import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { PetModel } from '../models/PetModel';
import { PetAiReply } from '../services/PetAiService';
import { PetVoiceService, VoiceSessionResult, VoiceStage } from '../services/PetVoiceService';
import { PetCuteVoiceService, PetVoiceSynthesisResult } from '../services/PetCuteVoiceService';
import { PetConversationService } from '../services/PetConversationService';
import { PetPersistenceService } from '../services/PetPersistenceService';
import { PetSpeechRecognizerService, SpeechSessionCallbacks } from '../services/PetSpeechRecognizerService';
import { PetChatGesturePolicy } from '../services/PetChatGesturePolicy';
import { PetContinuousChatService, ContinuousTurnCallbacks } from '../services/PetContinuousChatService';
import { PetKokoroTtsService } from '../services/PetKokoroTtsService';

const TYPEWRITER_INTERVAL_MS: number = 24;

/**
 * 首页语音聊天按钮：长按松开发送一次性语音对话；长按上滑 ≥120vp 松开进入面对面连续聊天。
 * 语音管线与 ChatPage 一致（复用同一批服务），展示改为首页气泡（首页无消息列表）。
 */
@Component
export struct HomeVoiceChatButton {
  @ObjectLink pet: PetModel;
  @State holdBtnScale: number = 1;
  @State isHolding: boolean = false;
  @State holdPartialText: string = '';
  @State swipeHintVisible: boolean = false;
  @State swipeActivated: boolean = false;
  @State swipeOffsetY: number = 0;
  @State isContinuousMode: boolean = false;
  @State isProcessing: boolean = false;
  @State bubbleUserText: string = '';
  @State bubbleReplyText: string = '';
  @State listeningText: string = '';
  private enterContinuousOnRelease: boolean = false;
  private simulatedHold: boolean = false;
  private holdSettled: boolean = false;
  private holdStartAt: number = 0;
  private holdFinalTimer: number = -1;
  private readonly speechService: PetSpeechRecognizerService = PetSpeechRecognizerService.getInstance();
  private readonly voiceService: PetVoiceService = PetVoiceService.getInstance();
  private readonly cuteVoiceService: PetCuteVoiceService = PetCuteVoiceService.getInstance();

  /** 长按开始：置按住态并启动 once 识别（连续模式下按钮为退出入口，不重复进入） */
  private onHoldStart(): void {
    if (this.isContinuousMode) {
      return;
    }
    if (this.isProcessing || this.isHolding) {
      return;
    }
    this.isHolding = true;
    this.holdSettled = false;
    this.simulatedHold = false;
    this.holdPartialText = '';
    this.holdStartAt = Date.now();
    this.enterContinuousOnRelease = false;
    this.clearSwipeHint();
    void this.beginHoldListening();
  }

  /** 按下即开启真实录音（once 识别）；识别不可用时降级为模拟兜底 */
  private async beginHoldListening(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const granted: boolean = await PetSpeechRecognizerService.requestMicPermission(context);
    if (!granted) {
      promptAction.showToast({ message: '需要麦克风权限才能语音对话' });
      this.resetHoldState();
      return;
    }
    // await 期间用户可能已松开：复查按压状态，防幽灵录音
    if (!this.isHolding || this.holdSettled) {
      return;
    }
    const petKey: string = PetPersistenceService.resolvePetKey(this.pet);
    const callbacks: SpeechSessionCallbacks = {
      onPartial: (text: string) => {
        this.holdPartialText = text;
      },
      onFinal: (text: string) => {
        if (this.holdSettled) {
          return;
        }
        this.holdSettled = true;
        this.clearHoldFinalTimer();
        this.isHolding = false;
        this.holdPartialText = '';
        const trimmed: string = text.trim();
        if (trimmed.length === 0) {
          promptAction.showToast({ message: '没听清，请再试一次' });
          return;
        }
        this.isProcessing = true;
        void this.handleUserTranscript(trimmed);
      },
      onError: (message: string) => {
        if (this.holdSettled) {
          return;
        }
        this.holdSettled = true;
        this.clearHoldFinalTimer();
        this.resetHoldState();
        promptAction.showToast({ message: message });
      }
    };
    const started: boolean = await this.speechService.startListening(petKey, 'once', callbacks);
    if (!started) {
      // 端侧识别不可用：降级为原模拟识别兜底（不崩溃）；已松开则不再进入模拟流程
      if (!this.isHolding || this.holdSettled) {
        return;
      }
      this.simulatedHold = true;
      this.voiceService.beginPress((stage: VoiceStage, detail: string): void => {
      });
      return;
    }
    // 录音已真正开启但用户已松开：立即停掉，防幽灵录音
    if (!this.isHolding || this.holdSettled) {
      this.speechService.stopListening();
    }
  }

