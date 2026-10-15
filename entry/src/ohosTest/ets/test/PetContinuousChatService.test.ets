import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { PetModel } from '../../../main/ets/common/models/PetModel';
import { PetContinuousChatService, ContinuousTurnCallbacks, SpeechPort } from '../../../main/ets/common/services/PetContinuousChatService';
import { SpeechSessionCallbacks } from '../../../main/ets/common/services/PetSpeechRecognizerService';
import { PetAiReply } from '../../../main/ets/common/services/PetAiService';
import { AiChatMessage, LlmReply, LlmTransport } from '../../../main/ets/common/services/PetLlmClient';

/** 记录 start/stop 调用次数的假语音端口（引擎由测试手动驱动） */
class FakeSpeechPort implements SpeechPort {
  startCount: number = 0;
  stopCount: number = 0;
  currentCb: SpeechSessionCallbacks | undefined = undefined;

  async startListening(petKey: string, mode: 'once', cb: SpeechSessionCallbacks): Promise<boolean> {
    this.startCount += 1;
    this.currentCb = cb;
    return true;
  }

  stopListening(): void {
    this.stopCount += 1;
  }
}

/** 固定返回 AI 回复的传输层（不触网） */
class StubTransport implements LlmTransport {
  async chat(messages: AiChatMessage[]): Promise<LlmReply> {
    return { ok: true, content: 'AI回复', errorMessage: '' };
  }
}

/** 记录轮次回调并可门住 onTurnReply 的假回调集 */
class TurnRecorder implements ContinuousTurnCallbacks {
  turns: string[] = [];
  replies: string[] = [];
  notices: string[] = [];
  errors: string[] = [];
  private replyGate: Promise<void> | undefined = undefined;
  private replyGateResolve: (() => void) | undefined = undefined;

  holdReply(): void {
    this.replyGate = new Promise<void>((resolve: () => void) => {
      this.replyGateResolve = resolve;
    });
  }

  releaseReply(): void {
    if (this.replyGateResolve) {
      this.replyGateResolve();
      this.replyGateResolve = undefined;
    }
  }

  onPartial(text: string): void {
  }

  onTurnStart(transcript: string): void {
    this.turns.push(transcript);
  }

  async onTurnReply(reply: PetAiReply): Promise<void> {
    this.replies.push(reply.content);
    if (this.replyGate) {
      await this.replyGate;
    }
  }

  onNotice(message: string): void {
    this.notices.push(message);
  }

  onError(message: string): void {
    this.errors.push(message);
  }
}

function shortDelay(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      resolve();
    }, 30);
  });
}

/**
 * PetContinuousChatService 轮次编排测试（fake 端口注入，不依赖真机语音引擎）
 */
export default function petContinuousChatServiceTest(): void {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const petKey = 'continuous_test_pet';
  const service = PetContinuousChatService.getInstance();

  describe('PetContinuousChatService', () => {
    it('一轮对话后依次回调onTurnStart与onTurnReply并重启聆听', TestType.FUNCTION | Size.MEDIUM_TEST | Level.LEVEL1, async () => {
      service.stopSession();
      const port: FakeSpeechPort = new FakeSpeechPort();
      const rec: TurnRecorder = new TurnRecorder();
      const pet: PetModel = new PetModel('团子', '猫咪', undefined, petKey);
      const started: boolean = await service.startSession(pet, petKey, rec, context, port, new StubTransport());
      expect(started).assertTrue();
      expect(port.startCount).assertEqual(1);

      const cb = port.currentCb;
      if (cb) {
        cb.onFinal('你好');
      }
      await shortDelay();

      expect(rec.turns.length).assertEqual(1);
      expect(rec.turns[0]).assertEqual('你好');
      expect(rec.replies.length).assertEqual(1);
      expect(rec.replies[0]).assertEqual('AI回复');
      expect(port.startCount).assertEqual(2);
      expect(service.isRunning()).assertTrue();
    });
    it('onTurnReply未resolve前不重启聆听', TestType.FUNCTION | Size.MEDIUM_TEST | Level.LEVEL1, async () => {
      service.stopSession();
      const port: FakeSpeechPort = new FakeSpeechPort();
      const rec: TurnRecorder = new TurnRecorder();
      rec.holdReply();
      const pet: PetModel = new PetModel('团子', '猫咪', undefined, petKey);
      await service.startSession(pet, petKey, rec, context, port, new StubTransport());

      const cb = port.currentCb;
      if (cb) {
        cb.onFinal('第二句');
      }
      await shortDelay();
      expect(port.startCount).assertEqual(1);

      rec.releaseReply();
      await shortDelay();
      expect(port.startCount).assertEqual(2);
    });
    it('stopSession后不再发起新一轮聆听', TestType.FUNCTION | Size.MEDIUM_TEST | Level.LEVEL1, async () => {
      service.stopSession();
      const port: FakeSpeechPort = new FakeSpeechPort();
      const rec: TurnRecorder = new TurnRecorder();
      const pet: PetModel = new PetModel('团子', '猫咪', undefined, petKey);
      await service.startSession(pet, petKey, rec, context, port, new StubTransport());
      expect(port.startCount).assertEqual(1);

      service.stopSession();
      expect(service.isRunning()).assertFalse();
      expect(port.stopCount).assertEqual(1);

      const cb = port.currentCb;
      if (cb) {
        cb.onFinal('第三句');
      }
      await shortDelay();
      expect(rec.turns.length).assertEqual(0);
      expect(port.startCount).assertEqual(1);
    });
    it('静默超时错误后自动重启聆听', TestType.FUNCTION | Size.MEDIUM_TEST | Level.LEVEL1, async () => {
      service.stopSession();
      const port: FakeSpeechPort = new FakeSpeechPort();
      const rec: TurnRecorder = new TurnRecorder();
      const pet: PetModel = new PetModel('团子', '猫咪', undefined, petKey);
      await service.startSession(pet, petKey, rec, context, port, new StubTransport());

      const cb = port.currentCb;
      if (cb) {
        cb.onError('没有听到说话，请再试一次');
      }
      await shortDelay();

      expect(rec.notices.length).assertEqual(1);
      expect(rec.errors.length).assertEqual(0);
      expect(port.startCount).assertEqual(2);
      expect(service.isRunning()).assertTrue();
    });
  });
}
