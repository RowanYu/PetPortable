import { common } from '@kit.AbilityKit';
import { CommonConstants } from '../constants/CommonConstants';
import { PetActionType, PetModel } from '../models/PetModel';
import { PetActionService, PetMotionProfile } from '../services/PetActionService';
import { InteractionService } from '../services/InteractionService';
import { PetStageAssetResolver, PetStageVisual } from '../services/PetStageAssetResolver';
import { PetCuteVoiceService, PetTouchBodyPart, PetTouchReactionPlan } from '../services/PetCuteVoiceService';
import { PetTtsService } from '../services/PetTtsService';
import { PetActionSoundService } from '../services/PetActionSoundService';
import { PetSensorService } from '../services/PetSensorService';
import { PetVideoRelayService } from '../services/PetVideoRelayService';
import { Live2DPetView } from './Live2DPetView';

const LIVE2D_REAL_PREFIX: string = 'live2d_real:';

interface ActionSequenceFrame {
  duration: number;
  motionOffsetYExtra: number;
  bodyScaleXExtra: number;
  bodyScaleYExtra: number;
  actionRotateYExtra: number;
  tiltZExtra: number;
  auraScaleExtra: number;
  auraOpacityExtra: number;
  shadowScaleXExtra: number;
  shadowScaleYExtra: number;
  accentOffsetX: number;
  accentOffsetY: number;
  accentScale: number;
  accentOpacity: number;
}

interface CatLayerLayout {
  size: number;
  offsetX: number;
  offsetY: number;
}

const CAT_TAIL_LAYOUT: CatLayerLayout = { size: 126, offsetX: 98, offsetY: 82 };
const CAT_LEFT_EAR_LAYOUT: CatLayerLayout = { size: 118, offsetX: -54, offsetY: -104 };
const CAT_RIGHT_EAR_LAYOUT: CatLayerLayout = { size: 118, offsetX: 54, offsetY: -104 };
const CAT_LEFT_LEG_LAYOUT: CatLayerLayout = { size: 96, offsetX: -44, offsetY: 124 };
const CAT_RIGHT_LEG_LAYOUT: CatLayerLayout = { size: 96, offsetX: 44, offsetY: 124 };
const CAT_TORSO_LAYOUT: CatLayerLayout = { size: 248, offsetX: 0, offsetY: 42 };
const CAT_HEAD_LAYOUT: CatLayerLayout = { size: 220, offsetX: 0, offsetY: -74 };
const CAT_FACE_LAYOUT: CatLayerLayout = { size: 220, offsetX: 0, offsetY: -64 };
const CAT_EFFECT_LAYOUT: CatLayerLayout = { size: 204, offsetX: 0, offsetY: -86 };
const GOLDEN_FRAME_DURATION: number = 167; // 6 FPS（约 167ms/帧）
const GOLDEN_IDLE_FRAME_DURATION: number = 167; // 待机 6 FPS（约 167ms/帧）
const LIVE2D_MAO_FRAME_DURATION: number = 250; // Live2D 待机采样 4 FPS

@Component
export struct PetSprite {
  @ObjectLink pet: PetModel;

  @State petRotationY: number = 0;
  @State interactionScale: number = 1;
  @State floatOffsetY: number = -10;
  @State bodyScaleX: number = 1.02;
  @State bodyScaleY: number = 1.03;
  @State actionRotateY: number = 0;
  @State tiltZ: number = -1;
  @State auraScale: number = 1.04;
  @State auraOpacity: number = 0.18;
  @State shadowScaleX: number = 0.98;
  @State shadowScaleY: number = 0.92;
  @State bodyOpacity: number = 1;
  @State effectOpacity: number = 0.12;
  @State effectOffsetY: number = -8;
  @State motionDuration: number = 1800;
  @State motionOffsetYExtra: number = 0;
  @State bodyScaleXExtra: number = 0;
  @State bodyScaleYExtra: number = 0;
  @State actionRotateYExtra: number = 0;
  @State tiltZExtra: number = 0;
  @State auraScaleExtra: number = 0;
  @State auraOpacityExtra: number = 0;
  @State shadowScaleXExtra: number = 0;
  @State shadowScaleYExtra: number = 0;
  @State accentOffsetX: number = 0;
  @State accentOffsetY: number = 0;
  @State accentScale: number = 1;
  @State accentOpacity: number = 0;

  private lastResolvedAction: PetActionType = 'idle';
  private lastResolvedProfile: string = '';
  private actionLoopId: number = -1;
  private actionResetTimerId: number = -1;
  private actionResetFallbackTimerId: number = -1;
  private actionStepIndex: number = 0;
  // 图片与音频协调：两者都完成后才回待机
  private imagePlayedOut: boolean = false;
  private soundPlayedOut: boolean = false;
  private isTouchReacting: boolean = false;
  private readonly cuteVoiceService: PetCuteVoiceService = PetCuteVoiceService.getInstance();
  private readonly ttsService: PetTtsService = PetTtsService.getInstance();
  private readonly actionSoundService: PetActionSoundService = PetActionSoundService.getInstance();
  private readonly videoRelayService: PetVideoRelayService = PetVideoRelayService.getInstance();
  private lastSpokenActionVersion: number = 0;
  private lastSpokenSpeech: string = '';
  private abilityContext: common.Context | undefined = undefined;

  aboutToAppear(): void {
    this.lastResolvedAction = this.pet.currentAction;
    this.lastResolvedProfile = this.pet.modelPath;
    this.lastSpokenActionVersion = this.pet.actionVersion;
    this.lastSpokenSpeech = this.pet.currentSpeech.trim();
    this.ttsService.ensureEngine();
    this.abilityContext = getContext(this) as common.Context;
    // 动作音效播放完成时标记 soundPlayedOut，与图片播完协调回待机
    this.actionSoundService.onActionSoundCompleted = (): void => {
      this.soundPlayedOut = true;
      this.tryResetAction();
    };
    this.applyMotionProfile(this.pet.currentAction);
    this.startActionLoop(this.pet.currentAction);
    this.triggerActionSideEffects(this.pet.currentAction);
  }

  aboutToDisappear(): void {
    this.stopActionLoop();
    this.actionSoundService.onActionSoundCompleted = undefined;
    this.ttsService.stop();
    void this.actionSoundService.stop();
  }

  private resolveVisual(): PetStageVisual {
    return PetStageAssetResolver.resolve(this.pet);
  }

  private syncActionProfile(): void {
    if (this.lastResolvedAction === this.pet.currentAction &&
      this.lastResolvedProfile === this.pet.modelPath) {
      return;
    }

    this.lastResolvedAction = this.pet.currentAction;
    this.lastResolvedProfile = this.pet.modelPath;
    this.applyMotionProfile(this.pet.currentAction);
    this.startActionLoop(this.pet.currentAction);
    this.triggerActionSideEffects(this.pet.currentAction);
  }

