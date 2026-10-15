import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PetActionType } from '../models/PetModel';
import { CommonConstants } from '../constants/CommonConstants';

const TAG: string = 'PetVideoRelayService';

// 中转服务连接配置
// - 本地模拟器（同 PC）：保持 127.0.0.1
// - 模拟真机（Remote Emulator，云端）：必须改为 PC 宿主机局域网 IP
// - 真机调试：必须改为 PC 宿主机局域网 IP，且 PC 防火墙放行该端口
// 改完直接 Run 即可生效，setRelayAddress() 调用优先级高于这里的默认值
// 默认值统一从 CommonConstants 读取，切换网络时只需改 CommonConstants.ENV_SERVER_HOST。
const DEFAULT_RELAY_HOST: string = CommonConstants.RELAY_SERVER_HOST;
const DEFAULT_RELAY_PORT: number = CommonConstants.RELAY_SERVER_PORT;

/**
 * 宠物素材中转服务
 * 当 App 端动作切换时，通过 HTTP 通知 PC 端 relay_server.py：
 *   1) 清空目标推流目录（金毛视频6秒）
 *   2) 根据中转服务当前模式快速放入对应素材（同盘硬链接，跨盘回退复制）
 * relay_server.py 的 watchdog 会自动触发 img_server.py 推流到 WS63 屏幕。
 *
 * App 端发送动作名称和宠物模型标识，由 relay_server.py 决定复制视频还是图片。
 * 模拟器访问 127.0.0.1 可直达宿主机；真机需改为局域网 IP。
 */
export class PetVideoRelayService {
  private static instance: PetVideoRelayService | undefined = undefined;

  // relay_server.py 监听地址（默认 127.0.0.1 适合本地模拟器；模拟真机/真机请改为 PC 局域网 IP）
  private relayHost: string = DEFAULT_RELAY_HOST;
  private relayPort: number = DEFAULT_RELAY_PORT;
  private readonly relayPath: string = '/swap';

  private lastRelayedAction: PetActionType | undefined = undefined;
  private lastRelayedProfile: string = '';

  private constructor() {
  }

  static getInstance(): PetVideoRelayService {
    if (!PetVideoRelayService.instance) {
      PetVideoRelayService.instance = new PetVideoRelayService();
    }
    return PetVideoRelayService.instance;
  }

  /**
   * 动态设置中转地址（切换模拟器/真机时用）。
   */
  setRelayAddress(host: string, port: number): void {
    this.relayHost = host;
    this.relayPort = port;
  }

  /**
   * 通知 PC 中转服务切换到动作对应的素材（视频或图片由中转服务模式决定）。
   * 动作未变则跳过；网络异常静默失败，不影响 App 主流程。
   */
  swapByAction(action: PetActionType, profile: string = ''): void {
    if (this.lastRelayedAction === action && this.lastRelayedProfile === profile) {
      return;
    }
    this.lastRelayedAction = action;
    this.lastRelayedProfile = profile;
    console.info(`${TAG} -> POST http://${this.relayHost}:${this.relayPort}${this.relayPath} action=${action} profile=${profile}`);
    void this.postSwap(action, profile);
  }

  /**
   * 强制触发一次切换（绕过 lastRelayedAction 去重），用于开发者面板的诊断按钮。
   * 即使与上次动作相同，PC 端仍会清空目标目录并重新复制对应素材。
   */
  forceSwapByAction(action: PetActionType, profile: string = ''): void {
    this.lastRelayedAction = undefined;
    this.lastRelayedProfile = '';
    console.info(`${TAG} -> force POST http://${this.relayHost}:${this.relayPort}${this.relayPath} action=${action} profile=${profile}`);
    void this.postSwap(action, profile);
  }

  /**
   * 主动探测中转服务是否可达（用于自检/排查 127.0.0.1 vs 局域网 IP 问题）。
   * 返回 true 表示连通；不修改 lastRelayedAction。
   */
  async ping(): Promise<boolean> {
    const url: string = `http://${this.relayHost}:${this.relayPort}/ping`;
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 1500,
        readTimeout: 3000,
        expectDataType: http.HttpDataType.STRING
      });
      const ok: boolean = response.responseCode === 200;
      console.info(`${TAG} ping ${url} -> ${response.responseCode} ok=${ok}`);
      return ok;
    } catch (e) {
      console.warn(`${TAG} ping ${url} failed: ${(e as BusinessError).message}`);
      return false;
    } finally {
      httpRequest.destroy();
    }
  }

  private async postSwap(action: PetActionType, profile: string): Promise<void> {
    try {
      const url: string = `http://${this.relayHost}:${this.relayPort}${this.relayPath}`;
      const body: string = JSON.stringify({ action: action, profile: profile });

      const httpRequest: http.HttpRequest = http.createHttp();
      const response: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: body,
        connectTimeout: 1500,
        readTimeout: 3000,
        expectDataType: http.HttpDataType.STRING
      });

      if (response.responseCode === 200) {
        console.info(`${TAG} relay OK: action=${action} resp=${response.result}`);
      } else {
        console.warn(`${TAG} relay HTTP ${response.responseCode}: action=${action} resp=${response.result}`);
      }

      httpRequest.destroy();
    } catch (e) {
      // 中转服务未启动或网络不通时静默失败
      console.warn(`${TAG} relay failed: ${(e as BusinessError).message}`);
    }
  }
}
