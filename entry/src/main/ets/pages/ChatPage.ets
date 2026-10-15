import { router } from '@kit.ArkUI';
import { PetModel } from '../common/models/PetModel';
import { PetAiService } from '../common/services/PetAiService';
import { InteractionService } from '../common/services/InteractionService';
import { PetVoiceService, VoiceSessionResult, VoiceStage } from '../common/services/PetVoiceService';
import { PetCuteVoiceService, PetVoiceSynthesisResult } from '../common/services/PetCuteVoiceService';

interface ChatMessage {
  id: string;
  role: '主人' | '宠物';
  content: string;
}

@Entry
@Component
struct ChatPage {
  @StorageLink('currentPet') pet: PetModel = new PetModel('小橘', '宠物', $r('app.media.pet_duck_full'), 'duck_default');
  private readonly voiceService: PetVoiceService = PetVoiceService.getInstance();
  private readonly cuteVoiceService: PetCuteVoiceService = PetCuteVoiceService.getInstance();
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

  aboutToAppear(): void {
    if (this.messages.length === 0) {
      this.messages = [{
        id: `${Date.now()}-welcome`,
        role: '宠物',
        content: this.pet.currentSpeech.length > 0 ? this.pet.currentSpeech : '主人，今天想聊些什么呢'
      }];
    }
  }

  private appendMessage(role: '主人' | '宠物', content: string, suffix: string): void {
    const message: ChatMessage = {
      id: `${Date.now()}-${suffix}`,
      role,
      content
    };
    this.messages = [...this.messages, message];
  }

  private appendDialogue(userContent: string, petContent: string): void {
    this.appendMessage('主人', userContent, 'user');
    this.appendMessage('宠物', petContent, 'pet');
  }

  private async sendMessage(): Promise<void> {
    const text: string = this.inputText.trim();
    if (text.length === 0) {
      return;
    }

    this.appendMessage('主人', text, 'user');

    const replyText: string = PetAiService.reply(this.pet, text);
    await InteractionService.getInstance().chat(this.pet, text);
    this.pet.currentSpeech = replyText;
    const textVoiceResult: PetVoiceSynthesisResult = this.cuteVoiceService.synthesizeSpeech(this.pet, replyText);
    this.appendMessage('宠物', replyText, 'pet');
    this.stage = '语音播报';
    this.stageDetail = `配音：${textVoiceResult.voiceRole}·${textVoiceResult.voiceText}`;
    this.inputText = '';
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
    const result: VoiceSessionResult = await this.voiceService.processRelease(this.pet, '', (stage: VoiceStage, detail: string): void => {
      this.stage = stage;
      this.stageDetail = detail;
    });

    this.isProcessing = false;
    this.holdButtonText = '按住说话';

    if (!result.success) {
      this.appendMessage('宠物', result.detail, 'voice-fail');
      return;
    }

    this.appendDialogue(result.transcript, result.reply);
    this.stageDetail = `配音：${result.voiceRole}·${result.voiceOutput}`;
  }

  @Builder
  private MessageBubble(message: ChatMessage) {
    Row() {
      if (message.role === '宠物') {
        Text('宠物')
          .fontSize(11)
          .fontColor('#8FD9EF')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('rgba(8, 148, 189, 0.2)')
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
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 10, bottom: 16 });
      }
      .layoutWeight(1)
      .width('100%');

      Column({ space: 10 }) {
        Row({ space: 8 }) {
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