  private applyMotionProfile(action: PetActionType): void {
    const profile: PetMotionProfile = PetActionService.resolveMotion(action);
    this.floatOffsetY = profile.floatOffsetY;
    this.bodyScaleX = profile.scaleX;
    this.bodyScaleY = profile.scaleY;
    this.actionRotateY = profile.rotateY;
    this.tiltZ = profile.tiltZ;
    this.auraScale = profile.auraScale;
    this.auraOpacity = profile.auraOpacity;
    this.shadowScaleX = profile.shadowScaleX;
    this.shadowScaleY = profile.shadowScaleY;
    this.bodyOpacity = profile.bodyOpacity;
    this.effectOpacity = profile.effectOpacity;
    this.effectOffsetY = profile.effectOffset;
    this.motionDuration = profile.animationDuration;
    this.resetActionAccents();
  }

  private async handleTouchByBodyPart(bodyPart: PetTouchBodyPart | undefined): Promise<void> {
    if (this.isTouchReacting) {
      return;
    }
    this.isTouchReacting = true;
    this.interactionScale = 0.95;
    try {
      this.pet.currentSpeech = '哈哈，好痒啊，主人。';
      const plan: PetTouchReactionPlan = bodyPart
        ? this.cuteVoiceService.buildTouchReactionByBodyPart(this.pet, bodyPart)
        : this.cuteVoiceService.buildRandomTouchReaction(this.pet);
      void this.applyTouchReaction(plan);
    } finally {
      setTimeout(() => {
        this.interactionScale = 1;
      }, 180);
      this.isTouchReacting = false;
    }
  }

