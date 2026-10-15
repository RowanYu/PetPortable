import { speechRecognizer } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 语音监听模式：once 单句识别（VAD 自动结束）；continuous 长监听（本期占位） */
export type SpeechMode = 'once' | 'continuous';

/** 语音会话回调 */
export interface SpeechSessionCallbacks {
  onPartial(text: string): void;
  onFinal(text: string): void;
  onError(message: string): void;
}

const TAG: string = 'PetSpeech';
const SESSION_ID: string = 'pet_session';
const SAMPLE_RATE: number = 16000;
const MAX_ONCE_DURATION_MS: number = 15000;

/**
 * 端侧语音识别服务：AudioCapturer(16k PCM) → CoreSpeechKit 引擎 → partial/final 回调。
 * 设备不支持时 isAvailable() 返回 false，UI 层降级为文字输入。
 */
export class PetSpeechRecognizerService {
  private static instance: PetSpeechRecognizerService | undefined = undefined;
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private capturer: audio.AudioCapturer | undefined = undefined;
  private listening: boolean = false;
  private availabilityChecked: boolean = false;
  private availableCache: boolean = false;
  private startedAt: number = 0;
  private timeoutTimer: number = -1;

  private constructor() {
  }

  static getInstance(): PetSpeechRecognizerService {
    if (!PetSpeechRecognizerService.instance) {
      PetSpeechRecognizerService.instance = new PetSpeechRecognizerService();
    }
    return PetSpeechRecognizerService.instance;
  }

  /** 能力探测：尝试创建引擎一次并缓存结果（失败即设备不支持） */
  isAvailable(): boolean {
    const self: PetSpeechRecognizerService = PetSpeechRecognizerService.getInstance();
    if (!self.availabilityChecked) {
      self.availabilityChecked = true;
      const params: speechRecognizer.CreateEngineParams = {
        language: 'zh-CN',
        online: 1
      };
      speechRecognizer.createEngine(params).then((engine: speechRecognizer.SpeechRecognitionEngine) => {
        self.availableCache = true;
        engine.shutdown();
      }).catch((e: BusinessError) => {
        console.warn(`${TAG} probe unavailable: ${e.message}`);
        self.availableCache = false;
      });
    }
    return self.availableCache;
  }

