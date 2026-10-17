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
  private enterContinuousOnRelease: boolean = false;
  private simulatedHold: boolean = false;
  private holdSettled: boolean = false;
  private holdStartAt: number = 0;
  private holdFinalTimer: number = -1;
  private readonly speechService: PetSpeechRecognizerService = PetSpeechRecognizerService.getInstance();
  private readonly voiceService: PetVoiceService = PetVoiceService.getInstance();
  private readonly cuteVoiceService: PetCuteVoiceService = PetCuteVoiceService.getInstance();

  private onHoldStart(): void {
  }

  private async beginHoldListening(): Promise<void> {
  }

  private onHoldEnd(): void {
  }

  private async handleUserTranscript(text: string): Promise<void> {
  }

  private async typewriterReply(reply: PetAiReply): Promise<void> {
  }

  private async speakReply(replyText: string): Promise<void> {
  }

  private async processVoice(): Promise<void> {
  }

  private async enterContinuousChat(): Promise<void> {
  }

  private exitContinuousChat(): void {
  }

  private resetHoldState(): void {
  }

  private clearHoldFinalTimer(): void {
  }

  private clearSwipeHint(): void {
  }

  aboutToDisappear(): void {
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
