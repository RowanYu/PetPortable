/**
 * 聊天消息共享模型
 * 从 ChatPage 局部定义提升为共享导出，供对话门面/持久化/页面共同使用
 */
export type ChatRole = '主人' | '宠物';

export interface ChatMessage {
  id: string;
  role: ChatRole;
  content: string;
  /** 消息来源：宠物侧为 'ai' | 'local'；主人侧或旧数据为空串 */
  source: string;
}