  private handlePetImageTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Down) {
      return;
    }
    if (this.resolveFramePrefix() === 'golden') {
      // 金毛：点击直触发摸头图片（feel_head）+ 触摸音效（touch.mp3）
      if (this.abilityContext) {
        this.actionSoundService.playTouchSound(this.abilityContext);
      }
      this.interactionScale = 0.95;
      setTimeout(() => {
        this.interactionScale = 1;
      }, 180);
      void InteractionService.getInstance().pet(this.pet);
    } else {
      void this.handleTouchByBodyPart(undefined);
    }
  }

  private async applyTouchReaction(plan: PetTouchReactionPlan): Promise<void> {
    const service: InteractionService = InteractionService.getInstance();
    if (plan.actionType === 'speak') {
      return;
    }
    if (plan.actionType === 'play') {
      await service.play(this.pet, { toyId: plan.toyId, duration: 22_000 });
      return;
    }
    if (plan.actionType === 'train') {
      await service.train(this.pet, plan.commandId);
      return;
    }
    if (plan.actionType === 'chat') {
      await service.chat(this.pet, plan.promptText);
      return;
    }
    await service.pet(this.pet);
  }

  private resetActionAccents(): void {
    this.motionOffsetYExtra = 0;
    this.bodyScaleXExtra = 0;
    this.bodyScaleYExtra = 0;
    this.actionRotateYExtra = 0;
    this.tiltZExtra = 0;
    this.auraScaleExtra = 0;
    this.auraOpacityExtra = 0;
    this.shadowScaleXExtra = 0;
    this.shadowScaleYExtra = 0;
    this.accentOffsetX = 0;
    this.accentOffsetY = 0;
    this.accentScale = 1;
    this.accentOpacity = 0;
  }

  private stopActionLoop(): void {
    if (this.actionLoopId >= 0) {
      clearTimeout(this.actionLoopId);
      this.actionLoopId = -1;
    }
    this.stopActionReset();
  }

  private stopActionReset(): void {
    if (this.actionResetTimerId >= 0) {
      clearTimeout(this.actionResetTimerId);
      this.actionResetTimerId = -1;
    }
    if (this.actionResetFallbackTimerId >= 0) {
      clearTimeout(this.actionResetFallbackTimerId);
      this.actionResetFallbackTimerId = -1;
    }
  }

  private startActionLoop(action: PetActionType): void {
    this.stopActionLoop();
    this.actionStepIndex = 0;
    this.imagePlayedOut = false;
    this.soundPlayedOut = false;
    this.resetActionAccents();
    const sequence: ActionSequenceFrame[] = this.resolveActionSequence(action);
    this.scheduleNextActionFrame(action, sequence);
    this.scheduleActionReset(action);
  }

  // 金毛：根据图片遍数总时长 + 介绍时间精确调度回待机，不依赖 ImageAnimator.onFinish 触发时机
  private scheduleActionReset(action: PetActionType): void {
    this.stopActionReset();
    if (this.resolveFramePrefix() !== 'golden') {
      return;
    }
    // idle 持续循环；sleep 停留最后一张；自动模式 hot/wet 持续循环
    if (action === 'idle' || action === 'sleep') {
      return;
    }
    if ((action === 'hot' || action === 'wet') && !PetSensorService.isManualExtremeReaction()) {
      return;
    }
    const frames: ImageFrameInfo[] = this.resolvePetFrames(action);
    const iterations: number = this.resolveIterations();
    let totalDuration: number = 0;
    for (const frame of frames) {
      const frameDuration: number | undefined = frame.duration;
      if (frameDuration !== undefined) {
        totalDuration += frameDuration;
      }
    }
    const resetDelay: number = totalDuration * iterations + this.resolveIntroDelay();
    const actionVersion: number = this.pet.actionVersion;
    this.actionResetTimerId = setTimeout(() => {
      if (this.pet.actionVersion !== actionVersion || this.pet.currentAction !== action) {
        return;
      }
      // 图片已播完，标记并尝试回待机（需 MP3 也播完）
      this.imagePlayedOut = true;
      this.tryResetAction();
    }, resetDelay);
    // AVPlayer 在异常或切后台时可能不发 completed。图片播完后最多再等 2 秒，
    // 防止动作永久停留并阻塞待机素材；正常情况下仍由真实音频回调立即复位。
    this.actionResetFallbackTimerId = setTimeout(() => {
      if (this.pet.actionVersion !== actionVersion || this.pet.currentAction !== action) {
        return;
      }
      this.soundPlayedOut = true;
      this.tryResetAction();
    }, resetDelay + 2000);
  }

  // 图片与音频都播放完成后才回待机；中途切换由 startActionLoop 重置标志，避免误触发
  private tryResetAction(): void {
    if (!this.imagePlayedOut || !this.soundPlayedOut) {
      return;
    }
    if (this.pet.currentAction === 'idle') {
      return; // 已待机，避免重复 reset 循环
    }
    this.imagePlayedOut = false;
    this.soundPlayedOut = false;
    PetActionService.resetToIdle(this.pet);
  }

  private scheduleNextActionFrame(action: PetActionType, sequence: ActionSequenceFrame[]): void {
    if (sequence.length === 0) {
      return;
    }

    const frame: ActionSequenceFrame = sequence[this.actionStepIndex % sequence.length];
    this.applySequenceFrame(frame);
    this.actionLoopId = setTimeout(() => {
      if (this.pet.currentAction !== action) {
        return;
      }

      this.actionStepIndex = (this.actionStepIndex + 1) % sequence.length;
      this.scheduleNextActionFrame(action, sequence);
    }, frame.duration);
  }

  private applySequenceFrame(frame: ActionSequenceFrame): void {
    this.motionDuration = frame.duration;
    this.motionOffsetYExtra = frame.motionOffsetYExtra;
    this.bodyScaleXExtra = frame.bodyScaleXExtra;
    this.bodyScaleYExtra = frame.bodyScaleYExtra;
    this.actionRotateYExtra = frame.actionRotateYExtra;
    this.tiltZExtra = frame.tiltZExtra;
    this.auraScaleExtra = frame.auraScaleExtra;
    this.auraOpacityExtra = frame.auraOpacityExtra;
    this.shadowScaleXExtra = frame.shadowScaleXExtra;
    this.shadowScaleYExtra = frame.shadowScaleYExtra;
    this.accentOffsetX = frame.accentOffsetX;
    this.accentOffsetY = frame.accentOffsetY;
    this.accentScale = frame.accentScale;
    this.accentOpacity = frame.accentOpacity;
  }

  private resolveActionSequence(action: PetActionType): ActionSequenceFrame[] {
    switch (action) {
      case 'interact':
        return [
          this.createFrame(220, -12, 0.03, 0.03, 6, 2, 0.06, 0.05, 0.02, -0.02, 16, -24, 1.12, 0.3),
          this.createFrame(260, -2, 0.01, 0.01, 0, -1, 0.03, 0.03, 0.00, 0.00, 12, -12, 0.98, 0.24),
          this.createFrame(240, -8, 0.02, 0.02, -4, -2, 0.04, 0.04, -0.01, 0.01, 20, -20, 1.04, 0.28)
        ];
      case 'eat':
        return [
          this.createFrame(180, 8, 0.02, 0.00, -3, -5, 0.02, 0.02, 0.03, -0.03, 18, 30, 0.92, 0.34),
          this.createFrame(260, 1, 0.01, 0.01, 2, 2, 0.03, 0.03, 0.01, -0.01, 6, 18, 1.06, 0.28),
          this.createFrame(320, -7, 0.00, 0.02, 0, -1, 0.05, 0.04, -0.02, 0.02, 2, -8, 1.04, 0.22)
        ];
      case 'chat':
        return [
          this.createFrame(240, -4, 0.01, 0.01, 7, -5, 0.03, 0.04, 0, 0, 18, -18, 0.96, 0.30),
          this.createFrame(220, 10, 0.02, 0.02, 0, 1, 0.04, 0.04, 0.02, -0.02, 28, -6, 1.08, 0.34),
          this.createFrame(240, -5, 0.01, 0.01, -7, 5, 0.03, 0.03, -0.01, 0.01, 20, -20, 0.98, 0.28)
        ];
      case 'sleep':
        return [
          this.createFrame(840, 3, 0.00, 0.02, -1, -3, -0.02, -0.02, -0.03, 0.02, 18, -28, 0.92, 0.20),
          this.createFrame(620, 1, 0.00, 0.01, 0, -2, 0.00, -0.01, -0.02, 0.01, 26, -44, 1.00, 0.24),
          this.createFrame(920, -5, 0.01, 0.00, 1, -1, 0.02, 0.02, 0.02, -0.01, 34, -62, 1.10, 0.18)
        ];
      case 'play':
        return [
          this.createFrame(220, -10, 0.03, 0.03, 4, 4, 0.06, 0.06, 0.04, -0.03, -12, -20, 1.15, 0.28),
          this.createFrame(240, 4, 0.01, 0.01, -3, -3, 0.02, 0.04, -0.02, 0.02, 14, -10, 0.96, 0.22),
          this.createFrame(260, -2, 0.01, 0.01, 2, 2, 0.04, 0.04, 0.01, -0.01, 0, -16, 1.05, 0.24)
        ];
      case 'train':
        return [
          this.createFrame(260, -8, 0.02, 0.03, 2, 1, 0.04, 0.03, 0.01, -0.01, -16, -22, 1.06, 0.24),
          this.createFrame(220, 2, 0.01, 0.01, 6, -2, 0.03, 0.03, 0.00, 0.00, 18, -10, 1.0, 0.26),
          this.createFrame(240, -4, 0.01, 0.02, -3, 2, 0.02, 0.02, -0.01, 0.01, 6, -16, 0.98, 0.22)
        ];
      case 'bath':
        return [
          this.createFrame(240, -4, 0.01, 0.01, -4, -1, 0.03, 0.04, 0.02, -0.02, -20, -12, 1.02, 0.2),
          this.createFrame(280, 6, 0.02, 0.02, 3, 2, 0.05, 0.04, -0.01, 0.02, 20, -24, 1.08, 0.24),
          this.createFrame(260, -3, 0.01, 0.01, 0, -1, 0.03, 0.03, 0.00, 0.00, 8, -14, 1.00, 0.2)
        ];
      case 'hot':
        // 过热：喘息式轻微起伏
        return [
          this.createFrame(220, -3, 0.00, 0.02, 0, -1, 0.02, 0.02, 0.00, 0.00, 0, -10, 0.96, 0.18),
          this.createFrame(200, 4, 0.01, 0.03, 0, 1, 0.03, 0.03, 0.01, -0.01, 0, -6, 1.04, 0.22),
          this.createFrame(240, -2, 0.00, 0.01, 0, 0, 0.02, 0.02, 0.00, 0.00, 0, -12, 0.98, 0.16)
        ];
      case 'wet':
        // 过湿：轻微抖动
        return [
          this.createFrame(180, -2, 0.01, 0.01, -3, -1, 0.02, 0.02, 0.01, -0.01, -8, -10, 1.02, 0.18),
          this.createFrame(200, 3, 0.02, 0.02, 3, 1, 0.03, 0.03, -0.01, 0.01, 8, -12, 0.98, 0.22),
          this.createFrame(220, -2, 0.01, 0.01, -2, 0, 0.02, 0.02, 0.00, 0.00, -4, -8, 1.00, 0.16),
          this.createFrame(180, 2, 0.02, 0.02, 2, 1, 0.03, 0.03, 0.01, -0.01, 4, -10, 1.02, 0.20)
        ];
      case 'idle':
      default:
        return [
          this.createFrame(1200, -2, 0.00, 0.01, 0, -0.6, 0.00, 0.00, -0.015, 0.01, 0, -4, 1.00, 0.08),
          this.createFrame(1200, 2, 0.01, 0.01, 0, 0.6, 0.00, 0.00, 0.015, -0.01, 0, 0, 1.00, 0.08)
        ];
    }
  }

  private createFrame(duration: number, motionOffsetYExtra: number, bodyScaleXExtra: number,
    bodyScaleYExtra: number, actionRotateYExtra: number, tiltZExtra: number, auraScaleExtra: number,
    auraOpacityExtra: number, shadowScaleXExtra: number, shadowScaleYExtra: number, accentOffsetX: number,
    accentOffsetY: number, accentScale: number, accentOpacity: number): ActionSequenceFrame {
    return {
      duration,
      motionOffsetYExtra,
      bodyScaleXExtra,
      bodyScaleYExtra,
      actionRotateYExtra,
      tiltZExtra,
      auraScaleExtra,
      auraOpacityExtra,
      shadowScaleXExtra,
      shadowScaleYExtra,
      accentOffsetX,
      accentOffsetY,
      accentScale,
      accentOpacity
    };
  }

  private resolveBodyScale(): number {
    const baseScale: number = (this.bodyScaleX + this.bodyScaleY) / 2;
    const extraScale: number = (this.bodyScaleXExtra + this.bodyScaleYExtra) / 2;
    const scale: number = (baseScale + extraScale) * this.interactionScale;
    return Math.max(0.96, Math.min(1.08, scale));
  }

  private resolvePetRotateY(): number {
    const rotateY: number = this.petRotationY + this.actionRotateY + this.actionRotateYExtra;
    return Math.max(-12, Math.min(12, rotateY));
  }

  private resolvePetTiltZ(): number {
    const tiltZ: number = this.tiltZ + this.tiltZExtra;
    return Math.max(-5, Math.min(5, tiltZ));
  }

  private shouldUseFrameAnimator(): boolean {
    const modelPath: string = this.pet.modelPath.toLowerCase();
    return modelPath.includes('duck') || modelPath.includes('fox') ||
      modelPath.includes('golden') || modelPath.includes('live2d_mao');
  }

  private shouldUseLayeredCat(): boolean {
    return this.pet.modelPath.toLowerCase().includes('cat');
  }

  private shouldUseRealLive2D(): boolean {
    return this.pet.modelPath.toLowerCase().startsWith(LIVE2D_REAL_PREFIX);
  }

  private resolveRealLive2DModelName(): string {
    const path: string = this.pet.modelPath;
    const lower: string = path.toLowerCase();
    if (lower.startsWith(LIVE2D_REAL_PREFIX)) {
      return path.substring(LIVE2D_REAL_PREFIX.length);
    }
    return 'mao_pro';
  }

  private resolveFramePrefix(): string {
    const modelPath: string = this.pet.modelPath.toLowerCase();
    if (modelPath.includes('fox')) {
      return 'fox';
    }
    if (modelPath.includes('golden')) {
      return 'golden';
    }
    if (modelPath.includes('cat')) {
      return 'cat';
    }
    if (modelPath.includes('live2d_mao')) {
      return 'live2d_mao';
    }
    return 'duck';
  }

  private resolveFrameAction(): PetActionType {
    switch (this.pet.currentAction) {
      case 'eat':
        return 'eat';
      case 'chat':
      case 'play':
      case 'train':
      case 'interact':
        return 'chat';
      case 'sleep':
        return 'sleep';
      case 'bath':
      case 'idle':
      default:
        return 'idle';
    }
  }

  private createAnimatorFrame(src: Resource, duration: number): ImageFrameInfo {
    return {
      src: src,
      duration: duration
    };
  }

  private resolveFrameResource(prefix: string, action: PetActionType, frameIndex: number): Resource {
    if (prefix === 'fox') {
      if (action === 'eat') {
        return frameIndex === 1 ? $r('app.media.fox_eat_01') : (frameIndex === 2 ? $r('app.media.fox_eat_02') : $r('app.media.fox_eat_03'));
      }
      if (action === 'chat') {
        return frameIndex === 1 ? $r('app.media.fox_chat_01') : (frameIndex === 2 ? $r('app.media.fox_chat_02') : $r('app.media.fox_chat_03'));
      }
      if (action === 'sleep') {
        return frameIndex === 1 ? $r('app.media.fox_sleep_01') : (frameIndex === 2 ? $r('app.media.fox_sleep_02') : $r('app.media.fox_sleep_03'));
      }
      return frameIndex === 1 ? $r('app.media.fox_idle_01') : (frameIndex === 2 ? $r('app.media.fox_idle_02') : $r('app.media.fox_idle_03'));
    }

    if (prefix === 'golden') {
      if (action === 'eat') {
        return frameIndex === 1 ? $r('app.media.golden_eat_01') : (frameIndex === 2 ? $r('app.media.golden_eat_02') : $r('app.media.golden_eat_03'));
      }
      if (action === 'chat') {
        return frameIndex === 1 ? $r('app.media.golden_chat_01') : (frameIndex === 2 ? $r('app.media.golden_chat_02') : $r('app.media.golden_chat_03'));
      }
      if (action === 'sleep') {
        return frameIndex === 1 ? $r('app.media.golden_sleep_01') : (frameIndex === 2 ? $r('app.media.golden_sleep_02') : $r('app.media.golden_sleep_03'));
      }
      return frameIndex === 1 ? $r('app.media.golden_idle_01') : (frameIndex === 2 ? $r('app.media.golden_idle_02') : $r('app.media.golden_idle_03'));
    }

    if (prefix === 'cat') {
      if (action === 'eat') {
        return frameIndex === 1 ? $r('app.media.cat_eat_01') : (frameIndex === 2 ? $r('app.media.cat_eat_02') : $r('app.media.cat_eat_03'));
      }
      if (action === 'chat') {
        return frameIndex === 1 ? $r('app.media.cat_chat_01') : (frameIndex === 2 ? $r('app.media.cat_chat_02') : $r('app.media.cat_chat_03'));
      }
      if (action === 'sleep') {
        return frameIndex === 1 ? $r('app.media.cat_sleep_01') : (frameIndex === 2 ? $r('app.media.cat_sleep_02') : $r('app.media.cat_sleep_03'));
      }
      return frameIndex === 1 ? $r('app.media.cat_idle_01') : (frameIndex === 2 ? $r('app.media.cat_idle_02') : $r('app.media.cat_idle_03'));
    }

    return $r('app.media.pet_duck_full');
  }

  private resolveGoldenEatFrames(): ImageFrameInfo[] {
    return [
      this.createAnimatorFrame($r('app.media.golden_eat_01'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_02'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_03'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_04'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_05'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_06'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_07'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_08'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_09'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_10'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_11'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_12'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_13'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_14'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_15'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_16'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_17'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_18'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_19'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_20'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_21'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_22'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_23'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_24'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_25'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_26'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_27'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_28'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_29'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_30'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_31'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_32'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_33'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_34'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_35'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_36'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_37'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_38'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_39'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_40'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_eat_41'), GOLDEN_FRAME_DURATION)
    ];
  }

  private resolveGoldenIdleFrames(): ImageFrameInfo[] {
    return [
      this.createAnimatorFrame($r('app.media.golden_idle_01'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_02'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_03'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_04'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_05'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_06'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_07'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_08'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_09'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_10'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_11'), GOLDEN_IDLE_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_idle_12'), GOLDEN_IDLE_FRAME_DURATION)
    ];
  }

  private resolveGoldenChatFrames(): ImageFrameInfo[] {
    return [
      this.createAnimatorFrame($r('app.media.golden_chat_01'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_chat_02'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_chat_03'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_chat_04'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_chat_05'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_chat_06'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_chat_07'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_chat_08'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_chat_09'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_chat_10'), GOLDEN_FRAME_DURATION)
    ];
  }

  private resolveGoldenSleepFrames(): ImageFrameInfo[] {
    return [
      this.createAnimatorFrame($r('app.media.golden_sleep_01'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_sleep_02'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_sleep_03'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_sleep_04'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_sleep_05'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_sleep_06'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_sleep_07'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_sleep_08'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_sleep_09'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_sleep_10'), GOLDEN_FRAME_DURATION)
    ];
  }

  private resolveGoldenBathFrames(): ImageFrameInfo[] {
    return [
      this.createAnimatorFrame($r('app.media.golden_bath_01'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_bath_02'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_bath_03'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_bath_04'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_bath_05'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_bath_06'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_bath_07'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_bath_08'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_bath_09'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_bath_10'), GOLDEN_FRAME_DURATION)
    ];
  }

  private resolveGoldenFeelHeadFrames(): ImageFrameInfo[] {
    return [
      this.createAnimatorFrame($r('app.media.golden_feel_head_01'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_02'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_03'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_04'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_05'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_06'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_07'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_08'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_09'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_10'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_11'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_12'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_13'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_14'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_15'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_16'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_17'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_18'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_19'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_20'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_21'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_22'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_23'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_24'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_25'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_26'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_27'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_28'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_29'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_30'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_31'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_feel_head_32'), GOLDEN_FRAME_DURATION)
    ];
  }

  // 金毛过热序列（金毛过热文件夹，20 帧）
  private resolveGoldenHotFrames(): ImageFrameInfo[] {
    return [
      this.createAnimatorFrame($r('app.media.golden_hot_01'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_02'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_03'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_04'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_05'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_06'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_07'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_08'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_09'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_10'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_11'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_12'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_13'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_14'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_15'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_16'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_17'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_18'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_19'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_hot_20'), GOLDEN_FRAME_DURATION)
    ];
  }

  // 金毛过湿序列（金毛过湿文件夹，13 帧）
  private resolveGoldenWetFrames(): ImageFrameInfo[] {
    return [
      this.createAnimatorFrame($r('app.media.golden_shi_01'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_02'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_03'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_04'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_05'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_06'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_07'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_08'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_09'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_10'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_11'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_12'), GOLDEN_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.golden_shi_13'), GOLDEN_FRAME_DURATION)
    ];
  }

  // 金毛：根据文件夹命名匹配的多帧调度，所有动作均按 24 FPS 播放
  private resolveGoldenFrames(action: PetActionType): ImageFrameInfo[] {
    switch (action) {
      case 'eat':
        return this.resolveGoldenEatFrames();
      case 'interact':
        return this.resolveGoldenFeelHeadFrames();
      case 'sleep':
        return this.resolveGoldenSleepFrames();
      case 'bath':
        return this.resolveGoldenBathFrames();
      case 'hot':
        return this.resolveGoldenHotFrames();
      case 'wet':
        return this.resolveGoldenWetFrames();
      case 'chat':
      case 'play':
      case 'train':
        // 无独立文件夹的动作回退到聊天序列
        return this.resolveGoldenChatFrames();
      case 'idle':
      default:
        return this.resolveGoldenIdleFrames();
    }
  }

  private resolveLive2DMaoFrames(): ImageFrameInfo[] {
    return [
      this.createAnimatorFrame($r('app.media.live2d_mao_idle_01'), LIVE2D_MAO_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.live2d_mao_idle_02'), LIVE2D_MAO_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.live2d_mao_idle_03'), LIVE2D_MAO_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.live2d_mao_idle_04'), LIVE2D_MAO_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.live2d_mao_idle_05'), LIVE2D_MAO_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.live2d_mao_idle_06'), LIVE2D_MAO_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.live2d_mao_idle_07'), LIVE2D_MAO_FRAME_DURATION),
      this.createAnimatorFrame($r('app.media.live2d_mao_idle_08'), LIVE2D_MAO_FRAME_DURATION)
    ];
  }

  private resolvePetFrames(action: PetActionType): ImageFrameInfo[] {
    const prefix: string = this.resolveFramePrefix();
    if (prefix === 'golden') {
      return this.resolveGoldenFrames(action);
    }
    if (prefix === 'live2d_mao') {
      return this.resolveLive2DMaoFrames();
    }
    switch (action) {
      case 'eat':
        return [
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'eat', 1), GOLDEN_FRAME_DURATION),
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'eat', 2), GOLDEN_FRAME_DURATION),
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'eat', 3), GOLDEN_FRAME_DURATION)
        ];
      case 'chat':
        return [
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'chat', 1), GOLDEN_FRAME_DURATION),
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'chat', 2), GOLDEN_FRAME_DURATION),
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'chat', 3), GOLDEN_FRAME_DURATION)
        ];
      case 'sleep':
        return [
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'sleep', 1), GOLDEN_FRAME_DURATION),
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'sleep', 2), GOLDEN_FRAME_DURATION),
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'sleep', 3), GOLDEN_FRAME_DURATION)
        ];
      case 'idle':
      default:
        return [
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'idle', 1), GOLDEN_FRAME_DURATION),
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'idle', 2), GOLDEN_FRAME_DURATION),
          this.createAnimatorFrame(this.resolveFrameResource(prefix, 'idle', 3), GOLDEN_FRAME_DURATION)
        ];
    }
  }

  // 金毛：每个动作都直接使用当前动作的多帧序列，不再做动作折叠
  private resolveAnimationAction(): PetActionType {
    if (this.resolveFramePrefix() === 'golden') {
      return this.pet.currentAction;
    }
    return this.resolveFrameAction();
  }

  // 金毛：待机/过热/过湿持续循环；睡觉播放一遍后停留最后一张；其他交互动作循环两遍
  // 手动模式下，过热/过湿改为播放两遍后回待机
  private resolveIterations(): number {
    if (this.resolveFramePrefix() !== 'golden') {
      return -1;
    }
    const action: PetActionType = this.pet.currentAction;
    if (PetSensorService.isManualExtremeReaction() && (action === 'hot' || action === 'wet')) {
      return 2;
    }
    if (action === 'idle' || action === 'hot' || action === 'wet') {
      return -1;
    }
    if (action === 'sleep') {
      return 1;
    }
    // eat/interact 帧数较多，播一遍避免拖沓；其余动作两遍
    if (action === 'eat' || action === 'interact') {
      return 1;
    }
    return 2;
  }

  // 金毛：回待机时机由 scheduleActionReset 精确调度（图片遍数总时长 + 介绍时间），不依赖 onFinish 触发时机
  private handleAnimationFrameFinish(): void {
  }

  // 介绍显示时间：基于气泡文字长度估算，1.2~2.8 秒
  private resolveIntroDelay(): number {
    const speech: string = this.pet.currentSpeech.trim();
    const length: number = speech.length;
    return Math.max(1200, Math.min(2800, 600 + length * 120));
  }

  private resolveCatEyeResource(): Resource {
    switch (this.pet.currentAction) {
      case 'sleep':
        return $r('app.media.cat_eye_sleep');
      case 'interact':
      case 'bath':
        return $r('app.media.cat_eye_touch');
      case 'play':
      case 'train':
        return $r('app.media.cat_eye_happy');
      case 'eat':
      case 'chat':
        return $r('app.media.cat_eye_half');
      case 'idle':
      default:
        return $r('app.media.cat_eye_normal');
    }
  }

  private resolveCatMouthResource(): Resource {
    if (this.pet.currentAction === 'eat') {
      return $r('app.media.cat_mouth_eat');
    }
    return $r('app.media.cat_mouth_happy');
  }

  private resolveCatMouthOpacity(): number {
    switch (this.pet.currentAction) {
      case 'eat':
      case 'chat':
      case 'interact':
      case 'play':
      case 'train':
        return Math.max(0.66, this.accentOpacity + 0.48);
      case 'sleep':
        return 0;
      case 'bath':
      case 'idle':
      default:
        return 0.3;
    }
  }

  private resolveCatBlushOpacity(): number {
    switch (this.pet.currentAction) {
      case 'interact':
      case 'play':
        return Math.max(0.24, this.accentOpacity + 0.18);
      case 'eat':
        return 0.28;
      default:
        return 0;
    }
  }

  private resolveCatEffectOpacity(): number {
    switch (this.pet.currentAction) {
      case 'interact':
      case 'play':
      case 'chat':
        return Math.max(0.18, this.accentOpacity + 0.1);
      default:
        return 0;
    }
  }

  private resolveCatEarAngle(side: number): number {
    let baseAngle: number = side * 4;
    switch (this.pet.currentAction) {
      case 'sleep':
        baseAngle = side * 9;
        break;
      case 'eat':
        baseAngle = side * (6 + this.motionOffsetYExtra * 0.18);
        break;
      case 'interact':
      case 'play':
        baseAngle = side * (10 + this.motionOffsetYExtra * 0.35);
        break;
      case 'chat':
      case 'train':
        baseAngle = side * (7 + this.actionRotateYExtra * 0.42);
        break;
      default:
        baseAngle = side * (4 + this.tiltZExtra * 0.5);
        break;
    }
    return Math.max(-18, Math.min(18, baseAngle));
  }

  private resolveCatTailAngle(): number {
    let angle: number = 8 + this.actionRotateYExtra * 0.7;
    switch (this.pet.currentAction) {
      case 'sleep':
        angle = -10 + this.tiltZExtra * 0.4;
        break;
      case 'eat':
        angle = 14 + this.motionOffsetYExtra * 0.34;
        break;
      case 'interact':
      case 'play':
        angle = 24 + this.actionRotateYExtra * 1.4;
        break;
      case 'chat':
      case 'train':
        angle = 16 + this.actionRotateYExtra * 0.9;
        break;
      default:
        angle = 10 + this.tiltZExtra * 0.8;
        break;
    }
    return Math.max(-20, Math.min(34, angle));
  }

  private resolveCatPawOffsetY(): number {
    switch (this.pet.currentAction) {
      case 'eat':
        return 10 + this.motionOffsetYExtra * 0.25;
      case 'play':
      case 'interact':
        return -8 + this.motionOffsetYExtra * 0.35;
      case 'sleep':
        return 5;
      default:
        return this.motionOffsetYExtra * 0.12;
    }
  }

  private resolveCatFaceOffsetY(): number {
    switch (this.pet.currentAction) {
      case 'eat':
        return 8 + this.motionOffsetYExtra * 0.18;
      case 'sleep':
        return 3;
      case 'interact':
        return 0 + this.motionOffsetYExtra * 0.18;
      default:
        return 10 + this.motionOffsetYExtra * 0.08;
    }
  }

  @Builder
  private LayeredCatBody() {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.cat_tail'))
        .width(CAT_TAIL_LAYOUT.size)
        .height(CAT_TAIL_LAYOUT.size)
        .objectFit(ImageFit.Contain)
        .translate({
          x: CAT_TAIL_LAYOUT.offsetX + this.accentOffsetX * 0.06,
          y: CAT_TAIL_LAYOUT.offsetY + this.motionOffsetYExtra * 0.08
        })
        .rotate({ x: 0, y: 0, z: 1, angle: this.resolveCatTailAngle() })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });

      Image($r('app.media.cat_ear_right'))
        .width(CAT_LEFT_EAR_LAYOUT.size)
        .height(CAT_LEFT_EAR_LAYOUT.size)
        .objectFit(ImageFit.Contain)
        .translate({
          x: CAT_LEFT_EAR_LAYOUT.offsetX,
          y: CAT_LEFT_EAR_LAYOUT.offsetY + this.motionOffsetYExtra * 0.08
        })
        .rotate({ x: 0, y: 0, z: 1, angle: this.resolveCatEarAngle(-1) })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });

      Image($r('app.media.cat_ear_left'))
        .width(CAT_RIGHT_EAR_LAYOUT.size)
        .height(CAT_RIGHT_EAR_LAYOUT.size)
        .objectFit(ImageFit.Contain)
        .translate({
          x: CAT_RIGHT_EAR_LAYOUT.offsetX,
          y: CAT_RIGHT_EAR_LAYOUT.offsetY + this.motionOffsetYExtra * 0.08
        })
        .rotate({ x: 0, y: 0, z: 1, angle: this.resolveCatEarAngle(1) })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });

      Image($r('app.media.cat_leg_right'))
        .width(CAT_LEFT_LEG_LAYOUT.size)
        .height(CAT_LEFT_LEG_LAYOUT.size)
        .objectFit(ImageFit.Contain)
        .translate({
          x: CAT_LEFT_LEG_LAYOUT.offsetX,
          y: CAT_LEFT_LEG_LAYOUT.offsetY + this.resolveCatPawOffsetY()
        })
        .rotate({ x: 0, y: 0, z: 1, angle: -3 - this.tiltZExtra * 0.25 })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });

      Image($r('app.media.cat_leg_left'))
        .width(CAT_RIGHT_LEG_LAYOUT.size)
        .height(CAT_RIGHT_LEG_LAYOUT.size)
        .objectFit(ImageFit.Contain)
        .translate({
          x: CAT_RIGHT_LEG_LAYOUT.offsetX,
          y: CAT_RIGHT_LEG_LAYOUT.offsetY - this.resolveCatPawOffsetY() * 0.24
        })
        .rotate({ x: 0, y: 0, z: 1, angle: 3 + this.tiltZExtra * 0.25 })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });

      Image($r('app.media.cat_head'))
        .width(CAT_TORSO_LAYOUT.size)
        .height(CAT_TORSO_LAYOUT.size)
        .objectFit(ImageFit.Contain)
        .translate({
          x: CAT_TORSO_LAYOUT.offsetX,
          y: CAT_TORSO_LAYOUT.offsetY + this.motionOffsetYExtra * 0.12
        })
        .scale({
          x: 1 + this.bodyScaleXExtra * 0.7,
          y: 1 + this.bodyScaleYExtra * 0.7
        })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });

      Image($r('app.media.cat_body'))
        .width(CAT_HEAD_LAYOUT.size)
        .height(CAT_HEAD_LAYOUT.size)
        .objectFit(ImageFit.Contain)
        .translate({
          x: CAT_HEAD_LAYOUT.offsetX,
          y: CAT_HEAD_LAYOUT.offsetY + this.resolveCatFaceOffsetY()
        })
        .scale({ x: 1 + this.bodyScaleXExtra * 0.36, y: 1 + this.bodyScaleYExtra * 0.36 })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });

      Image(this.resolveCatEyeResource())
        .width(CAT_FACE_LAYOUT.size)
        .height(CAT_FACE_LAYOUT.size)
        .objectFit(ImageFit.Contain)
        .translate({
          x: CAT_FACE_LAYOUT.offsetX,
          y: CAT_FACE_LAYOUT.offsetY + this.resolveCatFaceOffsetY()
        })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });

      Image(this.resolveCatMouthResource())
        .width(CAT_FACE_LAYOUT.size)
        .height(CAT_FACE_LAYOUT.size)
        .objectFit(ImageFit.Contain)
        .opacity(this.resolveCatMouthOpacity())
        .translate({
          x: CAT_FACE_LAYOUT.offsetX,
          y: CAT_FACE_LAYOUT.offsetY + this.resolveCatFaceOffsetY() + 2
        })
        .scale({ x: this.accentScale, y: 1 + (this.accentScale - 1) * 0.48 })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });

      Row({ space: 72 }) {
        Ellipse()
          .width(32)
          .height(18)
          .fill('rgba(255, 154, 168, 0.46)');

        Ellipse()
          .width(32)
          .height(18)
          .fill('rgba(255, 154, 168, 0.46)');
      }
        .opacity(this.resolveCatBlushOpacity())
        .translate({ y: this.resolveCatFaceOffsetY() + 16 })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });

      Image($r('app.media.cat_effect_01'))
        .width(CAT_EFFECT_LAYOUT.size)
        .height(CAT_EFFECT_LAYOUT.size)
        .objectFit(ImageFit.Contain)
        .opacity(this.resolveCatEffectOpacity())
        .translate({
          x: CAT_EFFECT_LAYOUT.offsetX + this.accentOffsetX * 0.4,
          y: CAT_EFFECT_LAYOUT.offsetY + this.accentOffsetY * 0.16
        })
        .scale({ x: this.accentScale, y: this.accentScale })
        .animation({ duration: this.motionDuration, curve: Curve.EaseInOut, iterations: 1, playMode: PlayMode.Normal });
    }
    .width(this.resolveVisual().width)
    .height(this.resolveVisual().height)
    .clip(false);
  }

  @Builder
  private AnimatedPetBody() {
    if (this.shouldUseRealLive2D()) {
      Live2DPetView({
        modelName: this.resolveRealLive2DModelName(),
        action: this.pet.currentAction
      })
        .width(this.resolveVisual().width)
        .height(this.resolveVisual().height);
    } else if (this.shouldUseLayeredCat()) {
      this.LayeredCatBody();
    } else if (this.shouldUseFrameAnimator()) {
      ImageAnimator()
        .images(this.resolvePetFrames(this.resolveAnimationAction()))
        .state(AnimationStatus.Running)
        .iterations(this.resolveIterations())
        .onFinish(() => {
          this.handleAnimationFrameFinish();
        })
        .width(this.resolveVisual().width)
        .height(this.resolveVisual().height)
        .fixedSize(true);
    } else {
      Image(this.resolveVisual().image)
        .width(this.resolveVisual().width)
        .height(this.resolveVisual().height)
        .objectFit(ImageFit.Contain);
    }
  }

  @Builder
  private ActionAccent() {
    if (this.pet.currentAction === 'eat') {
      Row({ space: 4 }) {
        Circle({ width: 8, height: 8 })
          .fill('rgba(255, 255, 255, 0.90)');
        Circle({ width: 12, height: 12 })
          .fill('rgba(8, 148, 189, 0.90)');
      }
      .opacity(this.accentOpacity)
      .scale({ x: this.accentScale, y: this.accentScale })
      .translate({ x: this.accentOffsetX + 42, y: this.accentOffsetY + 36 });
    } else if (this.pet.currentAction === 'chat') {
      Row({ space: 4 }) {
        Circle({ width: 7, height: 7 }).fill('#FFFFFF');
        Circle({ width: 7, height: 7 }).fill('rgba(255, 255, 255, 0.88)');
        Circle({ width: 7, height: 7 }).fill('rgba(8, 148, 189, 0.92)');
      }
      .opacity(this.accentOpacity)
      .scale({ x: this.accentScale, y: this.accentScale })
      .translate({ x: this.accentOffsetX + 20, y: this.accentOffsetY - 52 });
    } else if (this.pet.currentAction === 'sleep') {
      Column({ space: 4 }) {
        Circle({ width: 8, height: 8 }).fill('rgba(255, 255, 255, 0.80)');
        Circle({ width: 10, height: 10 }).fill('rgba(255, 255, 255, 0.64)');
        Circle({ width: 12, height: 12 }).fill('rgba(8, 148, 189, 0.38)');
      }
      .opacity(this.accentOpacity)
      .scale({ x: this.accentScale, y: this.accentScale })
      .translate({ x: this.accentOffsetX + 24, y: this.accentOffsetY - 52 });
    } else if (this.pet.currentAction === 'play') {
      Row({ space: 6 }) {
        Circle({ width: 10, height: 10 }).fill('#FFFFFF');
        Circle({ width: 14, height: 14 }).fill('rgba(8, 148, 189, 0.94)');
      }
      .opacity(this.accentOpacity)
      .scale({ x: this.accentScale, y: this.accentScale })
      .translate({ x: this.accentOffsetX, y: this.accentOffsetY - 72 });
    }
  }

  private syncActionProfileIfNeeded(): string {
    if (this.lastResolvedAction !== this.pet.currentAction ||
      this.lastResolvedProfile !== this.pet.modelPath) {
      this.lastResolvedAction = this.pet.currentAction;
      this.lastResolvedProfile = this.pet.modelPath;
      this.applyMotionProfile(this.pet.currentAction);
      this.startActionLoop(this.pet.currentAction);
      this.triggerActionSideEffects(this.pet.currentAction);
    }

    return '';
  }

  private triggerActionSideEffects(action: PetActionType): void {
    if (this.abilityContext) {
      this.actionSoundService.playActionSound(action, this.abilityContext);
    }
    this.videoRelayService.swapByAction(action, this.resolveRelayProfile());
  }

  private resolveRelayProfile(): string {
    const modelPath: string = this.pet.modelPath.trim();
    const type: string = this.pet.type.trim();
    const name: string = this.pet.name.trim();
    if (modelPath.length > 0 && type.length > 0 && name.length > 0) {
      return `${modelPath}|${type}|${name}`;
    }
    if (modelPath.length > 0 && type.length > 0) {
      return `${modelPath}|${type}`;
    }
    if (modelPath.length > 0) {
      return modelPath;
    }
    if (type.length > 0 && name.length > 0) {
      return `${type}|${name}`;
    }
    return type.length > 0 ? type : name;
  }

  private syncSpeechPlaybackIfNeeded(): string {
    const speechText: string = this.pet.currentSpeech.trim();
    if (speechText.length === 0) {
      this.lastSpokenActionVersion = this.pet.actionVersion;
      this.lastSpokenSpeech = '';
      return '';
    }

    const actionChanged: boolean = this.lastSpokenActionVersion !== this.pet.actionVersion;
    const speechChanged: boolean = this.lastSpokenSpeech !== speechText;
    if (!actionChanged && !speechChanged) {
      return '';
    }

    this.lastSpokenActionVersion = this.pet.actionVersion;
    this.lastSpokenSpeech = speechText;

    // 金毛使用 MP3 动作音效，不再播放 TTS 语音合成（气泡文字仍正常显示）
    if (this.resolveFramePrefix() === 'golden') {
      return '';
    }

    this.ttsService.speak(this.pet, speechText);
    return '';
  }

  build() {
    Column() {
      Text(this.syncActionProfileIfNeeded())
        .fontSize(0)
        .opacity(0)
        .width(0)
        .height(0)

      Text(this.syncSpeechPlaybackIfNeeded())
        .fontSize(0)
        .opacity(0)
        .width(0)
        .height(0)

      if (this.pet.currentSpeech.length > 0) {
        Column() {
          Text(this.pet.currentSpeech)
            .fontSize(14)
            .fontColor('#081E2A')
            .padding({
              top: CommonConstants.SPACE_12,
              bottom: CommonConstants.SPACE_12,
              left: CommonConstants.SPACE_16,
              right: CommonConstants.SPACE_16
            });
        }
        .backgroundColor('rgba(255, 255, 255, 0.94)')
        .borderRadius(CommonConstants.BORDER_RADIUS_16)
        .shadow({ radius: 8, color: '#10000000', offsetX: 0, offsetY: 4 })
        .margin({ bottom: 18 })
        .translate({ y: (this.floatOffsetY + this.motionOffsetYExtra) * 0.35 })
        .animation({
          duration: this.motionDuration,
          curve: Curve.EaseInOut,
          iterations: 1,
          playMode: PlayMode.Normal
        });
      }

      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 232, height: 232 })
          .fill('rgba(8, 148, 189, 0.16)')
          .opacity(this.auraOpacity + this.auraOpacityExtra)
          .scale({ x: this.auraScale + this.auraScaleExtra, y: this.auraScale + this.auraScaleExtra })
          .translate({ y: -20 })
          .animation({
            duration: this.motionDuration,
            curve: Curve.EaseInOut,
            iterations: 1,
            playMode: PlayMode.Normal
          });

        Circle({ width: 18, height: 18 })
          .fill('rgba(255, 255, 255, 0.78)')
          .opacity(this.effectOpacity)
          .translate({ x: -84 + this.accentOffsetX * 0.14, y: this.effectOffsetY - 94 + this.accentOffsetY * 0.12 })
          .animation({
            duration: Math.max(180, this.motionDuration - 40),
            curve: Curve.EaseInOut,
            iterations: 1,
            playMode: PlayMode.Normal
          });

        Circle({ width: 10, height: 10 })
          .fill('rgba(8, 148, 189, 0.92)')
          .opacity(this.effectOpacity)
          .translate({ x: 92 + this.accentOffsetX * 0.1, y: this.effectOffsetY - 56 + this.accentOffsetY * 0.1 })
          .animation({
            duration: Math.max(180, this.motionDuration),
            curve: Curve.EaseInOut,
            iterations: 1,
            playMode: PlayMode.Normal
          });

        Circle({ width: 12, height: 12 })
          .fill('rgba(255, 255, 255, 0.56)')
          .opacity(this.effectOpacity * 0.9)
          .translate({ x: 18 + this.accentOffsetX * 0.12, y: this.effectOffsetY - 120 + this.accentOffsetY * 0.12 })
          .animation({
            duration: Math.max(180, this.motionDuration + 40),
            curve: Curve.EaseInOut,
            iterations: 1,
            playMode: PlayMode.Normal
          });

        this.ActionAccent();

        Ellipse()
          .width(this.resolveVisual().shadowWidth)
          .height(30)
          .fill('#000000')
          .opacity(this.resolveVisual().shadowOpacity)
          .margin({ top: this.resolveVisual().stageHeight - 44 })
          .scale({
            x: (this.shadowScaleX + this.shadowScaleXExtra) * this.interactionScale,
            y: (this.shadowScaleY + this.shadowScaleYExtra) * this.interactionScale
          })
          .animation({
            duration: this.motionDuration,
            curve: Curve.EaseInOut,
            iterations: 1,
            playMode: PlayMode.Normal
          });

        Column() {
          this.AnimatedPetBody();
        }
        .width(this.resolveVisual().width)
        .height(this.resolveVisual().height)
        .opacity(this.bodyOpacity)
        .scale({ x: this.resolveBodyScale(), y: this.resolveBodyScale() })
        .rotate({
          x: 0,
          y: 1,
          z: 0,
          angle: this.resolvePetRotateY()
        })
        .rotate({
          x: 0,
          y: 0,
          z: 1,
          angle: this.resolvePetTiltZ()
        })
        .translate({ y: this.floatOffsetY + this.motionOffsetYExtra })
        .animation({
          duration: this.motionDuration,
          curve: Curve.EaseInOut,
          iterations: 1,
          playMode: PlayMode.Normal
        })
        .onTouch((event: TouchEvent) => {
          this.handlePetImageTouch(event);
        });
      }
      .width('100%')
      .height(this.resolveVisual().stageHeight)
      .align(Alignment.Center)
      .renderGroup(true)
      .clip(false)
      .gesture(
        GestureGroup(
          GestureMode.Parallel,
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionUpdate((event: GestureEvent) => {
              let nextRotation: number = this.petRotationY + event.offsetX / 18;
              nextRotation = Math.max(-16, Math.min(16, nextRotation));
              this.petRotationY = nextRotation;
            })
            .onActionEnd(() => {
              this.petRotationY = 0;
            }),
          PinchGesture()
            .onActionUpdate((event: GestureEvent) => {
              let nextScale: number = event.scale;
              nextScale = Math.max(0.94, Math.min(1.12, nextScale));
              this.interactionScale = nextScale;
            })
            .onActionEnd(() => {
              this.interactionScale = 1;
            })
        )
      )
    }
    .width('100%')
    .flexGrow(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16 });
  }
}
