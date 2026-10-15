import { PetDreamRecord, PetMemoryRecord, PetModel } from '../models/PetModel';
import { ChatMessage } from '../models/ChatModels';
import { PetLifecycleService } from './PetLifecycleService';
import { InteractionLogItem, InteractionService, InteractionType } from './InteractionService';
import { AiChatMessage, HttpLlmTransport, LlmTransport } from './PetLlmClient';
import { CommonConstants } from '../constants/CommonConstants';

/**
 * 一次 AI 对话的结果：content 为回复文本，source 标记来自 AI 引擎还是本地兜底
 */
export interface PetAiReply {
  content: string;
  source: 'ai' | 'local';
}

export class PetAiService {
  private static readonly MEMORY_LIMIT: number = 12;
  private static readonly CHAT_RECALL_LIMIT: number = 4;
  private static readonly INTERACTION_RECALL_LIMIT: number = 4;
  private static defaultTransportInstance: LlmTransport | undefined = undefined;

  /**
   * 默认传输层：惰性单例，读取 CommonConstants 的 StepFun 配置
   */
  static get defaultTransport(): LlmTransport {
    if (!PetAiService.defaultTransportInstance) {
      PetAiService.defaultTransportInstance = new HttpLlmTransport(
        CommonConstants.LLM_BASE_URL,
        CommonConstants.LLM_MODEL,
        CommonConstants.LLM_API_KEY,
        CommonConstants.LLM_TIMEOUT_MS
      );
    }
    return PetAiService.defaultTransportInstance;
  }

  /**
   * 真实 AI 对话入口：调度 DeepSeek 兼容 LLM，任何失败自动回退本地模板引擎。
   * 绝不上抛异常。
   */
  static async replyWithAI(pet: PetModel, userMessage: string, history: ChatMessage[],
    transport: LlmTransport): Promise<PetAiReply> {
    const sanitized: string = userMessage.trim();
    const finalMessage: string = sanitized.length > 0 ? sanitized : '你今天想和我聊点什么';

    let aiContent: string = '';
    try {
      const messages: AiChatMessage[] = PetAiService.buildConversationMessages(pet, finalMessage, history);
      const llmReply = await transport.chat(messages);
      if (llmReply.ok && llmReply.content.trim().length > 0) {
        aiContent = PetAiService.limitAiReply(llmReply.content.trim());
      }
    } catch (e) {
      aiContent = '';
    }

    if (aiContent.length > 0) {
      PetLifecycleService.addMemory(pet, '对话记忆', `主人：${finalMessage}`);
      PetLifecycleService.addMemory(pet, '对话记忆', `AI宠物：${aiContent}`);
      pet.currentSpeech = aiContent;
      const aiResult: PetAiReply = { content: aiContent, source: 'ai' };
      return aiResult;
    }

    // 回退：复用同步本地引擎（行为与 reply() 完全一致）
    const localResult: PetAiReply = { content: PetAiService.reply(pet, finalMessage), source: 'local' };
    return localResult;
  }

  /**
   * AI 回复截断：超过 LLM_REPLY_LIMIT 字截断并以省略号结尾
   */
  private static limitAiReply(reply: string): string {
    const limit: number = CommonConstants.LLM_REPLY_LIMIT;
    return reply.length <= limit ? reply : `${reply.slice(0, limit - 1)}…`;
  }


  /**
   * 构建多轮对话上下文：system（persona + 检索记忆） + 最近 N 条历史 + 当前用户消息
   * 供 replyWithAI 调用 LLM 时使用
   */
  static buildConversationMessages(pet: PetModel, userMessage: string, history: ChatMessage[]): AiChatMessage[] {
    const result: AiChatMessage[] = [];
    result.push({ role: 'system', content: PetAiService.buildSystemPrompt(pet, userMessage) });

    const recent: ChatMessage[] = history.length > CommonConstants.CHAT_HISTORY_LIMIT
      ? history.slice(history.length - CommonConstants.CHAT_HISTORY_LIMIT)
      : history;
    for (let i: number = 0; i < recent.length; i += 1) {
      const item: ChatMessage = recent[i];
      result.push({ role: item.role === '主人' ? 'user' : 'assistant', content: item.content });
    }

    result.push({ role: 'user', content: userMessage });
    return result;
  }

  /**
   * 构建 system 提示词：宠物人设 + 相关长期记忆（仅当检索结果非空时输出记忆小节）
   */
  private static buildSystemPrompt(pet: PetModel, userMessage: string): string {
    const label: string = pet.resolvePersonalityLabel();
    let prompt: string = `你是宠物"${pet.name}"（${pet.breed}，性格：${label}，心情：${pet.emotion}，` +
      `亲密度${pet.attributes.intimacy}/100）。` +
      '用简体中文以亲密宠物的口吻回复主人，60字以内，口语化、自然连贯，结合上面聊过的内容回答，不要用列表和表情符号。';

    const recalled: PetMemoryRecord[] = PetLifecycleService.recallMemories(pet, userMessage, PetAiService.CHAT_RECALL_LIMIT);
    const lines: string[] = [];
    for (let i: number = 0; i < recalled.length; i += 1) {
      const content: string = recalled[i].content.trim();
      if (content.length > 0) {
        lines.push(`- ${content}`);
      }
    }
    if (lines.length > 0) {
      prompt = `${prompt}\n你记得的事：\n${lines.join('\n')}`;
    }
    return prompt;
  }