  /** 松开：上滑则进连续聊天；模拟兜底走旧管线；否则等 onFinal（1.5s 兜底） */
  private onHoldEnd(): void {
    if (!this.isHolding || this.isProcessing) {
      return;
    }
    if (this.enterContinuousOnRelease) {
      // 上滑松开：丢弃本次按住的单句识别，进入连续聊天
      this.enterContinuousOnRelease = false;
      this.holdSettled = true;
      this.clearHoldFinalTimer();
      this.speechService.stopListening();
      this.clearSwipeHint();
      void this.enterContinuousChat();
      return;
    }
    if (this.simulatedHold) {
      this.isHolding = false;
      this.isProcessing = true;
      void this.processVoice();
      return;
    }
    // 松开即说话结束：finish 触发 onFinal 异步到达
    this.speechService.stopListening();
    const durationMs: number = Date.now() - this.holdStartAt;
    if (this.holdSettled) {
      return;
    }
    if (durationMs < 450) {
      this.holdSettled = true;
      this.resetHoldState();
      promptAction.showToast({ message: '没听清，请再试一次' });
      return;
    }
    // final 等待兜底：1.5s 内未收到识别结果按没听清处理
    this.holdFinalTimer = setTimeout(() => {
      if (!this.holdSettled) {
        this.holdSettled = true;
        this.resetHoldState();
        promptAction.showToast({ message: '没听清，请再试一次' });
      }
    }, 1500);
  }

  /** 语音识别文本进入对话管线：气泡展示 → AI 回复打字机 → 配音播报（历史自动落库，聊天页可见） */
  private async handleUserTranscript(text: string): Promise<void> {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.bubbleUserText = text;
    this.bubbleReplyText = '';
    try {
      const reply: PetAiReply = await PetConversationService.chatWithTranscript(
        this.pet, text, getContext(this) as common.UIAbilityContext);
      await this.typewriterReply(reply);
    } finally {
      this.isProcessing = false;
    }
  }

  /** 打字机上屏（首页为气泡）：AI 回复逐字追加；本地兜底直接上屏保证「快」 */
  private async typewriterReply(reply: PetAiReply): Promise<void> {
    // 新回复开始前中断上一段 Kokoro 播放，避免双声
    PetKokoroTtsService.getInstance().stop();
    if (reply.source !== 'ai') {
      this.bubbleReplyText = reply.content;
      await this.speakReply(reply.content);
      return;
    }

    const full: string = reply.content;
    this.bubbleReplyText = '';
    await new Promise<void>((resolve: () => void) => {
      let shown: number = 0;
      const timer: number = setInterval(() => {
        shown += 1;
        this.bubbleReplyText = full.slice(0, shown);
        if (shown >= full.length) {
          clearInterval(timer);
          resolve();
        }
      }, TYPEWRITER_INTERVAL_MS);
    });
    this.bubbleReplyText = full;
    await this.speakReply(full);
  }