  /** 申请麦克风权限；用户拒绝返回 false */
  static async requestMicPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
      for (let i: number = 0; i < result.authResults.length; i += 1) {
        if (result.authResults[i] === 0) {
          return true;
        }
      }
      return false;
    } catch (e) {
      console.warn(`${TAG} requestMicPermission failed: ${(e as BusinessError).message}`);
      return false;
    }
  }

  /**
   * 开始语音监听。
   * once：说完整句 VAD 自动 onFinal 并释放；continuous：本期占位，直接报错。
   * 会话进行中重复调用返回 false，不双开。
   */
  async startListening(petKey: string, mode: SpeechMode, cb: SpeechSessionCallbacks): Promise<boolean> {
    if (PetSpeechRecognizerService.getInstance().listening) {
      return false;
    }
    if (mode === 'continuous') {
      cb.onError('长监听模式待接入');
      return false;
    }

    const self: PetSpeechRecognizerService = PetSpeechRecognizerService.getInstance();
    self.listening = true;
    self.startedAt = Date.now();
    try {
      const engineReady: boolean = await self.ensureEngine(cb);
      if (!engineReady) {
        self.cleanup();
        return false;
      }
      await self.startCapture(cb);
      return true;
    } catch (e) {
      console.error(`${TAG} startListening failed: ${(e as BusinessError).message}`);
      cb.onError('语音启动失败，请用文字输入');
      self.cleanup();
      return false;
    }
  }

  /** 停止监听（幂等，重复调用安全） */
  stopListening(): void {
    const self: PetSpeechRecognizerService = PetSpeechRecognizerService.getInstance();
    if (!self.listening) {
      return;
    }
    try {
      if (self.engine) {
        self.engine.finish(SESSION_ID);
      }
    } catch (e) {
      console.warn(`${TAG} finish failed: ${(e as BusinessError).message}`);
    }
    self.cleanup();
  }

  private async ensureEngine(cb: SpeechSessionCallbacks): Promise<boolean> {
    const self: PetSpeechRecognizerService = PetSpeechRecognizerService.getInstance();
    if (self.engine) {
      return true;
    }
    const params: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1
    };
    const engine: speechRecognizer.SpeechRecognitionEngine = await speechRecognizer.createEngine(params);
    engine.setListener({
      onStart: (sessionId: string, eventMessage: string) => {
        console.info(`${TAG} onStart ${sessionId} ${eventMessage}`);
      },
      onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
        console.info(`${TAG} onEvent ${eventCode} ${eventMessage}`);
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        if (result.result.length > 0) {
          if (result.isFinal || result.isLast) {
            cb.onFinal(result.result);
          } else {
            cb.onPartial(result.result);
          }
        }
        if (result.isLast) {
          self.cleanup();
        }
      },
      onComplete: (sessionId: string, eventMessage: string) => {
        console.info(`${TAG} onComplete ${eventMessage}`);
        self.cleanup();
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        console.error(`${TAG} onError ${errorCode} ${errorMessage}`);
        cb.onError('语音识别出错，请再试一次');
        self.cleanup();
      }
    });
    self.engine = engine;
    self.availabilityChecked = true;
    self.availableCache = true;
    return true;
  }

  private async startCapture(cb: SpeechSessionCallbacks): Promise<void> {
    const self: PetSpeechRecognizerService = PetSpeechRecognizerService.getInstance();
    if (!self.engine) {
      return;
    }
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: SAMPLE_RATE,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };
    const capturerOptions: audio.AudioCapturerOptions = {
      streamInfo: streamInfo,
      capturerMode: audio.AudioCapturerMode.CAPTURE_MODE_NORMAL,
      capturerFlags: 0
    };
    const capturer: audio.AudioCapturer = await audio.createAudioCapturer(capturerOptions);
    self.capturer = capturer;

    const startParams: speechRecognizer.StartParams = {
      sessionId: SESSION_ID,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: SAMPLE_RATE,
        soundChannel: 1,
        sampleBit: 16
      }
    };
    self.engine.startListening(startParams);

    capturer.on('readData', (buffer: ArrayBuffer) => {
      if (!self.engine || !self.listening || buffer.byteLength === 0) {
        return;
      }
      try {
        // 引擎要求每次喂 640 或 1280 字节，按 1280 切片
        const chunkSize: number = 1280;
        const bytes: Uint8Array = new Uint8Array(buffer);
        for (let offset: number = 0; offset + chunkSize <= bytes.length; offset += chunkSize) {
          self.engine.writeAudio(SESSION_ID, bytes.slice(offset, offset + chunkSize));
        }
      } catch (e) {
        console.warn(`${TAG} writeAudio failed: ${(e as BusinessError).message}`);
      }
    });

    await capturer.start();

    // once 模式 15s 超时兜底
    self.timeoutTimer = setTimeout(() => {
      if (self.listening) {
        self.stopListening();
        cb.onError('没有听到说话，请再试一次');
      }
    }, MAX_ONCE_DURATION_MS);
  }

  /** 释放所有会话资源（异步收尾，调用处无需等待） */
  private cleanup(): void {
    const self: PetSpeechRecognizerService = PetSpeechRecognizerService.getInstance();
    self.listening = false;
    if (self.timeoutTimer !== -1) {
      clearTimeout(self.timeoutTimer);
      self.timeoutTimer = -1;
    }
    const capturer: audio.AudioCapturer | undefined = self.capturer;
    self.capturer = undefined;
    const engine: speechRecognizer.SpeechRecognitionEngine | undefined = self.engine;
    self.engine = undefined;
    if (capturer) {
      capturer.stop().then(() => {
        return capturer.release();
      }).catch((e: BusinessError) => {
        console.warn(`${TAG} capturer release failed: ${e.message}`);
      });
    }
    if (engine) {
      try {
        engine.shutdown();
      } catch (e) {
        console.warn(`${TAG} engine shutdown failed: ${(e as BusinessError).message}`);
      }
    }
  }
}