  static reply(pet: PetModel, userMessage: string): string {
    const sanitized: string = userMessage.trim();
    const finalMessage: string = sanitized.length > 0 ? sanitized : '你今天想和我聊点什么';
    const userEmotion: string = PetAiService.resolveUserEmotion(finalMessage);
    const intent: string = PetAiService.resolveIntent(finalMessage);
    const reply: string = PetAiService.limitReply(
      PetAiService.resolveCompanionReply(pet, finalMessage, userEmotion, intent)
    );

    PetLifecycleService.addMemory(pet, '对话记忆', `主人：${finalMessage}`);
    PetLifecycleService.addMemory(pet, '对话记忆', `宠物：${reply}`);
    pet.currentSpeech = reply;
    return reply;
  }

  static generateDream(pet: PetModel, timestamp: number = Date.now()): PetDreamRecord {
    const category: string = PetAiService.resolveDreamCategory(pet);
    const now: number = timestamp;
    const dream: PetDreamRecord = new PetDreamRecord();
    dream.id = `${now}-${pet.dreams.length + 1}`;
    dream.timestamp = now;
    dream.category = category;

    const titlePrefix: string = PetAiService.pickOne(PetAiService.resolveTitlePrefixes(category));
    const place: string = PetAiService.pickOne(PetAiService.resolvePlaces(category));
    const sceneStart: string = PetAiService.pickOne(PetAiService.resolveSceneStarts(category));
    const sceneMiddle: string = PetAiService.pickOne(PetAiService.resolveSceneMiddles(category));
    const sceneConflict: string = PetAiService.pickOne(PetAiService.resolveSceneConflicts(category));
    const sceneEnding: string = PetAiService.pickOne(PetAiService.resolveSceneEndings(category));
    const timePhase: string = PetAiService.resolveTimePhase(now);
    const ownerTopic: string = PetAiService.resolveRecentOwnerTopic(pet);
    const preferredActivity: string = PetAiService.resolvePreferredActivity(pet);
    const closenessLabel: string = PetAiService.resolveClosenessLabel(pet);

    dream.title = `${titlePrefix}·${place}`;
    dream.content = `在${timePhase}的梦里，我和你来到${place}。${sceneStart}。你提到"${ownerTopic}"，于是我们${sceneMiddle}。后来${sceneConflict}，我因为${closenessLabel}慢慢安定下来。醒来前，我们还一起${sceneEnding}，像现实里你陪我${preferredActivity}时一样踏实。`;
    dream.moodTag = PetAiService.resolveMoodTag(category, pet.emotion);

    pet.dreams.unshift(dream);
    if (pet.dreams.length > PetAiService.MEMORY_LIMIT) {
      pet.dreams.pop();
    }

    PetLifecycleService.addMemory(pet, '长期记忆', `梦境：${dream.title}`);
    if (pet.dreams.length >= 3) {
      PetLifecycleService.unlockAchievement(pet, 'dream_starter', '初梦收藏家', '累计记录3篇梦境日记');
    }
    if (pet.dreams.length >= 8) {
      PetLifecycleService.unlockAchievement(pet, 'dream_master', '梦境大师', '累计记录8篇梦境日记');
    }
    return dream;
  }

  private static pickOne(items: string[]): string {
    if (items.length === 0) {
      return '';
    }
    const index: number = Math.floor(Math.random() * items.length);
    return items[index];
  }

  /**
   * 本地离线对话降级引擎。
   * 回复优先回答用户当前表达，不再固定拼接开场白、无关记忆和追问。
   */
  private static resolveCompanionReply(pet: PetModel, message: string,
    userEmotion: string, intent: string): string {
    if (intent === '身份') {
      return `我是${pet.name}呀，你的${pet.breed}伙伴。`;
    }

    if (intent === '状态') {
      return PetAiService.resolvePetStatusReply(pet, message);
    }

    if (intent === '回忆') {
      return PetAiService.resolveExplicitMemoryReply(pet, message);
    }

    if (PetAiService.isRecentInteractionQuestion(message)) {
      const interactionMemory: string = PetAiService.resolveInteractionMemory();
      return interactionMemory.length > 0 ? interactionMemory : '刚才我一直在这里等你来找我。';
    }

    const knowledgeReply: string = PetAiService.resolveSimpleKnowledgeReply(message);
    if (knowledgeReply.length > 0) {
      return knowledgeReply;
    }

    if (userEmotion !== '平静') {
      return PetAiService.resolveEmotionalReply(pet, message, userEmotion);
    }

    if (intent === '问候') {
      return PetAiService.resolveGreetingReply(pet, message);
    }
    if (intent === '告别') {
      return pet.attributes.intimacy >= 60
        ? '好吧，我在家等你。记得早点回来找我。'
        : '好，路上注意安全，我在这里等你。';
    }
    if (intent === '感谢') {
      return pet.personality.naughty >= 60
        ? '光说谢谢可不够，等会儿要多陪我玩一会儿。'
        : '不用谢呀，能陪着你我就很开心。';
    }
    if (intent === '道歉') {
      return '没关系，我没有躲开你。我们和好啦。';
    }
    if (intent === '亲昵') {
      return PetAiService.resolveAffectionReply(pet);
    }
    if (intent === '求助') {
      return PetAiService.resolveAdviceReply(message);
    }

    const topicReply: string = PetAiService.resolveTopicReply(pet, message);
    if (topicReply.length > 0) {
      return topicReply;
    }

    if (intent === '问答') {
      return '这个我现在还答不准，不想随便骗你。换个说法问我试试？';
    }

    return PetAiService.resolveDailyReply(pet, message);
  }