  /** 可爱配音播报：狗宠物走 Kokoro 少年音（fire-and-forget，不阻塞连续聊天下一轮聆听），非狗仅文案 */
  private async speakReply(replyText: string): Promise<void> {
    const textVoiceResult: PetVoiceSynthesisResult = this.cuteVoiceService.synthesizeSpeech(this.pet, replyText);
    if (PetKokoroTtsService.getInstance().isDogVoiceEnabled(this.pet)) {
      PetKokoroTtsService.getInstance()
        .speak(this.pet, textVoiceResult.voiceText, getContext(this) as common.UIAbilityContext)
        .then((played: boolean): void => {
        });
    }
  }

  /** 识别不可用时的模拟兜底管线（端点检测→模拟识别→AI 回复） */
  private async processVoice(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const result: VoiceSessionResult = await this.voiceService.processRelease(this.pet, '',
      (stage: VoiceStage, detail: string): void => {
      }, context);

    this.isProcessing = false;

    if (!result.success) {
      this.bubbleReplyText = result.detail;
      return;
    }

    this.bubbleUserText = result.transcript;
    this.bubbleReplyText = result.reply;
  }

  /** 上滑松开进入面对面连续聊天：聆听 → 回复 → 自动重启聆听，直到点击退出 */
  private async enterContinuousChat(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const petKey: string = PetPersistenceService.resolvePetKey(this.pet);
    const callbacks: ContinuousTurnCallbacks = {
      onPartial: (text: string) => {
        this.listeningText = text;
      },
      onTurnStart: (transcript: string) => {
        this.listeningText = '';
        this.bubbleUserText = transcript;
        this.bubbleReplyText = '';
      },
      onTurnReply: (reply: PetAiReply): Promise<void> => {
        return this.typewriterReply(reply);
      },
      onNotice: (message: string) => {
        promptAction.showToast({ message: message });
      },
      onError: (message: string) => {
        promptAction.showToast({ message: message });
        this.exitContinuousChat();
      },
      onSessionStarted: () => {
        // 首轮聆听真正启动成功才亮「已开启」态；设备不支持时由 onError 流接管
        if (this.isContinuousMode) {
          return;
        }
        this.isContinuousMode = true;
        promptAction.showToast({ message: '面对面聊天已开启，说完自动回复' });
      }
    };
    const started: boolean = await PetContinuousChatService.getInstance()
      .startSession(this.pet, petKey, callbacks, context);
    if (!started) {
      // 双开竞态：恢复按住态
      this.resetHoldState();
      promptAction.showToast({ message: '当前已有语音会话进行中' });
    }
  }

  /** 退出连续聊天（幂等）：停会话、清聆听态与气泡 */
  private exitContinuousChat(): void {
    PetContinuousChatService.getInstance().stopSession();
    if (!this.isContinuousMode) {
      return;
    }
    this.isContinuousMode = false;
    this.listeningText = '';
    this.bubbleUserText = '';
    this.bubbleReplyText = '';
    promptAction.showToast({ message: '已退出语音聊天' });
  }

  private resetHoldState(): void {
    this.isHolding = false;
    this.holdPartialText = '';
  }

  private clearHoldFinalTimer(): void {
    if (this.holdFinalTimer !== -1) {
      clearTimeout(this.holdFinalTimer);
      this.holdFinalTimer = -1;
    }
  }

  private clearSwipeHint(): void {
    this.swipeHintVisible = false;
    this.swipeActivated = false;
    this.swipeOffsetY = 0;
  }

  aboutToDisappear(): void {
    if (this.isContinuousMode) {
      PetContinuousChatService.getInstance().stopSession();
      this.isContinuousMode = false;
    }
    this.clearHoldFinalTimer();
    this.speechService.stopListening();
    PetKokoroTtsService.getInstance().stop();
  }

