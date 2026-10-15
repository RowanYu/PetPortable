import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { resourceManager } from '@kit.LocalizationKit';
import { PetActionType } from '../models/PetModel';

const TAG: string = 'PetActionSoundService';

/**
 * 宠物动作音效服务
 * 在 ImageAnimator 播放序列帧的同时，同步播放对应的动作音效（MP3）。
 * idle / chat 不播放音效（chat 由 PetTtsService 负责语音播报）。
 */
export class PetActionSoundService {
  private static instance: PetActionSoundService | undefined = undefined;

  private player: media.AVPlayer | undefined = undefined;
  private touchPlayer: media.AVPlayer | undefined = undefined;
  private currentAction: PetActionType | undefined = undefined;
  private isPreparing: boolean = false;
  private pendingSoundFile: string = '';
  private currentSoundFile: string = '';
  private playContext: common.Context | undefined = undefined;
  // 动作音效播放完成回调（用于 PetSprite 协调图片与音频都完成后才回待机）
  onActionSoundCompleted: (() => void) | undefined = undefined;
  private isActionSound: boolean = false;

  private constructor() {
  }

  static getInstance(): PetActionSoundService {
    if (!PetActionSoundService.instance) {
      PetActionSoundService.instance = new PetActionSoundService();
    }
    return PetActionSoundService.instance;
  }

  /**
   * 根据动作播放对应音效；动作未变则不重复加载。
   * 需要传入 Context 以读取 rawfile 资源。
   */
  playActionSound(action: PetActionType, context: common.Context): void {
    const soundFile: string | undefined = this.resolveSoundResource(action);
    this.isActionSound = true;
    if (!soundFile) {
      void this.stop();
      this.currentAction = action;
      this.isPreparing = false;
      this.pendingSoundFile = '';
      this.currentSoundFile = '';
      // 无音频可播（如 idle/chat），立即通知完成
      if (this.onActionSoundCompleted) {
        this.onActionSoundCompleted();
      }
      return;
    }

    // 同一种动作也必须重新播放：手动过热/过湿可在回待机后再次触发，
    // 旧的 currentAction 缓存不能吞掉新的播放及 completed 回调。
    this.currentAction = action;
    this.pendingSoundFile = soundFile;
    void this.startPlay(soundFile, context);
  }

  /**
   * 播放传感器告警音（高温/过湿），独立于动作音效。
   */
  playAlertSound(type: 'temperature' | 'humidity', context: common.Context): void {
    this.isActionSound = false;
    const soundFile: string = type === 'temperature' ? 'alert_hot.mp3' : 'alert_wet.mp3';
    this.pendingSoundFile = soundFile;
    void this.startPlay(soundFile, context);
  }

  /**
   * 播放触摸音效（touch.mp3），独立于动作音效，每次触摸都触发。
   */
  playTouchSound(context: common.Context): void {
    void this.startTouchPlay(context);
  }

  private async startTouchPlay(context: common.Context): Promise<void> {
    try {
      let player: media.AVPlayer;
      if (!this.touchPlayer) {
        player = await media.createAVPlayer();
        this.touchPlayer = player;
        this.setupTouchPlayerCallbacks(player);
      } else {
        player = this.touchPlayer;
        // 已存在的播放器需 reset 回 idle，重新设置 fdSrc 才能触发 initialized→prepare→play
        if (player.state !== 'idle') {
          try {
            await player.reset();
          } catch (e) {
            console.warn(`${TAG} touch reset failed: ${(e as Error).message}`);
          }
        }
      }

      const fd: resourceManager.RawFileDescriptor = await context.resourceManager.getRawFd('touch.mp3');
      player.fdSrc = { fd: fd.fd, offset: fd.offset, length: fd.length };
    } catch (e) {
      console.error(`${TAG} touch sound failed: ${(e as Error).message}`);
    }
  }

