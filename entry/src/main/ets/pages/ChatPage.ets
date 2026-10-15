import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { PetModel } from '../common/models/PetModel';
import { ChatMessage } from '../common/models/ChatModels';
import { PetAiReply } from '../common/services/PetAiService';
import { PetVoiceService, VoiceSessionResult, VoiceStage } from '../common/services/PetVoiceService';
import { PetCuteVoiceService, PetVoiceSynthesisResult } from '../common/services/PetCuteVoiceService';
import { PetConversationService } from '../common/services/PetConversationService';
import { PetPersistenceService } from '../common/services/PetPersistenceService';
import { PetSpeechRecognizerService, SpeechSessionCallbacks } from '../common/services/PetSpeechRecognizerService';
import { PetChatGesturePolicy } from '../common/services/PetChatGesturePolicy';
import { PetContinuousChatService, ContinuousTurnCallbacks } from '../common/services/PetContinuousChatService';

const TYPEWRITER_INTERVAL_MS: number = 24;

@Entry
@Component
struct ChatPage {
  @StorageLink('currentPet') pet: PetModel = new PetModel('小橘', '宠物', $r('app.media.pet_duck_full'), 'duck_default');
  private readonly voiceService: PetVoiceService = PetVoiceService.getInstance();
  private readonly cuteVoiceService: PetCuteVoiceService = PetCuteVoiceService.getInstance();
  private readonly speechService: PetSpeechRecognizerService = PetSpeechRecognizerService.getInstance();
  @State backBtnScale: number = 1;
  @State sendBtnScale: number = 1;
  @State holdBtnScale: number = 1;
  @State inputText: string = '';
  @State messages: ChatMessage[] = [];
  @State stage: VoiceStage = '空闲';
  @State stageDetail: string = '可输入文字，也可按住说话';
  @State holdButtonText: string = '按住说话';
  @State isHolding: boolean = false;
  @State holdPartialText: string = '';
  @State swipeHintVisible: boolean = false;
  @State swipeActivated: boolean = false;
  @State swipeOffsetY: number = 0;
  @State isContinuousMode: boolean = false;
  private enterContinuousOnRelease: boolean = false;
  private simulatedHold: boolean = false;
  private holdSettled: boolean = false;
  private holdStartAt: number = 0;
  private holdFinalTimer: number = -1;
  @State isProcessing: boolean = false;
  @State isListening: boolean = false;
  @State listeningText: string = '';
  @State typingContent: string = '';

  aboutToAppear(): void {
    const petKey: string = PetPersistenceService.resolvePetKey(this.pet);
    const history: ChatMessage[] = PetConversationService.getHistory(petKey);
    if (history.length > 0) {
      this.messages = history.slice();
      return;
    }
    if (this.messages.length === 0) {
      this.messages = [{
        id: `${Date.now()}-welcome`,
        role: '宠物',
        content: this.pet.currentSpeech.length > 0 ? this.pet.currentSpeech : '主人，今天想聊些什么呢',
        source: ''
      }];
    }
  }

  private appendMessage(role: '主人' | '宠物', content: string, suffix: string, source: string): void {
    const message: ChatMessage = {
      id: `${Date.now()}-${suffix}`,
      role,
      content,
      source
    };
    this.messages = [...this.messages, message];
  }

  /**
   * 打字机上屏：AI 回复逐字追加（豆包式流式观感）；本地兜底直接上屏保证「快」
   */
  private async typewriterReply(reply: PetAiReply): Promise<void> {
    if (reply.source !== 'ai') {
      this.appendMessage('宠物', reply.content, 'pet', 'local');
      this.speakReply(reply.content);
      return;
    }

    const full: string = reply.content;
    this.typingContent = '';
    await new Promise<void>((resolve: () => void) => {
      let shown: number = 0;
      const timer: number = setInterval(() => {
        shown += 1;
        this.typingContent = full.slice(0, shown);
        if (shown >= full.length) {
          clearInterval(timer);
          resolve();
        }
      }, TYPEWRITER_INTERVAL_MS);
    });
    this.typingContent = '';
    this.appendMessage('宠物', full, 'pet', 'ai');
    this.speakReply(full);
  }