  /** pushUrl 跳转聊天页等场景首页不销毁，必须主动停会话，避免后台录音与 ChatPage 双开 */
  onPageHide(): void {
    if (this.isContinuousMode) {
      this.exitContinuousChat();
    }
    this.clearHoldFinalTimer();
    this.speechService.stopListening();
    PetKokoroTtsService.getInstance().stop();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.swipeHintVisible || this.holdPartialText.length > 0 ||
        this.bubbleUserText.length > 0 || this.bubbleReplyText.length > 0) {
        Column({ space: 4 }) {
          if (this.swipeHintVisible) {
            Text(this.swipeActivated ? '松开开启面对面聊天' : '上滑开启面对面聊天')
              .textAlign(TextAlign.Center)
              .fontSize(13)
              .fontColor(this.swipeActivated ? '#FFFFFF' : 'rgba(255,255,255,0.7)')
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .borderRadius(14)
              .backgroundColor(this.swipeActivated ? 'rgba(122,79,212,0.9)' : 'rgba(20,30,40,0.92)')
              .border({
                width: this.swipeActivated ? 1.5 : 1,
                color: this.swipeActivated ? '#B79CFF' : 'rgba(255,255,255,0.25)'
              })
              .scale({ x: this.swipeActivated ? 1.05 : 1, y: this.swipeActivated ? 1.05 : 1 })
              .animation({ duration: 150 });
          }

          if (this.bubbleReplyText.length > 0 || this.bubbleUserText.length > 0) {
            Text(this.bubbleReplyText.length > 0 ? this.bubbleReplyText : this.bubbleUserText)
              .fontSize(14)
              .lineHeight(20)
              .fontColor('#FFFFFF')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor('rgba(12, 31, 44, 0.84)')
              .borderRadius(12)
              .constraintSize({ maxWidth: '80%' });
          }

          if (this.holdPartialText.length > 0) {
            Text(`正在聆听：${this.holdPartialText}`)
              .fontSize(12)
              .fontColor('rgba(255,255,255,0.6)');
          }

          if (this.isContinuousMode && this.listeningText.length > 0) {
            Text(`正在聆听：${this.listeningText}`)
              .fontSize(12)
              .fontColor('#B79CFF');
          }
        }
        .alignItems(HorizontalAlign.Center)
        .offset({ y: -64 })
        .zIndex(5);
      }

      Row({ space: 6 }) {
        Image($r('app.media.ic_menu_voice'))
          .width(18)
          .height(18)
          .fillColor('#FFFFFF');

        Text(this.isContinuousMode ? '点击退出语音聊天' : (this.isHolding ? '松开结束' : '按住说话'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF');
      }
      .justifyContent(FlexAlign.Center)
      .width(168)
      .height(46)
      .borderRadius(23)
      .backgroundColor(this.isContinuousMode ? '#7A4FD4' : (this.isHolding ? '#1B85F3' : 'rgba(8, 148, 189, 0.92)'))
      .enabled(!this.isProcessing)
      .scale({ x: this.holdBtnScale, y: this.holdBtnScale })
      .animation({ duration: 140 })
      .onTouch((event: TouchEvent) => {
        if (this.isContinuousMode) {
          return;
        }
        if (event.type === TouchType.Down) {
          this.holdBtnScale = 0.95;
          this.onHoldStart();
        }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.holdBtnScale = 1;
          if (event.type === TouchType.Up && this.isHolding && this.swipeActivated) {
            this.enterContinuousOnRelease = true;
            this.clearSwipeHint();
          } else if (event.type === TouchType.Cancel) {
            this.enterContinuousOnRelease = false;
            this.clearSwipeHint();
          }
          this.onHoldEnd();
        }
      })
      .onClick(() => {
        if (this.isContinuousMode) {
          this.exitContinuousChat();
        }
      })
      .gesture(PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 8 })
        .onActionStart((event: GestureEvent) => {
          if (this.isHolding) {
            this.swipeOffsetY = event.offsetY;
            this.swipeHintVisible = true;
          }
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.isHolding) {
            this.swipeOffsetY = event.offsetY;
            this.swipeHintVisible = true;
            this.swipeActivated = PetChatGesturePolicy.isSwipeUpEnter(this.swipeOffsetY);
          }
        })
        .onActionEnd(() => {
          this.swipeHintVisible = false;
        }))
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 });
    }
    .width('100%')
    .height(56);
  }
}
