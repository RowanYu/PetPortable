import { common } from '@kit.AbilityKit';
import { PetModel } from '../models/PetModel';
import { ChatMessage } from '../models/ChatModels';
import { PetAiService, PetAiReply } from './PetAiService';
import { LlmTransport } from './PetLlmClient';
import { PetPersistenceService } from './PetPersistenceService';
import { InteractionService } from './InteractionService';

/**
 * 低耦合对话门面：文本对话与语音对话的对等统一入口。
 * 负责多轮历史维护、持久化编排与 AI 调度委托；
 * 未来主界面语言按钮只需依赖本服务，不接触任何传输细节。
 */
export class PetConversationService {
  private static readonly HISTORY_MAX: number = 50;
  private static histories: Map<string, ChatMessage[]> = new Map();
  private static restoredKeys: Set<string> = new Set();

  private constructor() {
    // 工具类禁止实例化
  }

  /** 获取指定宠物的内存态历史（进程内共享；未恢复时返回空数组） */
  static getHistory(petKey: string): ChatMessage[] {
    let history: ChatMessage[] | undefined = PetConversationService.histories.get(petKey);
    if (history === undefined) {
      history = [];
      PetConversationService.histories.set(petKey, history);
    }
    return history;
  }

  /** 从持久化恢复指定宠物的聊天记录（幂等，同一 petKey 只恢复一次） */
  static async restoreHistory(petKey: string, context: common.Context): Promise<void> {
    if (PetConversationService.restoredKeys.has(petKey)) {
      return;
    }
    PetConversationService.restoredKeys.add(petKey);
    const json: string = await PetPersistenceService.loadChat(context, petKey);
    if (json.length === 0) {
      PetConversationService.histories.set(petKey, []);
      return;
    }
    PetConversationService.histories.set(petKey, PetConversationService.parseHistory(json));
  }

  /** 文本对话入口 */
  static async chatWithText(pet: PetModel, text: string, context: common.Context,
    transport?: LlmTransport): Promise<PetAiReply> {
    return PetConversationService.chatInternal(pet, text, context, transport);
  }

  /** 语音识别文本对话入口（与文本完全对等，走同一管线） */
  static async chatWithTranscript(pet: PetModel, transcript: string, context: common.Context,
    transport?: LlmTransport): Promise<PetAiReply> {
    return PetConversationService.chatInternal(pet, transcript, context, transport);
  }

  private static async chatInternal(pet: PetModel, text: string, context: common.Context,
    transport?: LlmTransport): Promise<PetAiReply> {
    const petKey: string = PetPersistenceService.resolvePetKey(pet);
    const history: ChatMessage[] = PetConversationService.getHistory(petKey);
    const snapshot: ChatMessage[] = history.slice();

    const reply: PetAiReply = await PetAiService.replyWithAI(
      pet, text, snapshot, transport !== undefined ? transport : PetAiService.defaultTransport);

    const finalText: string = text.trim().length > 0 ? text.trim() : '你今天想和我聊点什么';
    const userMessage: ChatMessage = {
      id: `${Date.now()}-user`,
      role: '主人',
      content: finalText,
      source: ''
    };
    history.push(userMessage);
    const petMessage: ChatMessage = {
      id: `${Date.now()}-pet`,
      role: '宠物',
      content: reply.content,
      source: reply.source
    };
    history.push(petMessage);

    if (history.length > PetConversationService.HISTORY_MAX) {
      const overflow: number = history.length - PetConversationService.HISTORY_MAX;
      PetConversationService.histories.set(petKey, history.slice(overflow));
    }

    await InteractionService.getInstance().chat(pet, finalText);
    await PetPersistenceService.persistChat(context, petKey,
      JSON.stringify(PetConversationService.getHistory(petKey)));
    await PetPersistenceService.persist(context);
    return reply;
  }

  /** 解析历史 JSON；非法数据返回空数组 */
  private static parseHistory(json: string): ChatMessage[] {
    const result: ChatMessage[] = [];
    try {
      const arr: Array<Object> = JSON.parse(json) as Array<Object>;
      for (let i: number = 0; i < arr.length; i += 1) {
        const item: Record<string, Object> = arr[i] as Record<string, Object>;
        const role: string = `${item['role'] ?? ''}`;
        if (role !== '主人' && role !== '宠物') {
          continue;
        }
        const message: ChatMessage = {
          id: `${item['id'] ?? ''}`,
          role: role,
          content: `${item['content'] ?? ''}`,
          source: `${item['source'] ?? ''}`
        };
        result.push(message);
      }
    } catch (e) {
      console.error('PetConversation parseHistory failed');
      return [];
    }
    return result;
  }
}