  /** 可爱配音播报 */
  private speakReply(replyText: string): void {
    const textVoiceResult: PetVoiceSynthesisResult = this.cuteVoiceService.synthesizeSpeech(this.pet, replyText);
    this.stage = '语音播报';
    this.stageDetail = `配音：${textVoiceResult.voiceRole}·${textVoiceResult.voiceText}`;
  }

  /** 打字中临时气泡（方法返回保证类型标注，规避 ArkTS 无类型字面量限制） */
  private typingBubble(): ChatMessage {
    const bubble: ChatMessage = {
      id: 'typing-bubble',
      role: '宠物',
      content: this.typingContent,
      source: 'ai'
    };
    return bubble;
  }

  private async sendMessage(): Promise<void> {
    const text: string = this.inputText.trim();
    if (text.length === 0 || this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.appendMessage('主人', text, 'user', '');
    this.inputText = '';

    try {
      const reply: PetAiReply = await PetConversationService.chatWithText(
        this.pet, text, getContext(this) as common.UIAbilityContext);
      await this.typewriterReply(reply);
    } finally {
      this.isProcessing = false;
    }
  }

  /** 「唤醒AI」头像点击：未监听则开启 once 识别；监听中再次点击安全取消 */
  private onAvatarClick(): void {
    if (this.isContinuousMode) {
      this.exitContinuousChat();
      return;
    }
    if (this.isListening) {
      this.speechService.stopListening();
      this.isListening = false;
      this.listeningText = '';
      this.stage = '空闲';
      this.stageDetail = '已取消语音监听';
      return;
    }
    void this.startVoiceWake();
  }

  private async startVoiceWake(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const granted: boolean = await PetSpeechRecognizerService.requestMicPermission(context);
    if (!granted) {
      promptAction.showToast({ message: '需要麦克风权限才能语音对话' });
      return;
    }

    const callbacks: SpeechSessionCallbacks = {
      onPartial: (text: string) => {
        this.listeningText = text;
      },
      onFinal: (text: string) => {
        this.isListening = false;
        this.listeningText = '';
        if (text.trim().length > 0) {
          void this.handleUserTranscript(text.trim());
        }
      },
      onError: (message: string) => {
        this.isListening = false;
        this.listeningText = '';
        promptAction.showToast({ message: message });
        this.stage = '空闲';
        this.stageDetail = '语音不可用时仍可文字输入';
      }
    };

    const petKey: string = PetPersistenceService.resolvePetKey(this.pet);
    const started: boolean = await this.speechService.startListening(petKey, 'once', callbacks);
    if (!started) {
      promptAction.showToast({ message: '当前设备不支持语音，请用文字输入' });
      return;
    }
    this.isListening = true;
    this.stage = '录音中';
    this.stageDetail = '正在聆听，说完自动发送';
  }

  /** 语音识别文本进入对话管线：上屏用户气泡 → AI 回复打字机 → 配音播报 */
  private async handleUserTranscript(text: string): Promise<void> {
    if (this.isProcessing) {
      return;
    }
    this.isProcessing = true;
    this.stage = '语音识别';
    this.stageDetail = '识别完成，正在生成回复';
    this.appendMessage('主人', text, 'user', '');
    try {
      const reply: PetAiReply = await PetConversationService.chatWithTranscript(
        this.pet, text, getContext(this) as common.UIAbilityContext);
      await this.typewriterReply(reply);
    } finally {
      this.isProcessing = false;
    }
  }

  private onHoldStart(): void {
    if (this.isContinuousMode) {
      return;
    }
    // 头像唤醒监听中直接按住：先安全取消 once 会话，避免录音会话双开
    if (this.isListening) {
      this.speechService.stopListening();
      this.isListening = false;
      this.listeningText = '';
    }
    if (this.isProcessing || this.isHolding) {
      return;
    }
    this.isHolding = true;
    this.holdButtonText = '松开结束';
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
          this.holdButtonText = '按住说话';
          promptAction.showToast({ message: '没听清，请再试一次' });
          return;
        }
        this.isProcessing = true;
        void this.handleUserTranscript(trimmed).then(() => {
          this.holdButtonText = '按住说话';
        });
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
        this.stage = stage;
        this.stageDetail = detail;
      });
      return;
    }
    // 录音已真正开启但用户已松开：立即停掉，防幽灵录音
    if (!this.isHolding || this.holdSettled) {
      this.speechService.stopListening();
    }
  }

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
      this.holdButtonText = '处理中';
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
    this.holdButtonText = '处理中';
    // final 等待兜底：1.5s 内未收到识别结果按没听清处理
    this.holdFinalTimer = setTimeout(() => {
      if (!this.holdSettled) {
        this.holdSettled = true;
        this.resetHoldState();
        promptAction.showToast({ message: '没听清，请再试一次' });
      }
    }, 1500);
  }

  private resetHoldState(): void {
    this.isHolding = false;
    this.holdButtonText = '按住说话';
    this.holdPartialText = '';
    this.stage = '空闲';
    this.stageDetail = '可输入文字，也可按住说话';
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

  private async processVoice(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const result: VoiceSessionResult = await this.voiceService.processRelease(this.pet, '', (stage: VoiceStage, detail: string): void => {
      this.stage = stage;
      this.stageDetail = detail;
    }, context);

    this.isProcessing = false;
    this.holdButtonText = '按住说话';

    if (!result.success) {
      this.appendMessage('宠物', result.detail, 'voice-fail', 'local');
      return;
    }

    this.appendMessage('主人', result.transcript, 'user', '');
    this.appendMessage('宠物', result.reply, 'pet', 'ai');
    this.stageDetail = `配音：${result.voiceRole}·${result.voiceOutput}`;
  }

  /** 上滑松开进入连续聊天：聆听 → 回复 → 自动重启聆听，直到点击退出 */
  private async enterContinuousChat(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const petKey: string = PetPersistenceService.resolvePetKey(this.pet);
    const callbacks: ContinuousTurnCallbacks = {
      onPartial: (text: string) => {
        this.listeningText = text;
      },
      onTurnStart: (transcript: string) => {
        this.listeningText = '';
        this.appendMessage('主人', transcript, 'user', '');
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
        this.holdButtonText = '点击退出连续聊天';
        this.stage = '录音中';
        this.stageDetail = '面对面聊天中，说完自动回复';
        promptAction.showToast({ message: '连续聊天已开启，说完自动回复' });
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

  /** 退出连续聊天（幂等）：停会话、清聆听态、按钮复原 */
  private exitContinuousChat(): void {
    PetContinuousChatService.getInstance().stopSession();
    if (!this.isContinuousMode) {
      return;
    }
    this.isContinuousMode = false;
    this.listeningText = '';
    this.holdButtonText = '按住说话';
    this.stage = '空闲';
    this.stageDetail = '可输入文字，也可按住说话';
    promptAction.showToast({ message: '已退出连续聊天' });
  }

  aboutToDisappear(): void {
    if (this.isContinuousMode) {
      PetContinuousChatService.getInstance().stopSession();
      this.isContinuousMode = false;
    }
    if (this.isListening) {
      this.speechService.stopListening();
      this.isListening = false;
      this.listeningText = '';
    }
    this.clearHoldFinalTimer();
  }

  @Builder
  private MessageBubble(message: ChatMessage) {
    Row() {
      if (message.role === '宠物') {
        Text(message.source === 'ai' ? 'AI' : '本地')
          .fontSize(11)
          .fontColor(message.source === 'ai' ? '#7CE7B0' : '#8FD9EF')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(message.source === 'ai' ? 'rgba(60, 180, 120, 0.2)' : 'rgba(8, 148, 189, 0.2)')
          .borderRadius(10)
          .margin({ right: 8 });
      }

      Text(message.content)
        .fontSize(14)
        .lineHeight(20)
        .fontColor('#FFFFFF')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(message.role === '宠物' ? '#31404D' : 'rgba(8, 148, 189, 0.36)')
        .borderRadius(14)
        .constraintSize({ minWidth: '36%', maxWidth: '80%' });

      if (message.role === '主人') {
        Text('我')
          .fontSize(11)
          .fontColor('#FFFFFF')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('rgba(255,255,255,0.2)')
          .borderRadius(10)
          .margin({ left: 8 });
      }
    }
    .width('100%')
    .justifyContent(message.role === '宠物' ? FlexAlign.Start : FlexAlign.End);
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor('#FFFFFF')
          .scale({ x: this.backBtnScale, y: this.backBtnScale })
          .animation({ duration: 150 })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.backBtnScale = 0.9;
            }
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.backBtnScale = 1;
            }
          })
          .onClick(() => {
            router.back();
          });

        Text(`和${this.pet.name}的聊天互动`)
          .layoutWeight(1)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .margin({ right: 24 });
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 10 });

      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.messages, (message: ChatMessage) => {
            this.MessageBubble(message);
          }, (message: ChatMessage) => message.id);

          if (this.typingContent.length > 0) {
            this.MessageBubble(this.typingBubble());
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 10, bottom: 16 });
      }
      .layoutWeight(1)
      .width('100%');

      Column({ space: 10 }) {
        if (this.listeningText.length > 0) {
          Text(`${this.isContinuousMode ? '正在聆听' : '正在识别'}：${this.listeningText}`)
            .width('100%')
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.6)');
        }

        if (this.isHolding && this.holdPartialText.length > 0) {
          Text(`正在聆听：${this.holdPartialText}`)
            .width('100%')
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.6)');
        }

        Row({ space: 8 }) {
          // 「唤醒AI」宠物头像按钮：监听中显示红色脉冲态，再次点击取消
          Image(this.pet.image)
            .width(44)
            .height(44)
            .borderRadius(22)
            .objectFit(ImageFit.Cover)
            .border({
              width: 2,
              color: this.isListening ? '#FF5A5A' : 'rgba(255,255,255,0.3)'
            })
            .scale({ x: this.isListening ? 1.12 : 1, y: this.isListening ? 1.12 : 1 })
            .animation({
              duration: 700,
              curve: Curve.EaseInOut,
              iterations: this.isListening ? -1 : 1,
              playMode: this.isListening ? PlayMode.Alternate : PlayMode.Normal
            })
            .onClick(() => {
              this.onAvatarClick();
            });

          TextInput({ placeholder: '输入消息', text: this.inputText })
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#31404D')
            .borderRadius(12)
            .fontColor('#FFFFFF')
            .placeholderColor('rgba(255,255,255,0.56)')
            .onChange((value: string) => {
              this.inputText = value;
            });

          Button('发送')
            .width(72)
            .height(44)
            .backgroundColor('#0894BD')
            .fontColor('#FFFFFF')
            .borderRadius(12)
            .scale({ x: this.sendBtnScale, y: this.sendBtnScale })
            .animation({ duration: 150 })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.sendBtnScale = 0.95;
              }
              if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.sendBtnScale = 1;
              }
            })
            .onClick(() => {
              void this.sendMessage();
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 });
        }
        .width('100%');

        Text(`语音状态：${this.stage}  ${this.stageDetail}`)
          .width('100%')
          .fontSize(12)
          .fontColor('#A0B3C6');

        if (this.swipeHintVisible) {
          Text(this.swipeActivated ? '松开开启连续聊天' : '上滑开启连续聊天')
            .width('100%')
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

        if (this.isContinuousMode) {
          Text('面对面聊天中 · 宠物回复后自动聆听')
            .width('100%')
            .textAlign(TextAlign.Center)
            .fontSize(12)
            .fontColor('#B79CFF');
        }

        Button(this.holdButtonText)
          .width('100%')
          .height(46)
          .backgroundColor(this.isContinuousMode ? '#7A4FD4' : (this.isHolding ? '#1B85F3' : '#0A8FB7'))
          .fontColor('#FFFFFF')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .borderRadius(12)
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
      .padding({ left: 16, right: 16, top: 10, bottom: 20 })
      .backgroundColor('#2A3641')
      .borderRadius({ topLeft: 16, topRight: 16 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#081E2A');
  }
}
