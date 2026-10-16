import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { PetModel } from '../models/PetModel';
import { CommonConstants } from '../constants/CommonConstants';

const TAG: string = 'PetKokoroTtsService';
const CACHE_FILE_NAME: string = 'kokoro_tts.wav';
const LATIN_DOG_KEYS: string[] = ['golden', 'dog', 'corgi', 'akita'];
const CN_DOG_KEYS: string[] = ['犬', '狗', '金毛', '柯基', '秋田'];
// 播放启动兜底超时：防止 prepare 异常悬挂导致 ChatPage await 卡死
const PLAY_START_TIMEOUT_MS: number = 5000;

/**
 * Kokoro TTS 客户端（狗宠物少年音）
 * 流程：狗判定 -> POST /tts 下载 WAV -> 写 cacheDir -> AVPlayer(fdSrc) 播放。
 * 任一环节失败返回 false，绝不抛异常；调用方（ChatPage）据此回退现状文案。
 */
export class PetKokoroTtsService {
  private static instance: PetKokoroTtsService | undefined = undefined;

  private player: media.AVPlayer | undefined = undefined;
  private isPlaying: boolean = false;
  private openFd: number = -1;
  private playStartResolver: ((value: boolean) => void) | undefined = undefined;
  private playStartTimer: number = -1;
  private speakSeq: number = 0;   // 会话代次：stop/新 speak 递增，使 in-flight 会话失效
  private fdSession: number = -1; // 当前 openFd 所属会话代次

  private constructor() {
  }

  static getInstance(): PetKokoroTtsService {
    if (!PetKokoroTtsService.instance) {
      PetKokoroTtsService.instance = new PetKokoroTtsService();
    }
    return PetKokoroTtsService.instance;
  }

  /** 狗宠物判定：modelPath/breed 小写后命中任一关键词即为狗（coyote 郊狼不命中） */
  isDogVoiceEnabled(pet: PetModel): boolean {
    const modelPath: string = pet.modelPath.toLowerCase();
    const breed: string = pet.breed.toLowerCase();
    for (const key of LATIN_DOG_KEYS) {
      if (modelPath.includes(key) || breed.includes(key)) {
        return true;
      }
    }
    for (const key of CN_DOG_KEYS) {
      if (breed.includes(key)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 合成并播放。返回 true 表示已启动播放（不等待播完）；
   * 非狗/空文本/下载失败/播放失败一律返回 false。
   */
  async speak(pet: PetModel, text: string, context: common.UIAbilityContext): Promise<boolean> {
    const normalizedText: string = text.trim();
    if (!this.isDogVoiceEnabled(pet) || normalizedText.length === 0) {
      return false;
    }
    this.speakSeq += 1;
    const session: number = this.speakSeq;
    // 立即中断旧播放（旧 fd 在 await reset 后安全回收，避免 stopped 回调误杀新 fd）
    const player: media.AVPlayer = await this.ensurePlayer();
    await this.stopCurrentPlayback(player);
    try {
      const wavData: ArrayBuffer = await this.downloadWav(normalizedText);
      if (session !== this.speakSeq) {
        return false;
      }
      const cachePath: string = await this.writeCacheFile(wavData, context);
      if (session !== this.speakSeq) {
        return false;
      }
      return await this.playCacheFile(cachePath, session);
    } catch (e) {
      console.warn(`${TAG} speak failed: ${(e as Error).message}`);
      return false;
    }
  }

  /** 停止当前播放并复位（新回复开始前 / 页面退出时调用），并使 in-flight 会话失效 */
  stop(): void {
    this.speakSeq += 1;
    this.isPlaying = false;
    this.resolvePlayStart(false);
    const player: media.AVPlayer | undefined = this.player;
    if (!player) {
      return;
    }
    try {
      if (player.state === 'playing' || player.state === 'paused' || player.state === 'prepared'
        || player.state === 'initialized') {
        player.stop();
      }
    } catch (e) {
      console.warn(`${TAG} stop failed: ${(e as Error).message}`);
    }
  }

  private downloadWav(text: string): Promise<ArrayBuffer> {
    return new Promise<ArrayBuffer>((resolve: (value: ArrayBuffer) => void,
      reject: (reason: Error) => void) => {
      const httpRequest: http.HttpRequest = http.createHttp();
      httpRequest.request(CommonConstants.KOKORO_TTS_ENDPOINT, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json'
        },
        extraData: JSON.stringify({
          text: text,
          voice: CommonConstants.KOKORO_VOICE_DOG
        }),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: CommonConstants.KOKORO_CONNECT_TIMEOUT_MS,
        readTimeout: CommonConstants.KOKORO_TIMEOUT_MS
      }).then((response: http.HttpResponse): void => {
        if (response.responseCode === 200 && response.result instanceof ArrayBuffer) {
          resolve(response.result as ArrayBuffer);
        } else {
          reject(new Error(`Kokoro HTTP ${response.responseCode}`));
        }
      }).catch((err: BusinessError): void => {
        reject(new Error(`Kokoro 请求失败: ${err.message}`));
      }).finally((): void => {
        httpRequest.destroy();
      });
    });
  }

  private async writeCacheFile(wavData: ArrayBuffer, context: common.UIAbilityContext): Promise<string> {
    const cachePath: string = `${context.cacheDir}/${CACHE_FILE_NAME}`;
    const file = fs.openSync(cachePath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, wavData);
    } finally {
      fs.closeSync(file);
    }
    return cachePath;
  }

