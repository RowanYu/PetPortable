import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { PetModel } from '../../../main/ets/common/models/PetModel';
import { PetConversationService } from '../../../main/ets/common/services/PetConversationService';
import { AiChatMessage, LlmReply, LlmTransport } from '../../../main/ets/common/services/PetLlmClient';
import { PetAiReply } from '../../../main/ets/common/services/PetAiService';

/** 记录收到的 messages 供多轮断言的 Mock 传输层 */
class RecordingTransport implements LlmTransport {
  reply: LlmReply;
  lastMessages: AiChatMessage[] = [];

  constructor(reply: LlmReply) {
    this.reply = reply;
  }

  async chat(messages: AiChatMessage[]): Promise<LlmReply> {
    this.lastMessages = messages;
    return this.reply;
  }
}

/**
 * PetConversationService 门面测试
 */
export default function petConversationTest(): void {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  const petKey = 'conversation_test_pet';

  describe('PetConversation', () => {
    it('连续两轮对话后历史长度为4且宠物侧来源为ai', TestType.FUNCTION | Size.MEDIUM_TEST | Level.LEVEL1, async () => {
      const pet: PetModel = new PetModel('团子', '猫咪', undefined, petKey);
      const mock: RecordingTransport = new RecordingTransport({ ok: true, content: 'AI第一轮回复', errorMessage: '' });

      await PetConversationService.chatWithText(pet, '第一句话', context, mock);
      mock.reply = { ok: true, content: 'AI第二轮回复', errorMessage: '' };
      await PetConversationService.chatWithText(pet, '第二句话', context, mock);

      const history = PetConversationService.getHistory(petKey);
      expect(history.length).assertEqual(4);
      expect(history[1].source).assertEqual('ai');
      expect(history[3].source).assertEqual('ai');
      expect(history[2].content).assertEqual('第二句话');
    });
    it('第二轮请求携带第一轮对话内容', TestType.FUNCTION | Size.MEDIUM_TEST | Level.LEVEL1, async () => {
      const pet: PetModel = new PetModel('团子', '猫咪', undefined, petKey);
      const mock: RecordingTransport = new RecordingTransport({ ok: true, content: '好呀', errorMessage: '' });

      await PetConversationService.chatWithText(pet, '记得我说过火锅', context, mock);
      await PetConversationService.chatWithText(pet, '我刚才说什么了', context, mock);

      let foundFirstRound: boolean = false;
      for (let i: number = 0; i < mock.lastMessages.length; i += 1) {
        if (mock.lastMessages[i].content.includes('记得我说过火锅')) {
          foundFirstRound = true;
        }
      }
      expect(foundFirstRound).assertTrue();
    });
    it('chatWithTranscript与chatWithText产物结构一致', TestType.FUNCTION | Size.MEDIUM_TEST | Level.LEVEL1, async () => {
      const pet: PetModel = new PetModel('团子', '猫咪', undefined, petKey);
      const before: number = PetConversationService.getHistory(petKey).length;
      const mock: RecordingTransport = new RecordingTransport({ ok: true, content: '语音回复', errorMessage: '' });

      const reply: PetAiReply = await PetConversationService.chatWithTranscript(pet, '语音说的一句话', context, mock);
      expect(reply.source).assertEqual('ai');
      expect(reply.content).assertEqual('语音回复');

      const history = PetConversationService.getHistory(petKey);
      expect(history.length).assertEqual(before + 2);
      expect(history[history.length - 2].content).assertEqual('语音说的一句话');
    });
    it('历史超过50条时裁掉最旧一条', TestType.FUNCTION | Size.MEDIUM_TEST | Level.LEVEL1, async () => {
      const pet: PetModel = new PetModel('团子', '猫咪', undefined, petKey);
      const mock: RecordingTransport = new RecordingTransport({ ok: true, content: '嗯', errorMessage: '' });

      const key = 'trim_test_pet';
      // 造 51 条：25 轮 + 1 条用户消息
      for (let i: number = 0; i < 25; i += 1) {
        await PetConversationService.chatWithText(pet, `第${i}轮`, context, mock);
      }
      await PetConversationService.chatWithText(pet, '最新一条', context, mock);

      const history = PetConversationService.getHistory(key);
      expect(history.length).assertEqual(50);
      expect(history[0].content).assertEqual('第1轮');
    });
  });
}
