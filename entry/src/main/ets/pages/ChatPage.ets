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
    if (this.isProcessing) {
      return;
    }
    this.isHolding = true;
    this.holdButtonText = '松开结束';
    this.voiceService.beginPress((stage: VoiceStage, detail: string): void => {
      this.stage = stage;
      this.stageDetail = detail;
    });
  }

  private onHoldEnd(): void {
    if (!this.isHolding || this.isProcessing) {
      return;
    }
    this.isHolding = false;
    this.holdButtonText = '处理中';
    this.isProcessing = true;
    void this.processVoice();
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
          Text(`正在识别：${this.listeningText}`)
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

        Button(this.holdButtonText)
          .width('100%')
          .height(46)
          .backgroundColor(this.isHolding ? '#1B85F3' : '#0A8FB7')
          .fontColor('#FFFFFF')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .borderRadius(12)
          .enabled(!this.isProcessing)
          .scale({ x: this.holdBtnScale, y: this.holdBtnScale })
          .animation({ duration: 140 })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.holdBtnScale = 0.95;
              this.onHoldStart();
            }
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.holdBtnScale = 1;
              this.onHoldEnd();
            }
          })
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
