import { PetModel } from '../models/PetModel';
import { PetAiService } from './PetAiService';
import { InteractionService } from './InteractionService';
import { PetCuteVoiceService, PetVoiceRole, PetVoiceSynthesisResult } from './PetCuteVoiceService';
import { PetConversationService } from './PetConversationService';
import { PetPersistenceService } from './PetPersistenceService';
import { PetSpeechRecognizerService, SpeechSessionCallbacks } from './PetSpeechRecognizerService';
import { common } from '@kit.AbilityKit';

export type VoiceStage = '空闲' | '录音中' | '端点检测' | '语音识别' | '生成回复' | '语音播报' | '完成' | '失败';

export class VoiceSessionResult {
  success: boolean = false;
  stage: VoiceStage = '空闲';
  detail: string = '';
  transcript: string = '';
  reply: string = '';
  voiceRole: PetVoiceRole = '伙伴';
  voiceOutput: string = '';
  durationMs: number = 0;
}

export type VoiceStageCallback = (stage: VoiceStage, detail: string) => void;

export class PetVoiceService {
  private static instance: PetVoiceService | undefined = undefined;
  private pressStartedAt: number = 0;
  private lastPartial: string = '';
  private readonly cuteVoiceService: PetCuteVoiceService = PetCuteVoiceService.getInstance();

  private constructor() {
  }

  static getInstance(): PetVoiceService {
    if (!PetVoiceService.instance) {
      PetVoiceService.instance = new PetVoiceService();
    }
    return PetVoiceService.instance;
  }

  beginPress(onStage?: VoiceStageCallback): void {
    this.pressStartedAt = Date.now();
    this.emit(onStage, '录音中', '正在收集语音，请继续按住说话');
  }

  async processRelease(pet: PetModel, draftText: string, onStage?: VoiceStageCallback,
    context?: common.Context): Promise<VoiceSessionResult> {
    const result: VoiceSessionResult = new VoiceSessionResult();
    const durationMs: number = Math.max(0, Date.now() - this.pressStartedAt);
    result.durationMs = durationMs;

    this.emit(onStage, '端点检测', '正在检测说话结束');
    await this.wait(280);

    const vadPassed: boolean = this.detectVoiceEndpoint(durationMs, draftText);
    if (!vadPassed) {
      result.success = false;
      result.stage = '失败';
      result.detail = '没有检测到有效语音，请再试一次';
      this.emit(onStage, result.stage, result.detail);
      return result;
    }

    this.emit(onStage, '语音识别', '正在识别语音内容');
    let transcript: string = '';
    const recognizer: PetSpeechRecognizerService = PetSpeechRecognizerService.getInstance();
    if (recognizer.isAvailable()) {
      transcript = await this.recognizeWithEngine(recognizer);
    }
    if (transcript.length === 0) {
      // 端侧识别不可用/失败时，保留原模拟识别兜底（不崩溃）
      transcript = this.recognizeSpeech(pet, draftText, durationMs);
    }
    if (transcript.length === 0) {
      result.success = false;
      result.stage = '失败';
      result.detail = '语音识别失败，请重新说一次';
      this.emit(onStage, result.stage, result.detail);
      return result;
    }

    result.transcript = transcript;

    this.emit(onStage, '生成回复', '正在生成宠物回复');
    await this.wait(300);
    let replyText: string;
    if (context) {
      const aiReply = await PetConversationService.chatWithTranscript(pet, transcript, context);
      replyText = aiReply.content;
    } else {
      replyText = PetAiService.reply(pet, transcript);
      await InteractionService.getInstance().chat(pet, transcript);
    }
    result.reply = replyText;

    const voiceResult: PetVoiceSynthesisResult = this.cuteVoiceService.synthesizeSpeech(pet, replyText);
    result.voiceRole = voiceResult.voiceRole;
    result.voiceOutput = voiceResult.displayText;

    this.emit(onStage, '语音播报', `正在使用${voiceResult.voiceRole}可爱配音播报`);
    await this.wait(Math.max(this.resolveSpeakDuration(replyText), voiceResult.speakDurationMs));

    result.success = true;
    result.stage = '完成';
    result.detail = '语音互动完成';
    this.emit(onStage, result.stage, result.detail);
    return result;
  }

  /** 端侧识别 once 模式：录音到 VAD 结束，返回最终文本；失败返回空串 */
  private recognizeWithEngine(recognizer: PetSpeechRecognizerService): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void) => {
      let settled: boolean = false;
      const finish = (text: string): void => {
        if (!settled) {
          settled = true;
          resolve(text);
        }
      };
      const callbacks: SpeechSessionCallbacks = {
        onPartial: (text: string) => {
          // 中间结果暂存，最终以 onFinal 为准
          if (text.trim().length > 0) {
            this.lastPartial = text;
          }
        },
        onFinal: (text: string) => {
          finish(text);
        },
        onError: () => {
          finish('');
        }
      };
      recognizer.startListening('voice_press', 'once', callbacks).then((started: boolean) => {
        if (!started) {
          finish('');
        }
      }).catch(() => {
        finish('');
      });
      // 15s 兜底
      setTimeout(() => {
        if (!settled) {
          recognizer.stopListening();
          finish(this.lastPartial);
          this.lastPartial = '';
        }
      }, 15000);
    });
  }

  private emit(onStage: VoiceStageCallback | undefined, stage: VoiceStage, detail: string): void {
    if (onStage) {
      onStage(stage, detail);
    }
  }

  private detectVoiceEndpoint(durationMs: number, draftText: string): boolean {
    if (draftText.trim().length > 0) {
      return true;
    }
    return durationMs >= 450;
  }

  private recognizeSpeech(pet: PetModel, draftText: string, durationMs: number): string {
    const customText: string = draftText.trim();
    if (customText.length > 0) {
      return customText.length > 42 ? `${customText.slice(0, 42)}…` : customText;
    }

    if (pet.emotion === '悲伤') {
      return '你今天是不是有点不开心，我想陪着你';
    }
    if (pet.emotion === '困倦') {
      return '今天有点累了，我们早点休息好不好';
    }
    if (durationMs >= 1800) {
      return '我想和你多聊一会儿今天发生的事';
    }
    if (durationMs >= 900) {
      return '今天过得怎么样呀';
    }
    return '我在呢';
  }

  private resolveSpeakDuration(replyText: string): number {
    const contentLength: number = replyText.trim().length;
    const estimated: number = 420 + contentLength * 24;
    return Math.min(2400, Math.max(680, estimated));
  }

  private wait(ms: number): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
