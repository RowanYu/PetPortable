import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CommonConstants } from '../constants/CommonConstants';

/**
 * 单条对话消息（Anthropic Messages 协议）
 * role 取值：'system' | 'user' | 'assistant'
 */
export interface AiChatMessage {
  role: string;
  content: string;
}

/**
 * 一次 LLM 调用的结果
 */
export interface LlmReply {
  ok: boolean;
  content: string;
  errorMessage: string;
}

/**
 * LLM 传输层接口：可替换为 Mock 实现用于测试
 */
export interface LlmTransport {
  chat(messages: AiChatMessage[]): Promise<LlmReply>;
}

/**
 * 构建 Anthropic Messages 协议请求体。
 * role 为 'system' 的消息拆分到顶层 system 字段，其余按顺序放入 messages。
 */
export function buildChatRequestBody(model: string, messages: AiChatMessage[]): string {
  let systemText: string = '';
  const chatMessages: AiChatMessage[] = [];
  for (let i: number = 0; i < messages.length; i += 1) {
    const item: AiChatMessage = messages[i];
    if (item.role === 'system') {
      systemText = systemText.length > 0 ? `${systemText}\n${item.content}` : item.content;
    } else {
      chatMessages.push(item);
    }
  }

  const requestBody: Record<string, Object> = {};
  requestBody['model'] = model;
  requestBody['max_tokens'] = CommonConstants.LLM_MAX_TOKENS;
  if (systemText.length > 0) {
    requestBody['system'] = systemText;
  }
  requestBody['messages'] = chatMessages;
  return JSON.stringify(requestBody);
}

/**
 * 解析 Anthropic Messages 协议响应：取 content 数组中首个 text 文本。
 * 任何结构异常都判为失败，绝不抛出。
 */
export function parseChatResponse(raw: string): LlmReply {
  const failed: LlmReply = { ok: false, content: '', errorMessage: '响应格式异常' };
  try {
    const json: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    const contentArr: Object | undefined = json['content'];
    if (contentArr === undefined || contentArr === null) {
      return failed;
    }
    const blocks: Array<Object> = contentArr as Array<Object>;
    for (let i: number = 0; i < blocks.length; i += 1) {
      const block: Record<string, Object> = blocks[i] as Record<string, Object>;
      const blockType: Object | undefined = block['type'];
      if (blockType === undefined || `${blockType}` !== 'text') {
        continue;
      }
      const textValue: Object | undefined = block['text'];
      const text: string = textValue === undefined || textValue === null ? '' : `${textValue}`;
      if (text.trim().length === 0) {
        return failed;
      }
      const okReply: LlmReply = { ok: true, content: text, errorMessage: '' };
      return okReply;
    }
    return failed;
  } catch (e) {
    const errorReply: LlmReply = { ok: false, content: '', errorMessage: '响应解析失败' };
    return errorReply;
  }
}

/**
 * HTTP 传输层：调用 StepFun Anthropic Messages 兼容接口。
 * 任何网络异常都返回 ok:false，绝不上抛。
 */
export class HttpLlmTransport implements LlmTransport {
  private readonly url: string;
  private readonly model: string;
  private readonly apiKey: string;
  private readonly timeoutMs: number;

  constructor(url: string, model: string, apiKey: string, timeoutMs: number) {
    this.url = url;
    this.model = model;
    this.apiKey = apiKey;
    this.timeoutMs = timeoutMs;
  }

  async chat(messages: AiChatMessage[]): Promise<LlmReply> {
    const notConfigured: LlmReply = { ok: false, content: '', errorMessage: '未配置Key' };
    if (this.apiKey.length === 0) {
      return notConfigured;
    }

    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const body: string = buildChatRequestBody(this.model, messages);
      const response: http.HttpResponse = await httpRequest.request(this.url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
          'anthropic-version': '2023-06-01'
        },
        extraData: body,
        connectTimeout: this.timeoutMs,
        readTimeout: this.timeoutMs,
        expectDataType: http.HttpDataType.STRING
      });

      if (response.responseCode === 200 && typeof response.result === 'string') {
        return parseChatResponse(response.result);
      }
      console.warn(`PetLlmClient HTTP ${response.responseCode}: ${response.result}`);
      const httpFailed: LlmReply = { ok: false, content: '', errorMessage: `HTTP ${response.responseCode}` };
      return httpFailed;
    } catch (e) {
      console.warn(`PetLlmClient request failed: ${(e as BusinessError).message}`);
      const networkFailed: LlmReply = { ok: false, content: '', errorMessage: '网络请求失败' };
      return networkFailed;
    } finally {
      httpRequest.destroy();
    }
  }
}