  private async playCacheFile(cachePath: string, session: number): Promise<boolean> {
    const player: media.AVPlayer = await this.ensurePlayer();
    try {
      this.fdSession = session;
      this.openFd = fs.openSync(cachePath, fs.OpenMode.READ_ONLY).fd;
      const stat = fs.statSync(this.openFd);
      player.fdSrc = { fd: this.openFd, offset: 0, length: stat.size };
    } catch (e) {
      this.closeOpenFd();
      throw e as Error;
    }

    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      this.playStartResolver = resolve;
      this.playStartTimer = setTimeout((): void => {
        console.warn(`${TAG} play start timeout`);
        this.resolvePlayStart(false);
      }, PLAY_START_TIMEOUT_MS);
    });
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    if (!this.player) {
      const player: media.AVPlayer = await media.createAVPlayer();
      this.setupPlayerCallbacks(player);
      this.player = player;
    }
    return this.player;
  }

  private async stopCurrentPlayback(player: media.AVPlayer): Promise<void> {
    this.isPlaying = false;
    this.resolvePlayStart(false);
    const state: string = player.state;
    if (state !== 'idle') {
      try {
        if (state === 'playing' || state === 'paused' || state === 'prepared' || state === 'initialized') {
          await player.stop();
        }
        // 必须等 reset 完成再回收 fd / 设置新 fdSrc（参照 PetActionSoundService 的惯例）
        await player.reset();
      } catch (e) {
        console.warn(`${TAG} stopCurrentPlayback failed: ${(e as Error).message}`);
      }
    }
    this.closeOpenFd();
  }

  private setupPlayerCallbacks(player: media.AVPlayer): void {
    player.on('stateChange', async (state: string, _reason: media.StateChangeReason): Promise<void> => {
      if (state === 'initialized') {
        try {
          await player.prepare();
        } catch (e) {
          console.error(`${TAG} prepare failed: ${(e as Error).message}`);
          this.resolvePlayStart(false);
        }
      } else if (state === 'prepared') {
        try {
          player.loop = false;
          await player.play();
          this.isPlaying = true;
          this.resolvePlayStart(true);
        } catch (e) {
          console.error(`${TAG} play failed: ${(e as Error).message}`);
          this.resolvePlayStart(false);
        }
      } else if (state === 'completed' || state === 'error') {
        this.isPlaying = false;
        this.closeOpenFd();
      } else if (state === 'stopped') {
        this.isPlaying = false;
        // 仅当 fd 已成孤儿（会话被取消且无新播放接管）时回收，
        // 避免旧播放的 stopped 回调误关新播放的 fd
        if (this.fdSession !== this.speakSeq) {
          this.closeOpenFd();
        }
      }
    });

    player.on('error', (error: BusinessError): void => {
      console.error(`${TAG} player error: ${error.code} ${error.message}`);
      this.isPlaying = false;
      this.resolvePlayStart(false);
    });
  }

  private resolvePlayStart(value: boolean): void {
    if (this.playStartResolver) {
      const resolver: ((value: boolean) => void) | undefined = this.playStartResolver;
      this.playStartResolver = undefined;
      if (this.playStartTimer >= 0) {
        clearTimeout(this.playStartTimer);
        this.playStartTimer = -1;
      }
      resolver(value);
    }
  }

  private closeOpenFd(): void {
    if (this.openFd >= 0) {
      try {
        fs.closeSync(this.openFd);
      } catch (e) {
        console.warn(`${TAG} close fd failed: ${(e as Error).message}`);
      }
      this.openFd = -1;
    }
  }
}
