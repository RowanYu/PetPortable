/**
 * 公共常量类，定义 UI 规范和业务限制
 */
export class CommonConstants {
  /**
   * 栅格系统基准 (8vp)
   */
  static readonly GRID_BASE: number = 8;

  /**
   * 默认间距
   */
  static readonly SPACE_12: number = 12;
  static readonly SPACE_16: number = 16;
  static readonly SPACE_24: number = 24;

  /**
   * 默认圆角
   */
  static readonly BORDER_RADIUS_16: number = 16;

  /**
   * 动画配置
   */
  static readonly CLICK_SCALE: number = 0.95;

  /**
   * 颜色常量 (建议优先使用 $r('sys.color.*'))
   */
  static readonly THEME_COLOR: string = '#007DFF';
  static readonly BACKGROUND_LIGHT_GRAY: string = '#F1F3F5';

  /**
   * 环境数据服务地址（img_server.py 的 /env HTTP 端点）
   * PC 端运行 img_server.py 后，App 通过此地址拉取 WS63 上报的温湿度
   *
   * 切换网络/换电脑时，必须把这里改为 PC 当前 WLAN IPv4。
   * 同时把同 IP 加到 entry/src/main/resources/base/profile/network_config.json 的
   * cleartextTraffic 白名单中（HarmonyOS 不允许明文 HTTP 访问未白名单域名）。
   *
   * 本地模拟器（同 PC）也可改为 '127.0.0.1'；模拟真机/真机必须用 PC 局域网 IP。
   */
  static readonly ENV_SERVER_HOST: string = '10.201.81.99';
  static readonly ENV_SERVER_PORT: number = 6790;
  static readonly ENV_ENDPOINT: string = `http://${CommonConstants.ENV_SERVER_HOST}:${CommonConstants.ENV_SERVER_PORT}/env`;

  /**
   * 素材中转服务地址（relay_server.py 监听的 HTTP 端点）
   * relay_server.py 使用 6791 端口，与 img_server.py 的 /env（6790）分离，
   * 避免两个服务抢同一端口导致 /swap 请求被打到 img_server.py 返回 501。
   *
   * 单一来源：变更主机时只需修改 ENV_SERVER_HOST，端口各自独立。
   * App 启动时由 Index.ets 调用 PetVideoRelayService.setRelayAddress() 同步。
   */
  static readonly RELAY_SERVER_HOST: string = CommonConstants.ENV_SERVER_HOST;
  static readonly RELAY_SERVER_PORT: number = 6791;
  static readonly RELAY_ENDPOINT: string = `http://${CommonConstants.RELAY_SERVER_HOST}:${CommonConstants.RELAY_SERVER_PORT}/swap`;

  /**
   * 环境阈值
   */
  static readonly TEMP_TOO_HIGH: number = 32;   // 温度过高阈值 (°C)
  static readonly HUMIDITY_TOO_HIGH: number = 80; // 湿度过高阈值 (%)
}
