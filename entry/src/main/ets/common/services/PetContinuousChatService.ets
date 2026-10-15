import { common } from '@kit.AbilityKit';
import { PetModel } from '../models/PetModel';
import { PetAiReply } from './PetAiService';
import { PetConversationService } from './PetConversationService';
import { PetSpeechRecognizerService, SpeechSessionCallbacks } from './PetSpeechRecognizerService';
import { PetChatGesturePolicy } from './PetChatGesturePolicy';
import { LlmTransport } from './PetLlmClient';

/** 连续聊天轮次回调：页面据此上屏与打字机播报 */
export interface ContinuousTurnCallbacks {
  onPartial: (text: string) => void;
  onTurnStart: (transcript: string) => void;
  onTurnReply: (reply: PetAiReply) => Promise<void>;
  onError: (message: string) => void;
  onNotice: (message: string) => void;
  /** 会话首轮聆听真正启动成功后回调一次（设备不支持时不会触发，页面据此再亮「已开启」态） */
  onSessionStarted?: () => void;
}

/** 语音端口最小接口：生产接 PetSpeechRecognizerService，测试注入 fake */
export interface SpeechPort {
  startListening: (petKey: string, mode: 'once', cb: SpeechSessionCallbacks) => Promise<boolean>;
  stopListening: () => void;
}

/**
 * 连续聊天轮次编排：聆听 → onFinal → AI 回复 → 回复完成后自动重启聆听，
 * 直到 stopSession 或终止性错误。AI 回复期间不录音（onTurnReply resolve 后才重启），
 * 静默超时（「没有听到说话」）自动重启，其余错误终止。
 */
export class PetContinuousChatService {
  private static instance: PetContinuousChatService | undefined = undefined;
  private running: boolean = false;
  private generation: number = 0;
  private lastPort: SpeechPort | undefined = undefined;
  private sessionStartedNotified: boolean = false;

  private constructor() {
  }

  static getInstance(): PetContinuousChatService {
    if (!PetContinuousChatService.instance) {
      PetContinuousChatService.instance = new PetContinuousChatService();
    }
    return PetContinuousChatService.instance;
  }

  isRunning(): boolean {
    return this.running;
  }

  /** 开启连续会话；进行中重复调用返回 false 不双开 */
  async startSession(pet: PetModel, petKey: string, cb: ContinuousTurnCallbacks,
    context: common.Context, speech?: SpeechPort,
    transport?: LlmTransport): Promise<boolean> {
    const self: PetContinuousChatService = PetContinuousChatService.getInstance();
    if (self.running) {
      return false;
    }
    const port: SpeechPort = speech !== undefined ? speech : PetSpeechRecognizerService.getInstance();
    self.running = true;
    self.generation += 1;
    self.lastPort = port;
    self.sessionStartedNotified = false;
    self.loopTurn(pet, petKey, cb, context, port, transport);
    return true;
  }

  /** 停止会话（幂等）；进行中的回调检查 generation 后不再重启 */
  stopSession(): void {
    const self: PetContinuousChatService = PetContinuousChatService.getInstance();
    if (!self.running) {
      return;
    }
    self.running = false;
    self.generation += 1;
    const port: SpeechPort | undefined = self.lastPort;
    self.lastPort = undefined;
    if (port) {
      port.stopListening();
    }
  }

  private loopTurn(pet: PetModel, petKey: string, cb: ContinuousTurnCallbacks,
    context: common.Context, port: SpeechPort, transport?: LlmTransport): void {
    const self: PetContinuousChatService = PetContinuousChatService.getInstance();
    const generation: number = self.generation;
    const sessionCb: SpeechSessionCallbacks = {
      onPartial: (text: string) => {
        if (self.running && generation === self.generation) {
          cb.onPartial(text);
        }
      },
      onFinal: (text: string) => {
        void self.onTurnFinal(pet, petKey, cb, context, port, transport, generation, text);
      },
      onError: (message: string) => {
        if (!self.running || generation !== self.generation) {
          return;
        }
        const action: string = PetChatGesturePolicy.resolveAfterError(message, true);
        if (action === 'restart') {
          cb.onNotice(message);
          self.listenAgain(pet, petKey, cb, context, port, transport);
        } else {
          self.running = false;
          self.generation += 1;
          self.lastPort = undefined;
          cb.onError(message);
        }
      }
    };
    void port.startListening(petKey, 'once', sessionCb).then((started: boolean) => {
      if (!started) {
        // 启动失败（设备不支持/被占用）：终止会话并明确上报，避免无回调死挂
        if (!self.running || generation !== self.generation) {
          return;
        }
        self.running = false;
        self.generation += 1;
        self.lastPort = undefined;
        cb.onError('语音不可用，无法连续聊天');
        return;
      }
      if (generation === self.generation && !self.sessionStartedNotified) {
        self.sessionStartedNotified = true;
        if (cb.onSessionStarted) {
          cb.onSessionStarted();
        }
      }
    });
  }

  private async onTurnFinal(pet: PetModel, petKey: string, cb: ContinuousTurnCallbacks,
    context: common.Context, port: SpeechPort, transport: LlmTransport | undefined,
    generation: number, text: string): Promise<void> {
    const self: PetContinuousChatService = PetContinuousChatService.getInstance();
    if (!self.running || generation !== self.generation) {
      return;
    }
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      cb.onNotice('没听清，请再说说');
      self.listenAgain(pet, petKey, cb, context, port, transport);
      return;
    }
    cb.onTurnStart(trimmed);
    const reply: PetAiReply = await PetConversationService.chatWithTranscript(pet, trimmed, context, transport);
    if (!self.running || generation !== self.generation) {
      return;
    }
    await cb.onTurnReply(reply);
    if (!self.running || generation !== self.generation) {
      return;
    }
    self.listenAgain(pet, petKey, cb, context, port, transport);
  }

  private listenAgain(pet: PetModel, petKey: string, cb: ContinuousTurnCallbacks,
    context: common.Context, port: SpeechPort, transport: LlmTransport | undefined): void {
    const self: PetContinuousChatService = PetContinuousChatService.getInstance();
    if (!self.running) {
      return;
    }
    self.loopTurn(pet, petKey, cb, context, port, transport);
  }
}