  private setupTouchPlayerCallbacks(player: media.AVPlayer): void {
    player.on('stateChange', async (state: string, reason: media.StateChangeReason): Promise<void> => {
      if (state === 'initialized') {
        try {
          await player.prepare();
        } catch (e) {
          console.error(`${TAG} touch prepare failed: ${(e as Error).message}`);
        }
      } else if (state === 'prepared') {
        try {
          player.loop = false;
          await player.play();
        } catch (e) {
          console.error(`${TAG} touch play failed: ${(e as Error).message}`);
        }
      }
    });

    player.on('error', (error: BusinessError): void => {
      console.error(`${TAG} touch player error: ${error.code} ${error.message}`);
    });
  }

  async stop(): Promise<void> {
    if (!this.player) {
      this.isPreparing = false;
      this.currentAction = undefined;
      return;
    }
    try {
      if (this.player.state === 'playing' || this.player.state === 'paused') {
        await this.player.stop();
      }
    } catch (e) {
      console.warn(`${TAG} stop failed: ${(e as Error).message}`);
    }
    this.isPreparing = false;
    this.currentAction = undefined;
  }

  async release(): Promise<void> {
    this.currentAction = undefined;
    this.isPreparing = false;
    this.pendingSoundFile = '';
    this.currentSoundFile = '';
    this.playContext = undefined;
    if (this.player) {
      try {
        await this.player.release();
      } catch (e) {
        console.warn(`${TAG} release failed: ${(e as Error).message}`);
      }
      this.player = undefined;
    }
    if (this.touchPlayer) {
      try {
        await this.touchPlayer.release();
      } catch (e) {
        console.warn(`${TAG} touch release failed: ${(e as Error).message}`);
      }
      this.touchPlayer = undefined;
    }
  }

  /**
   * 准备完成后消费 pending：若切换期间又有新动作，则加载新音效，避免新动作音效丢失。
   */
  private consumePendingIfNeeded(): void {
    if (!this.pendingSoundFile || !this.playContext) {
      return;
    }
    if (this.pendingSoundFile === this.currentSoundFile) {
      this.pendingSoundFile = '';
      return;
    }
    const nextFile: string = this.pendingSoundFile;
    const nextContext: common.Context = this.playContext;
    this.pendingSoundFile = '';
    void this.startPlay(nextFile, nextContext);
  }

  private resolveSoundResource(action: PetActionType): string | undefined {
    switch (action) {
      case 'eat':
        return 'action_eat.mp3';
      case 'play':
        return 'action_play.mp3';
      case 'train':
        return 'action_play.mp3';
      case 'bath':
        return 'action_bath.mp3';
      case 'sleep':
        return 'action_sleep.mp3';
      case 'interact':
        // 摸头由触摸音效（touch.mp3）负责，不重复播放动作音效
        return undefined;
      case 'hot':
        return 'alert_hot.mp3';
      case 'wet':
        return 'alert_wet.mp3';
      case 'idle':
      case 'chat':
      default:
        return undefined;
    }
  }