  private static resolveGreetingReply(pet: PetModel, message: string): string {
    if (message.includes('早安') || message.includes('早上好')) {
      return pet.attributes.energy <= 30
        ? '早呀……我还没完全睡醒，先让我靠你一会儿。'
        : '早呀！我已经醒啦，今天也想和你待在一起。';
    }
    if (message.includes('晚安')) {
      return '晚安，我就在旁边陪你。做个轻轻软软的好梦。';
    }
    if (pet.attributes.intimacy >= 65) {
      return PetAiService.pickStable([
        '你来啦，我刚好正想找你。',
        '我在呢。今天想先和我说什么？',
        '终于等到你啦，靠近一点嘛。'
      ], message);
    }
    return PetAiService.pickStable([
      '我在呀。今天过得怎么样？',
      '你好呀，我一直在这里。',
      '听见你叫我啦，想聊点什么？'
    ], message);
  }

  private static resolvePetStatusReply(pet: PetModel, message: string): string {
    if (message.includes('在干嘛') || message.includes('做什么')) {
      if (pet.attributes.energy <= 30) {
        return '刚才在打盹，听见你来就睁开眼啦。';
      }
      return pet.personality.naughty >= 60
        ? '在假装很乖，其实刚偷偷玩了会儿。'
        : '在这里等你，顺便发了一会儿呆。';
    }
    if (pet.emotion === '困倦' || pet.attributes.energy <= 25) {
      return '有点困，不过你来了，我还想再陪你说几句。';
    }
    if (pet.emotion === '悲伤' || pet.attributes.mood <= 35) {
      return '刚才有点闷闷的。你陪我一会儿，我会好很多。';
    }
    if (pet.emotion === '兴奋' || pet.attributes.mood >= 85) {
      return '我现在特别有精神，尾巴都快停不下来啦。';
    }
    return '我挺好的，看到你以后心情又亮了一点。';
  }

  private static resolveEmotionalReply(pet: PetModel, message: string, userEmotion: string): string {
    if (userEmotion === '开心') {
      return pet.personality.naughty >= 60
        ? '这么开心？那必须带上我一起庆祝，不许偷偷乐。'
        : '听得我也开心起来了。快把这件好事再讲给我听。';
    }
    if (userEmotion === '难过') {
      return pet.personality.warmth >= 60
        ? '先靠着我吧，不想说也没关系，我会安静陪你。'
        : '我在。你愿意说的话，我会认真听完。';
    }
    if (userEmotion === '生气') {
      return '先把最生气的那件事告诉我，不用急着让自己平静。';
    }
    if (userEmotion === '焦虑') {
      return message.includes('考试') || message.includes('工作')
        ? '先只管眼前最小的一步，别一次扛完。我陪你慢慢来。'
        : '先和我一起慢慢呼吸。你最担心的是哪一件事？';
    }
    return '你已经很累了，先歇一会儿。剩下的事可以晚一点再处理。';
  }

  private static resolveAffectionReply(pet: PetModel): string {
    if (pet.attributes.intimacy >= 70) {
      return pet.personality.naughty >= 60
        ? '当然喜欢呀，不过你今天还欠我一个抱抱。'
        : '喜欢。你一靠近，我就觉得这里是家。';
    }
    if (pet.attributes.intimacy >= 35) {
      return '喜欢呀，我已经开始熟悉你的声音和脚步了。';
    }
    return '我正在一点点喜欢上你，再多陪陪我吧。';
  }

  private static resolveAdviceReply(message: string): string {
    if (PetAiService.containsAny(message, ['要不要', '该不该', '能不能'])) {
      return '先想想你最在意什么，再选不会让自己后悔的那个。我陪你慢慢选。';
    }
    if (PetAiService.containsAny(message, ['压力', '考试', '作业', '工作'])) {
      return '先挑最急的一件做十分钟，做完再看下一件，别一次压住自己。';
    }
    return '先告诉我你卡在哪一步，我们从最容易动手的地方开始。';
  }

