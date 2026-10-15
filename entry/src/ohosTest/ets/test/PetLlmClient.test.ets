import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { buildChatRequestBody, parseChatResponse, HttpLlmTransport, AiChatMessage, LlmReply } from '../../../main/ets/common/services/PetLlmClient';
import { CommonConstants } from '../../../main/ets/common/constants/CommonConstants';

/**
 * PetLlmClient 纯函数与传输层测试（Anthropic Messages 协议）
 */
export default function petLlmClientTest(): void {
  describe('PetLlmClient', () => {
    it('请求体包含model与messages', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const messages: AiChatMessage[] = [{ role: 'user', content: '你好' }];
      const body: string = buildChatRequestBody('step-3.5-flash-2603', messages);
      expect(body.includes('"step-3.5-flash-2603"')).assertTrue();
      expect(body.includes('你好')).assertTrue();
      expect(body.includes('max_tokens')).assertTrue();
    });
    it('system消息拆分到顶层system字段', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const messages: AiChatMessage[] = [
        { role: 'system', content: '你是宠物团子' },
        { role: 'user', content: '在吗' }
      ];
      const body: string = buildChatRequestBody('step-3.5-flash-2603', messages);
      expect(body.includes('"system":"你是宠物团子"')).assertTrue();
      expect(body.includes('"role":"user"')).assertTrue();
      expect(body.includes('"role":"system"')).assertFalse();
    });
    it('非法响应解析为失败', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const r1: LlmReply = parseChatResponse('not json');
      expect(r1.ok).assertFalse();
      expect(r1.errorMessage.length > 0).assertTrue();
    });
    it('缺content字段与空content均判失败', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      expect(parseChatResponse('{"id":"x"}').ok).assertFalse();
      expect(parseChatResponse('{"content":[]}').ok).assertFalse();
      expect(parseChatResponse('{"content":[{"type":"text","text":""}]}').ok).assertFalse();
    });
    it('正常响应解析出content文本', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const r2: LlmReply = parseChatResponse('{"content":[{"type":"text","text":"汪汪"}]}');
      expect(r2.ok).assertTrue();
      expect(r2.content).assertEqual('汪汪');
    });
    it('未配置Key时直接返回失败不发起网络请求', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const transport: HttpLlmTransport = new HttpLlmTransport(
        CommonConstants.LLM_BASE_URL, CommonConstants.LLM_MODEL, '', CommonConstants.LLM_TIMEOUT_MS);
      transport.chat([{ role: 'user', content: '你好' }]).then((reply: LlmReply) => {
        expect(reply.ok).assertFalse();
        expect(reply.errorMessage.includes('未配置')).assertTrue();
      });
    });
  });
}
