import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { PetModel, PetMemoryRecord } from '../../../main/ets/common/models/PetModel';
import { ChatMessage } from '../../../main/ets/common/models/ChatModels';
import { PetAiService } from '../../../main/ets/common/services/PetAiService';
import { AiChatMessage } from '../../../main/ets/common/services/PetLlmClient';
import { CommonConstants } from '../../../main/ets/common/constants/CommonConstants';

/** 构造一条聊天历史 */
function makeHistory(index: number, role: '主人' | '宠物'): ChatMessage {
  const item: ChatMessage = {
    id: `h-${index}`,
    role: role,
    content: role === '主人' ? `主人第${index}句` : `宠物第${index}句`,
    source: ''
  };
  return item;
}

/**
 * buildConversationMessages：记忆检索 + 多轮上下文构建测试
 */
export default function petAiContextTest(): void {
  describe('PetAiContext', () => {
    it('无历史时返回system与当前用户消息两条', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const pet: PetModel = new PetModel('团子', '猫咪');
      const result: AiChatMessage[] = PetAiService.buildConversationMessages(pet, '你好呀', []);
      expect(result.length).assertEqual(2);
      expect(result[0].role).assertEqual('system');
      expect(result[1].role).assertEqual('user');
      expect(result[1].content).assertEqual('你好呀');
    });
    it('system提示词包含宠物名与性格标签', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const pet: PetModel = new PetModel('团子', '猫咪');
      const result: AiChatMessage[] = PetAiService.buildConversationMessages(pet, '在吗', []);
      expect(result[0].content.includes('团子')).assertTrue();
      expect(result[0].content.includes(pet.resolvePersonalityLabel())).assertTrue();
    });
    it('system注入与查询相关的对话记忆', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const pet: PetModel = new PetModel('团子', '猫咪');
      const m1: PetMemoryRecord = new PetMemoryRecord();
      m1.type = '对话记忆';
      m1.content = '主人：我喜欢吃火锅';
      const m2: PetMemoryRecord = new PetMemoryRecord();
      m2.type = '对话记忆';
      m2.content = '主人：明天要考试';
      pet.memories.push(m1);
      pet.memories.push(m2);
      const result: AiChatMessage[] = PetAiService.buildConversationMessages(pet, '火锅好吃吗', []);
      expect(result[0].content.includes('火锅')).assertTrue();
    });
    it('超过上限时仅携带最近N条历史且角色映射正确', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const pet: PetModel = new PetModel('团子', '猫咪');
      const history: ChatMessage[] = [];
      for (let i: number = 1; i <= 14; i += 1) {
        history.push(makeHistory(i, i % 2 === 1 ? '主人' : '宠物'));
      }
      const result: AiChatMessage[] = PetAiService.buildConversationMessages(pet, '最新消息', history);
      // system + 最近10条 + 当前消息
      expect(result.length).assertEqual(2 + CommonConstants.CHAT_HISTORY_LIMIT);
      expect(result[1].content).assertEqual('主人第5句');
      const lastHistory: AiChatMessage = result[result.length - 2];
      expect(lastHistory.role).assertEqual('assistant');
      expect(lastHistory.content).assertEqual('宠物第14句');
    });
    it('无记忆时system不含记忆小节标题', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const pet: PetModel = new PetModel('团子', '猫咪');
      const result: AiChatMessage[] = PetAiService.buildConversationMessages(pet, '早', []);
      expect(result[0].content.includes('你记得的事')).assertFalse();
    });
  });
}
