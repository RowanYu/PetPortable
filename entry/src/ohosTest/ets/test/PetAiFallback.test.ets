import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { PetModel } from '../../../main/ets/common/models/PetModel';
import { PetAiService, PetAiReply } from '../../../main/ets/common/services/PetAiService';
import { AiChatMessage, LlmReply, LlmTransport } from '../../../main/ets/common/services/PetLlmClient';

/** 固定返回预设结果的 Mock 传输层 */
class MockTransport implements LlmTransport {
  reply: LlmReply;
  shouldThrow: boolean = false;

  constructor(reply: LlmReply) {
    this.reply = reply;
  }

  async chat(messages: AiChatMessage[]): Promise<LlmReply> {
    if (this.shouldThrow) {
      throw new Error('mock 传输层异常');
    }
    return this.reply;
  }
}

/** 查找记忆中指定前缀的内容 */
function findMemory(pet: PetModel, prefix: string): string {
  for (let i: number = 0; i < pet.memories.length; i += 1) {
    const content: string = pet.memories[i].content;
    if (content.startsWith(prefix)) {
      return content;
    }
  }
  return '';
}

/**
 * replyWithAI：AI 调度与本地回退测试
 */
export default function petAiFallbackTest(): void {
  describe('PetAiFallback', () => {
    it('AI成功时返回ai来源并写入双方记忆', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, async () => {
      const pet: PetModel = new PetModel('团子', '猫咪');
      const mock: MockTransport = new MockTransport({ ok: true, content: 'AI回复内容', errorMessage: '' });
      const result: PetAiReply = await PetAiService.replyWithAI(pet, '你好呀', [], mock);
      expect(result.source).assertEqual('ai');
      expect(result.content).assertEqual('AI回复内容');
      expect(findMemory(pet, '主人：').length > 0).assertTrue();
      expect(findMemory(pet, 'AI宠物：').length > 0).assertTrue();

    });
    it('AI失败时回退本地引擎', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, async () => {
      const pet: PetModel = new PetModel('团子', '猫咪');
      const mock: MockTransport = new MockTransport({ ok: false, content: '', errorMessage: '超时' });
      const result: PetAiReply = await PetAiService.replyWithAI(pet, '今天天气怎么样', [], mock);
      expect(result.source).assertEqual('local');
      expect(result.content.length > 0).assertTrue();
    });
    it('传输层抛异常时不上抛并回退本地', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, async () => {
      const pet: PetModel = new PetModel('团子', '猫咪');
      const mock: MockTransport = new MockTransport({ ok: true, content: 'x', errorMessage: '' });
      mock.shouldThrow = true;
      const result: PetAiReply = await PetAiService.replyWithAI(pet, '在吗', [], mock);
      expect(result.source).assertEqual('local');
      expect(result.content.length > 0).assertTrue();
    });
    it('AI超长回复截断至120字以内', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, async () => {
      const pet: PetModel = new PetModel('团子', '猫咪');
      let longText: string = '';
      for (let i: number = 0; i < 30; i += 1) {
        longText += '这是一段超长的宠物回复内容用来测试截断';
      }
      const mock: MockTransport = new MockTransport({ ok: true, content: longText, errorMessage: '' });
      const result: PetAiReply = await PetAiService.replyWithAI(pet, '多聊几句', [], mock);
      expect(result.content.length <= 120).assertTrue();
      expect(result.content.endsWith('…')).assertTrue();
    });
    it('同步reply旧行为不变', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const pet: PetModel = new PetModel('团子', '猫咪');
      const replyText: string = PetAiService.reply(pet, '你好');
      expect(replyText.length > 0).assertTrue();
      expect(findMemory(pet, '宠物：').length > 0).assertTrue();
    });
  });
}