  private static resolveSimpleKnowledgeReply(message: string): string {
    if (message.includes('天空') && message.includes('蓝')) {
      return '阳光穿过空气时，蓝光更容易被散射，所以天空看起来是蓝色的。';
    }
    if (message.includes('为什么') && message.includes('下雨')) {
      return '云里的小水滴越聚越大，空气托不住时，就会落下来变成雨。';
    }
    if (message.includes('彩虹') && PetAiService.containsAny(message, ['怎么', '为什么', '形成'])) {
      return '阳光进入小水滴后发生折射和反射，分成不同颜色，就成了彩虹。';
    }
    if (message.includes('月亮') && message.includes('发光')) {
      return '月亮自己不会发光，我们看到的是它反射的太阳光。';
    }
    return '';
  }

  private static resolveTopicReply(pet: PetModel, message: string): string {
    if (PetAiService.containsAny(message, ['上班', '工作', '加班', '开会'])) {
      return '听起来今天挺费神的。回到我这里就先松一口气吧。';
    }
    if (PetAiService.containsAny(message, ['上课', '学习', '作业', '考试'])) {
      return '今天也认真撑下来了呀。先休息一下，再继续也不迟。';
    }
    if (PetAiService.containsAny(message, ['吃了', '好吃', '火锅', '奶茶', '蛋糕'])) {
      return pet.personality.naughty >= 60
        ? '听得我都馋了，下次可得给我留一小口。'
        : '听起来很好吃。你喜欢的话，下次还可以再去。';
    }
    if (PetAiService.containsAny(message, ['公园', '散步', '旅行', '出去玩'])) {
      return '听起来很舒服。下次也带上我，我会乖乖跟着你。';
    }
    if (PetAiService.containsAny(message, ['回家', '到家'])) {
      return '回来就好。我给你留的位置一直都在。';
    }
    return '';
  }

  private static resolveDailyReply(pet: PetModel, message: string): string {
    if (message.length <= 4) {
      return PetAiService.pickStable(['嗯，我在。', '听见啦，你说。', '我正听着呢。'], message);
    }
    if (pet.personality.curiosity >= 65) {
      return '这件事听起来有点意思。后来发生什么了？';
    }
    if (pet.personality.naughty >= 65) {
      return '这话我记下啦，不过你得再讲具体一点。';
    }
    if (pet.personality.warmth >= 60) {
      return '我在认真听。你想从哪一段开始讲？';
    }
    return '嗯，我在听。你愿意再说具体一点吗？';
  }