  private async startPlay(soundFile: string, context: common.Context): Promise<void> {
    console.info(`${TAG} startPlay enter: file=${soundFile} isPreparing=${this.isPreparing}`);
    if (this.isPreparing) {
      this.pendingSoundFile = soundFile;
      console.info(`${TAG} startPlay deferred (isPreparing), queued as pending`);
      return;
    }
    this.isPreparing = true;
    this.currentSoundFile = soundFile;
    this.playContext = context;

    // 超时保护：若 5 秒内仍未进入 prepared（AVPlayer 卡在非预期状态），强制重建播放器
    const safetyTimerId: number = setTimeout((): void => {
      if (this.isPreparing && this.currentSoundFile === soundFile) {
        console.warn(`${TAG} isPreparing stuck for 5s, force-resetting`);
        this.isPreparing = false;
        if (this.player) {
          try {
            void this.player.release();
          } catch (e) {
            console.warn(`${TAG} safety release failed: ${(e as Error).message}`);
          }
          this.player = undefined;
        }
        if (this.pendingSoundFile) {
          const next: string = this.pendingSoundFile;
          this.pendingSoundFile = '';
          void this.startPlay(next, context);
        }
      }
    }, 5000);

    try {
      let player: media.AVPlayer;
      if (!this.player) {
        player = await media.createAVPlayer();
        this.player = player;
        console.info(`${TAG} created new AVPlayer, state=${player.state}`);
        this.setupPlayerCallbacks(context);
      } else {
        player = this.player;
        console.info(`${TAG} reuse AVPlayer, state=${player.state}`);
        let needRecreate: boolean = false;
        try {
          if (player.state === 'playing' || player.state === 'paused') {
            await player.stop();
            console.info(`${TAG} stop() ok, state=${player.state}`);
          }
          await player.reset();
          console.info(`${TAG} reset() ok, state=${player.state}`);
          if (player.state !== 'idle') {
            console.warn(`${TAG} player not idle after reset (state=${player.state}), will recreate`);
            needRecreate = true;
          }
        } catch (e) {
          console.warn(`${TAG} reuse failed: ${(e as Error).message}, will recreate`);
          needRecreate = true;
        }
        if (needRecreate) {
          try {
            await player.release();
          } catch (e) {
            console.warn(`${TAG} release old player failed: ${(e as Error).message}`);
          }
          player = await media.createAVPlayer();
          this.player = player;
          console.info(`${TAG} recreated AVPlayer after reuse failure, state=${player.state}`);
          this.setupPlayerCallbacks(context);
        }
      }

      const fd: resourceManager.RawFileDescriptor = await context.resourceManager.getRawFd(soundFile);
      console.info(`${TAG} getRawFd ok: fd=${fd.fd} offset=${fd.offset} length=${fd.length}`);
      player.fdSrc = { fd: fd.fd, offset: fd.offset, length: fd.length };
      console.info(`${TAG} fdSrc set, state=${player.state} (expect initialized soon)`);
    } catch (e) {
      console.error(`${TAG} startPlay failed: ${(e as Error).message}`);
      this.isPreparing = false;
      clearTimeout(safetyTimerId);
    }
  }

  private setupPlayerCallbacks(context: common.Context): void {
    if (!this.player) {
      return;
    }

    this.player.on('stateChange', async (state: string, reason: media.StateChangeReason): Promise<void> => {
      console.info(`${TAG} stateChange -> ${state} (reason=${reason})`);
      switch (state) {
        case 'initialized':
          try {
            await this.player!.prepare();
            console.info(`${TAG} prepare() ok, state=${this.player!.state}`);
          } catch (e) {
            console.error(`${TAG} prepare failed: ${(e as Error).message}`);
            this.isPreparing = false;
          }
          break;
        case 'prepared':
          try {
            this.player!.loop = false;
            this.player!.setVolume(1.0);
            await this.player!.play();
            console.info(`${TAG} play() ok, state=${this.player!.state}`);
            this.isPreparing = false;
            this.consumePendingIfNeeded();
          } catch (e) {
            console.error(`${TAG} play failed: ${(e as Error).message}`);
            this.isPreparing = false;
          }
          break;
        case 'playing':
          console.info(`${TAG} ENTERED playing, file=${this.currentSoundFile}`);
          break;
        case 'completed':
          console.info(`${TAG} completed, file=${this.currentSoundFile}`);
          // 动作音效播完一遍，通知 PetSprite（loop=false 已确保只播一遍）
          if (this.isActionSound && this.onActionSoundCompleted) {
            this.onActionSoundCompleted();
          }
          break;
        case 'error':
          console.error(`${TAG} stateChange reports error state`);
          this.isPreparing = false;
          break;
        default:
          break;
      }
    });

    this.player.on('error', (error: BusinessError): void => {
      console.error(`${TAG} player error event: code=${error.code} msg=${error.message}`);
      this.isPreparing = false;
    });
  }
}