  private static resolveExplicitMemoryReply(pet: PetModel, message: string): string {
    const queryTerms: string[] = PetAiService.resolveMemoryQueryTerms(message);
    let bestTopic: string = '';
    let bestScore: number = 0;
    let fallbackTopic: string = '';
    for (let i: number = 0; i < pet.memories.length; i += 1) {
      const memory: PetMemoryRecord = pet.memories[i];
      const content: string = memory.content;
      if (!content.startsWith('主人：')) {
        continue;
      }
      const topic: string = content.slice(3).trim();
      if (topic.length === 0 || PetAiService.containsAny(topic, ['还记得', '记得我', '之前说过'])) {
        continue;
      }
      if (fallbackTopic.length === 0 && topic.length > 4 &&
        !PetAiService.containsAny(topic, ['你好', '在吗', '早安', '晚安', '嗨'])) {
        fallbackTopic = topic;
      }
      let score: number = 0;
      for (let j: number = 0; j < queryTerms.length; j += 1) {
        if (topic.includes(queryTerms[j])) {
          score += 1;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestTopic = topic;
      }
    }

    const recalledTopic: string = bestScore > 0 ? bestTopic : fallbackTopic;
    if (recalledTopic.length > 0) {
      const shortTopic: string = recalledTopic.length > 22 ? `${recalledTopic.slice(0, 22)}…` : recalledTopic;
      return `记得呀，你之前和我说过"${shortTopic}"。`;
    }
    return '我还没有找到那段记忆。你再告诉我一次，我会认真记住。';
  }

  private static resolveMemoryQueryTerms(message: string): string[] {
    const ignoredParts: string[] = [
      '还记得', '记得我', '记得', '上次', '之前', '说过', '告诉过',
      '我', '你', '是什么', '什么', '哪里', '哪儿', '怎么', '做', '吗',
      '呢', '的', '？', '?', '。', '，', ',', ' '
    ];
    let focus: string = message.trim();
    for (let i: number = 0; i < ignoredParts.length; i += 1) {
      focus = focus.split(ignoredParts[i]).join('');
    }

    const terms: string[] = [];
    for (let i: number = 0; i + 1 < focus.length; i += 1) {
      const term: string = focus.slice(i, i + 2);
      if (!terms.includes(term)) {
        terms.push(term);
      }
    }
    const semanticTerms: string[] = ['今天', '昨天', '明天', '喜欢', '讨厌', '想要', '计划', '工作', '学习'];
    for (let i: number = 0; i < semanticTerms.length; i += 1) {
      const term: string = semanticTerms[i];
      if (message.includes(term) && !terms.includes(term)) {
        terms.push(term);
      }
    }
    return terms;
  }

  private static isRecentInteractionQuestion(message: string): boolean {
    return PetAiService.containsAny(message, ['刚才做了什么', '刚刚做了什么', '刚才在干嘛']);
  }

  private static pickStable(items: string[], seed: string): string {
    if (items.length === 0) {
      return '';
    }
    let value: number = 0;
    for (let i: number = 0; i < seed.length; i += 1) {
      value = (value + seed.charCodeAt(i) * (i + 1)) % 2147483647;
    }
    return items[value % items.length];
  }

  private static limitReply(reply: string): string {
    const normalized: string = reply.trim();
    return normalized.length <= 50 ? normalized : `${normalized.slice(0, 49)}…`;
  }

  private static resolveNaturalOpener(pet: PetModel): string {
    const emotion: string = pet.emotion;
    const energy: number = pet.attributes.energy;
    const intimacy: number = pet.attributes.intimacy;
    const personality = pet.personality;

    if (energy <= 25 || emotion === '困倦') {
      return PetAiService.pickOne([
        '我刚打了个小盹',
        '我正窝在垫子上打哈欠',
        '我刚才眯了一小会儿',
        '我眼皮有点沉'
      ]);
    }
    if (emotion === '兴奋' || (energy >= 80 && personality.cheerful >= 60)) {
      return PetAiService.pickOne([
        intimacy >= 65 ? '我一看到你就精神了' : '我刚才满屋子跑了一圈',
        '我尾巴一直摇个不停',
        '我精神头可足了',
        '我刚自己玩了一会儿'
      ]);
    }
    if (emotion === '快乐') {
      return PetAiService.pickOne([
        '我今天心情挺好的',
        '我刚在窗边晒了会儿太阳',
        '我正开心地等你来找我',
        '我刚才自己溜达了一圈'
      ]);
    }
    if (emotion === '悲伤') {
      return PetAiService.pickOne([
        '我今天有点蔫蔫的',
        '我刚才自己趴了一会儿',
        '我正想你',
        '我心里有点不踏实'
      ]);
    }
    if (emotion === '焦虑') {
      return PetAiService.pickOne([
        '我刚才一直在门口等',
        '我有点担心你',
        '我心里有点不踏实',
        '我刚才走来走去'
      ]);
    }
    if (personality.naughty >= 65) {
      return PetAiService.pickOne([
        '我刚偷偷蹭了一下沙发',
        '我把你的拖鞋叼到窝里了',
        '我刚才咬了一会儿小球'
      ]);
    }
    return PetAiService.pickOne([
      intimacy >= 65 ? '你可算来找我' : '我正乖乖等你呢',
      '我刚在垫子上歇着',
      '我刚才自己溜达了一圈',
      '我正窝在窝里发呆'
    ]);
  }

  private static resolveRecentMemoryLine(pet: PetModel, currentMessage: string): string {
    const trimmedCurrent: string = currentMessage.trim();
    const chatMemory: string = PetAiService.resolveChatMemory(pet, trimmedCurrent);
    if (chatMemory.length > 0 && Math.random() < 0.6) {
      return chatMemory;
    }
    const interactionMemory: string = PetAiService.resolveInteractionMemory();
    if (interactionMemory.length > 0) {
      return interactionMemory;
    }
    return chatMemory;
  }

  private static resolveChatMemory(pet: PetModel, currentMessage: string): string {
    const memories = PetLifecycleService.recallMemories(pet, currentMessage, PetAiService.CHAT_RECALL_LIMIT);
    for (let i: number = 0; i < memories.length; i += 1) {
      const item = memories[i];
      if (item.type !== '对话记忆' || !item.content.startsWith('主人：')) {
        continue;
      }
      const topic: string = item.content.slice(3).trim();
      if (topic.length === 0 || topic === currentMessage.trim()) {
        continue;
      }
      const shortTopic: string = topic.length > 16 ? `${topic.slice(0, 16)}…` : topic;
      return PetAiService.pickOne([
        `刚才你说的"${shortTopic}"我也记着呢`,
        `你之前提过"${shortTopic}"，我还记得`,
        `你聊过的"${shortTopic}"，我心里有印象`,
        `上次聊的"${shortTopic}"我没忘`
      ]);
    }
    return '';
  }

  private static resolveInteractionMemory(): string {
    const logs: InteractionLogItem[] = InteractionService.getInstance().getRecentLogs(PetAiService.INTERACTION_RECALL_LIMIT);
    for (let i: number = 0; i < logs.length; i += 1) {
      const log: InteractionLogItem = logs[i];
      if (log.type === 'chat') {
        continue;
      }
      const memory: string = PetAiService.buildInteractionMemoryText(log);
      if (memory.length > 0) {
        return memory;
      }
    }
    return '';
  }

  private static buildInteractionMemoryText(log: InteractionLogItem): string {
    const type: InteractionType = log.type;
    const reaction: string = log.result.bubbleText.trim();
    if (type === 'pet') {
      return PetAiService.pickOne([
        '刚才你摸我，我舒服得眯起了眼',
        '你刚才的贴贴我还在回味',
        '被你摸了一下，我现在尾巴还在轻轻晃'
      ]);
    }
    if (type === 'feed') {
      const foodText: string = reaction.length > 0 ? reaction.replace('我吃到了', '').replace('，好满足', '') : '小零食';
      return PetAiService.pickOne([
        `你喂我的${foodText}味道还留在嘴里`,
        `刚才那个${foodText}真好吃，我还记得`,
        `我刚吃完小零食，正满足呢`
      ]);
    }
    if (type === 'play') {
      return PetAiService.pickOne([
        '刚才我们玩得挺开心，我还没尽兴',
        '刚才追来追去那一下，我现在还想再跑一圈',
        '我们刚才玩得我都出汗了',
        '刚才你扔的玩具我还想再玩'
      ]);
    }
    if (type === 'train') {
      return PetAiService.pickOne([
        '刚才练的动作我还在记',
        '你教我的口令我慢慢学着呢',
        '刚才练习的时候我感觉自己在进步',
        '你刚训练完我，我正认真琢磨呢'
      ]);
    }
    if (type === 'bath') {
      return PetAiService.pickOne([
        '我刚洗完澡，毛还香香的',
        '洗完澡身上暖暖的，我现在正干净',
        '刚洗完感觉浑身轻飘飘的'
      ]);
    }
    if (type === 'sleep') {
      return PetAiService.pickOne([
        '我刚睡醒一小会儿',
        '我刚才睡得可踏实了',
        '眯了一会儿，我现在精神了一点'
      ]);
    }
    return '';
  }

  private static resolveReplyLine(message: string, userEmotion: string, intent: string): string {
    if (userEmotion === '开心') {
      return PetAiService.pickOne([
        '我也跟着你一起开心，尾巴都快摇成小风扇了',
        '看你高兴我也跟着乐',
        '你开心我就开心，我蹦两下给你看'
      ]);
    }
    if (userEmotion === '难过') {
      return PetAiService.pickOne([
        '你靠我近一点，我乖乖陪你',
        '我挨着你坐着，你说什么我都听着',
        '抱抱我，我陪着你',
        '你要是想哭就靠着我'
      ]);
    }
    if (userEmotion === '生气') {
      return PetAiService.pickOne([
        '你先别急，我蹲这儿静静听你说',
        '我乖乖等你气消了再一起想办法',
        '你慢慢说，我哪儿也不去'
      ]);
    }
    if (userEmotion === '焦虑') {
      return PetAiService.pickOne([
        '我们一件一件来，先别急着下结论',
        '先别想那么多，我陪你把事情捋一捋',
        '我听你说，咱们慢慢理'
      ]);
    }
    if (userEmotion === '疲惫') {
      return PetAiService.pickOne([
        '你歇会儿，我守着你',
        '你先眯一会儿，我陪你',
        '什么事先放一放，你太累了'
      ]);
    }
    if (intent === '问候') {
      return PetAiService.pickOne([
        '我好着呢，你呢',
        '我在家等你呢',
        '嗯嗯，你今天怎么样'
      ]);
    }
    if (intent === '求助') {
      return PetAiService.pickOne([
        '你把细节说说，我陪你一起想办法',
        '要不我们先列个能马上做的小步骤',
        '你说说看，我帮你理一理'
      ]);
    }
    if (intent === '问答') {
      return PetAiService.pickOne([
        '我听着呢，你继续问',
        '我懂你的意思了',
        '嗯嗯，我这么理解的'
      ]);
    }
    if (intent === '回忆') {
      return PetAiService.pickOne([
        '那些片段我心里也都记着',
        '你说的那些我也都记得',
        '嗯，那段我也常想起'
      ]);
    }
    if (message.length <= 4) {
      return PetAiService.pickOne([
        '嗯嗯，你说',
        '我在听呢',
        '你说，我在呢'
      ]);
    }
    return PetAiService.pickOne([
      '你说的我都记下了',
      '嗯，我听着呢',
      '你说得对，我懂你意思了',
      '我听你说完心里有底了'
    ]);
  }

  private static resolveCloser(pet: PetModel, userEmotion: string, intent: string): string {
    if (userEmotion === '疲惫') {
      return PetAiService.pickOne([
        '你什么时候想聊我都在',
        '你睡会儿我守着你',
        '我陪你静静待着'
      ]);
    }
    if (userEmotion === '难过' || userEmotion === '焦虑') {
      return PetAiService.pickOne([
        '想说多少说多少，我不催你',
        '你什么时候想接着聊都行',
        '我哪儿也不去，你慢慢说'
      ]);
    }
    if (userEmotion === '生气') {
      return PetAiService.pickOne([
        '你气消了我们再一起想办法',
        '我等着你，没事儿',
        '你随时叫我'
      ]);
    }
    if (pet.attributes.intimacy >= 70) {
      return PetAiService.pickOne([
        '想聊啥继续',
        '你愿意再多和我说两句吗',
        '继续说嘛，我还想听',
        '想说就说，我都在'
      ]);
    }
    if (intent === '求助' || intent === '问答') {
      return PetAiService.pickOne([
        '你愿意再细说一点吗',
        '要不要多说说',
        '你慢慢讲，我听着'
      ]);
    }
    return PetAiService.pickOne([
      '想聊啥继续',
      '你说，我都在',
      '嗯嗯，你继续'
    ]);
  }

  private static resolveIntent(message: string): string {
    const text: string = message.trim();
    if (PetAiService.containsAny(text, ['你是谁', '你叫什么', '你的名字', '你是什么'])) {
      return '身份';
    }
    if (PetAiService.containsAny(text, ['你好吗', '你怎么样', '你在干嘛', '你在做什么', '心情怎么样'])) {
      return '状态';
    }
    if (PetAiService.containsAny(text, ['还记得', '记得我', '上次', '之前说过'])) {
      return '回忆';
    }
    if (PetAiService.containsAny(text, ['喜欢我', '爱我吗', '想我吗', '抱抱', '贴贴'])) {
      return '亲昵';
    }
    if (PetAiService.containsAny(text, ['谢谢', '多谢', '感谢'])) {
      return '感谢';
    }
    if (PetAiService.containsAny(text, ['对不起', '抱歉'])) {
      return '道歉';
    }
    if (PetAiService.containsAny(text, ['再见', '拜拜', '我走了', '先走了'])) {
      return '告别';
    }
    if (PetAiService.containsAny(text, ['怎么办', '如何', '怎么做', '建议', '要不要'])) {
      return '求助';
    }
    if (PetAiService.containsAny(text, ['难过', '压力', '烦', '焦虑', '累', '崩溃', '失眠'])) {
      return '情绪';
    }
    if (PetAiService.containsAny(text, ['开心', '高兴', '通过', '成功', '顺利'])) {
      return '喜悦';
    }
    if (PetAiService.containsAny(text, ['你好', '在吗', '早安', '早上好', '晚安', '嗨'])) {
      return '问候';
    }
    if (PetAiService.containsAny(text, ['什么是', '是什么意思', '为什么', '谁是', '科普', '介绍一下']) ||
      text.endsWith('？') || text.endsWith('?') || text.endsWith('吗')) {
      return '问答';
    }
    return '日常';
  }

  private static resolveUserEmotion(message: string): string {
    if (PetAiService.containsAny(message, ['开心', '高兴', '兴奋', '太棒', '顺利', '好消息'])) {
      return '开心';
    }
    if (PetAiService.containsAny(message, ['难过', '伤心', '委屈', '想哭', '不开心'])) {
      return '难过';
    }
    if (PetAiService.containsAny(message, ['生气', '火大', '烦死', '愤怒'])) {
      return '生气';
    }
    if (PetAiService.containsAny(message, ['焦虑', '紧张', '担心', '不安', '压力'])) {
      return '焦虑';
    }
    if (PetAiService.containsAny(message, ['好累', '累死', '疲惫', '困', '没精神'])) {
      return '疲惫';
    }
    return '平静';
  }

  private static containsAny(text: string, keywords: string[]): boolean {
    for (let i: number = 0; i < keywords.length; i += 1) {
      if (text.includes(keywords[i])) {
        return true;
      }
    }
    return false;
  }

  private static resolveTitlePrefixes(category: string): string[] {
    if (category === '快乐梦') {
      return ['晴天散步记录', '晚风回家路', '公园长椅小记'];
    }
    if (category === '回忆梦') {
      return ['第一次回家那天', '旧相册那一页', '你掌心的温度'];
    }
    if (category === '奇幻梦') {
      return ['云朵飞艇巡游', '星光邮局奇遇', '会说话的风之岛'];
    }
    if (category === '焦虑梦') {
      return ['雨夜等你回家', '人群里的脚步声', '夜班后的门口'];
    }
    return ['夜宵小铺排队记', '厨房香气探险', '小鱼干补给站'];
  }

  private static resolvePlaces(category: string): string[] {
    if (category === '快乐梦') {
      return ['楼下梧桐步道', '周末公园湖边', '家里阳台暖垫旁', '小区花园长椅'];
    }
    if (category === '回忆梦') {
      return ['第一次见面的客厅', '你接我回家的路口', '旧照片墙前', '熟悉的餐桌旁'];
    }
    if (category === '奇幻梦') {
      return ['漂浮云层上的小镇', '会发光的图书馆', '月光隧道尽头的广场', '会唱歌的森林'];
    }
    if (category === '焦虑梦') {
      return ['下班高峰的街口', '雨后的公交站台', '灯光忽明忽暗的走廊', '陌生又拥挤的商场'];
    }
    return ['夜市小吃摊前', '厨房灶台旁', '宠物零食货架前', '街角小面馆门口'];
  }

  private static resolveSceneStarts(category: string): string[] {
    if (category === '快乐梦') {
      return ['路边的风很轻，你弯下腰帮我理了理项圈'];
    }
    if (category === '回忆梦') {
      return ['我又看见你第一次叫我名字时的神情，声音和那天一样温柔'];
    }
    if (category === '奇幻梦') {
      return ['我追着一束会发光的尾巴跑，抬头发现天空挂着会慢慢转动的糖果星球'];
    }
    if (category === '焦虑梦') {
      return ['我听见很多急促的脚步声，一开始有点慌，尾巴都不敢抬起来'];
    }
    return ['我闻到小鱼干和热牛奶的味道，肚子咕噜咕噜地叫起来'];
  }

  private static resolveSceneMiddles(category: string): string[] {
    if (category === '快乐梦') {
      return ['沿着熟悉的小路慢慢散步，还在路边一起看了一会儿云'];
    }
    if (category === '回忆梦') {
      return ['重新走了一遍我们从陌生到熟悉的那段路，我一步也不想落下'];
    }
    if (category === '奇幻梦') {
      return ['我们坐上纸飞机改装的列车，在风里穿过会说话的云朵商店'];
    }
    if (category === '焦虑梦') {
      return ['贴着你的脚边往前走，你一边轻声安慰我，一边放慢了步子'];
    }
    return ['你帮我挑了好多零食，我抱着最喜欢的小鱼干开心地转圈圈'];
  }

  private static resolveSceneConflicts(category: string): string[] {
    if (category === '快乐梦') {
      return ['忽然有一阵大风把树叶吹得满天都是，你笑着把我抱到怀里'];
    }
    if (category === '回忆梦') {
      return ['我差点在巷口走丢，你远远喊了我一声，我立刻就认出了你'];
    }
    if (category === '奇幻梦') {
      return ['半路出现了一只巨大的闹钟怪，把我们追得满街飞奔'];
    }
    if (category === '焦虑梦') {
      return ['人群突然加快了节奏，雨点也密了起来，我的心跳一下子变快'];
    }
    return ['结果最后一份小鱼干被抢走了，我急得原地跺脚'];
  }

  private static resolveSceneEndings(category: string): string[] {
    if (category === '快乐梦') {
      return ['在便利店门口分着一块小点心，然后慢慢走回家'];
    }
    if (category === '回忆梦') {
      return ['坐在门口的台阶上听你说今天的烦恼，直到夜色完全安静下来'];
    }
    if (category === '奇幻梦') {
      return ['拿着闪闪发光的奖章回家，你说我是今天最勇敢的小伙伴'];
    }
    if (category === '焦虑梦') {
      return ['在屋檐下等雨停，你轻拍着我，我终于敢把头靠在你手臂上'];
    }
    return ['你把最后一块点心掰给我，我们心满意足地一起回到小窝'];
  }

  private static resolveTimePhase(now: number): string {
    const hour: number = new Date(now).getHours();
    if (hour >= 5 && hour < 10) {
      return '清晨';
    }
    if (hour < 14) {
      return '上午';
    }
    if (hour < 18) {
      return '午后';
    }
    if (hour < 22) {
      return '傍晚';
    }
    return '深夜';
  }

  private static resolveRecentOwnerTopic(pet: PetModel): string {
    const memoryLimit: number = Math.min(pet.memories.length, 20);
    for (let i: number = 0; i < memoryLimit; i += 1) {
      const item = pet.memories[i];
      if (item.type !== '对话记忆') {
        continue;
      }
      if (item.content.startsWith('主人：')) {
        const topic: string = item.content.slice(3).trim();
        if (topic.length > 0) {
          return topic.length > 14 ? `${topic.slice(0, 14)}…` : topic;
        }
      }
    }
    return '今天的日常';
  }

  private static resolvePreferredActivity(pet: PetModel): string {
    const stats = pet.interactionStats;
    let maxCount: number = stats.feedCount;
    let activity: string = '吃饭';

    if (stats.playCount > maxCount) {
      maxCount = stats.playCount;
      activity = '玩耍';
    }
    if (stats.petCount > maxCount) {
      maxCount = stats.petCount;
      activity = '贴贴';
    }
    if (stats.trainCount > maxCount) {
      maxCount = stats.trainCount;
      activity = '训练';
    }
    if (stats.chatCount > maxCount) {
      maxCount = stats.chatCount;
      activity = '聊天';
    }

    if (maxCount <= 0) {
      if (pet.attributes.energy <= 35) {
        return '安静休息';
      }
      return '散步聊天';
    }
    return activity;
  }

  private static resolveClosenessLabel(pet: PetModel): string {
    const intimacy: number = pet.attributes.intimacy;
    if (intimacy >= 75) {
      return '你熟悉的心跳和呼吸';
    }
    if (intimacy >= 40) {
      return '你手心里稳稳的温度';
    }
    return '你轻轻叫我名字的声音';
  }

  private static resolveMoodTag(category: string, emotion: string): string {
    if (category === '焦虑梦') {
      return emotion === '悲伤' ? '惦念' : '释然';
    }
    if (category === '回忆梦') {
      return '感动';
    }
    if (category === '快乐梦') {
      return '温暖';
    }
    return '平和';
  }

  private static resolveDreamCategory(pet: PetModel): string {
    if (pet.attributes.energy <= 30 || pet.attributes.health <= 35) {
      return '美食梦';
    }
    if (pet.attributes.mood >= 80) {
      return '快乐梦';
    }
    if (pet.attributes.mood <= 30) {
      return '焦虑梦';
    }
    if (pet.memories.length > 0 && pet.memories[0].type === '长期记忆') {
      return '回忆梦';
    }
    if (Math.random() > 0.82) {
      return '奇幻梦';
    }
    return '回忆梦';
  }
}
