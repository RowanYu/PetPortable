import { PetActionType, PetModel } from '../models/PetModel';
import { PetLifecycleService } from './PetLifecycleService';
import { PetCuteVoiceService } from './PetCuteVoiceService';

export type InteractionType = 'pet' | 'feed' | 'play' | 'train' | 'bath' | 'sleep' | 'chat';

export class AttributeChanges {
  health: number = 0;
  mood: number = 0;
  energy: number = 0;
  intimacy: number = 0;
  obedience: number = 0;
  toxicity: number = 0;
}

export class InteractionResult {
  success: boolean = false;
  petReaction: PetActionType = 'idle';
  attributeChanges: AttributeChanges = new AttributeChanges();
  bubbleText: string = '';
  timestamp: number = 0;
}

export interface FeedOptions {
  foodId: string;
  quantity?: number;
}

export interface PlayOptions {
  toyId: string;
  duration?: number;
}

export class InteractionLogItem {
  type: InteractionType = 'pet';
  result: InteractionResult = new InteractionResult();
}

export class InteractionStatsSnapshot {
  totalInteractions: number = 0;
  todayCount: number = 0;
  mostFrequentType: InteractionType = 'pet';
  lastInteractionTime: number = 0;
}

export class InteractionService {
  private static readonly LOG_LIMIT: number = 200;
  private static instance: InteractionService | undefined = undefined;
  private readonly logs: InteractionLogItem[] = [];
  private readonly cuteVoiceService: PetCuteVoiceService = PetCuteVoiceService.getInstance();

  private constructor() {
  }

  public static getInstance(): InteractionService {
    if (!InteractionService.instance) {
      InteractionService.instance = new InteractionService();
    }
    return InteractionService.instance;
  }

  async pet(pet: PetModel): Promise<InteractionResult> {
    const changes: AttributeChanges = this.createChanges(0, this.randomRange(8, 12), 0, this.randomRange(3, 6), 0, 0);
    const result: InteractionResult = this.buildResult('interact', changes, '好舒服啊，最喜欢主人陪我啦。');
    this.applyResultToPet(pet, 'pet', result);
    await this.logInteraction('pet', result);
    return result;
  }

  async feed(pet: PetModel, options: FeedOptions): Promise<InteractionResult> {
    const quantity: number = Math.max(1, options.quantity ?? 1);
    const healthDelta: number = Math.min(18, this.randomRange(10, 15) + quantity - 1);
    const energyDelta: number = Math.min(10, this.randomRange(3, 8) + quantity - 1);
    const changes: AttributeChanges = this.createChanges(healthDelta, 3, energyDelta, 0, 0, 0);
    const result: InteractionResult = this.buildResult('eat', changes, `我吃到了${this.resolveFoodName(options.foodId)}，好满足`);
    this.applyResultToPet(pet, 'feed', result);
    await this.logInteraction('feed', result);
    return result;
  }

  async play(pet: PetModel, options: PlayOptions): Promise<InteractionResult> {
    const durationSeconds: number = Math.max(10, Math.floor((options.duration ?? 30_000) / 1000));
    const moodDelta: number = Math.min(14, this.randomRange(8, 12) + Math.floor(durationSeconds / 45));
    const energyDelta: number = -Math.max(8, this.randomRange(8, 15) + Math.floor(durationSeconds / 60));
    const changes: AttributeChanges = this.createChanges(0, moodDelta, energyDelta, 4, 0, 0);
    const result: InteractionResult = this.buildResult('play', changes, '哈哈，我最喜欢和主人一起玩了，\n好玩。');
    this.applyResultToPet(pet, 'play', result);
    await this.logInteraction('play', result);
    return result;
  }

  async train(pet: PetModel, commandId: string): Promise<InteractionResult> {
    const obedienceDelta: number = this.randomRange(3, 7);
    const toxicityDelta: number = this.randomRange(-3, 3);
    const changes: AttributeChanges = this.createChanges(0, 0, -4, 0, obedienceDelta, toxicityDelta);
    const result: InteractionResult = this.buildResult('train', changes, `我学会了${this.resolveCommandName(commandId)}，你要继续训练我吗`);
    this.applyResultToPet(pet, 'train', result);
    await this.logInteraction('train', result);
    return result;
  }

  async bath(pet: PetModel): Promise<InteractionResult> {
    const shyAtFirst: boolean = pet.attributes.intimacy < 35;
    const moodDelta: number = shyAtFirst ? this.randomRange(0, 2) : this.randomRange(4, 6);
    const intimacyDelta: number = shyAtFirst ? 2 : 3;
    const bathSpeech: string = shyAtFirst
      ? '我刚开始想躲一下，但你很温柔，后来真的好舒服'
      : '洗得清清爽爽，毛发都亮起来了';
    const changes: AttributeChanges = this.createChanges(this.randomRange(8, 12), moodDelta, 0, intimacyDelta, 0, 0);
    const result: InteractionResult = this.buildResult('bath', changes, bathSpeech);
    this.applyResultToPet(pet, 'bath', result);
    await this.logInteraction('bath', result);
    return result;
  }

  async sleep(pet: PetModel): Promise<InteractionResult> {
    const changes: AttributeChanges = this.createChanges(0, 3, 100 - pet.attributes.energy, 0, 0, 0);
    const result: InteractionResult = this.buildResult('sleep', changes, '我好困啊主人，我先睡了。');
    this.applyResultToPet(pet, 'sleep', result);
    await this.logInteraction('sleep', result);
    return result;
  }

  async chat(pet: PetModel, userInput: string): Promise<InteractionResult> {
    const safeInput: string = userInput.trim();
    const hint: string = safeInput.length > 0 ? safeInput.slice(0, 12) : '今天的心情';
    const speech: string = pet.currentSpeech.trim();
    const bubbleText: string = speech.length > 0 ? speech : `我记住你说的“${hint}”啦`;
    const changes: AttributeChanges = this.createChanges(0, this.randomRange(2, 5), 0, this.randomRange(2, 4), 0, 0);
    const result: InteractionResult = this.buildResult('chat', changes, bubbleText);
    this.applyResultToPet(pet, 'chat', result);
    await this.logInteraction('chat', result);
    return result;
  }

  async getInteractionStats(pet: PetModel): Promise<InteractionStatsSnapshot> {
    const snapshot: InteractionStatsSnapshot = new InteractionStatsSnapshot();
    snapshot.totalInteractions = pet.interactionStats.totalInteractions;
    snapshot.todayCount = pet.interactionStats.todayCount;
    snapshot.lastInteractionTime = pet.interactionStats.lastInteractionTime;
    snapshot.mostFrequentType = this.resolveMostFrequentType(pet);
    return snapshot;
  }

  getRecentLogs(limit: number = 20): InteractionLogItem[] {
    const normalizedLimit: number = Math.max(1, Math.floor(limit));
    const start: number = Math.max(0, this.logs.length - normalizedLimit);
    return this.logs.slice(start).reverse();
  }

  private async logInteraction(type: InteractionType, result: InteractionResult): Promise<void> {
    const item: InteractionLogItem = new InteractionLogItem();
    item.type = type;
    item.result = result;
    this.logs.push(item);
    if (this.logs.length > InteractionService.LOG_LIMIT) {
      this.logs.shift();
    }
  }

  private applyResultToPet(pet: PetModel, type: InteractionType, result: InteractionResult): void {
    this.applyAttributeDelta(pet, result.attributeChanges);
    PetLifecycleService.applyPersonalityGrowth(pet, type);
    pet.actionVersion += 1;
    const actionVersion: number = pet.actionVersion;
    pet.currentAction = result.petReaction;
    pet.currentSpeech = result.bubbleText;
    pet.lastInteractionTime = result.timestamp;
    pet.interactionStats.lastInteractionTime = result.timestamp;
    pet.interactionStats.totalInteractions += 1;
    pet.interactionStats.todayCount += 1;

    if (type === 'pet') {
      pet.interactionStats.petCount += 1;
    } else if (type === 'feed') {
      pet.interactionStats.feedCount += 1;
    } else if (type === 'play') {
      pet.interactionStats.playCount += 1;
    } else if (type === 'train') {
      pet.interactionStats.trainCount += 1;
    } else if (type === 'bath') {
      pet.interactionStats.bathCount += 1;
    } else if (type === 'sleep') {
      pet.interactionStats.sleepCount += 1;
    } else if (type === 'chat') {
      pet.interactionStats.chatCount += 1;
    }

    PetLifecycleService.addMemory(pet, '行为记忆', `互动[${type}]：${pet.currentSpeech}`, result.timestamp);
    this.tryUnlockAchievements(pet);
    PetLifecycleService.updateEmotionAndStage(pet);

    const resetDelay: number = this.resolveResetDelay(pet, result.petReaction, pet.currentSpeech);
    if (resetDelay > 0) {
      setTimeout(() => {
        if (pet.actionVersion === actionVersion && pet.currentAction === result.petReaction) {
          pet.currentAction = 'idle';
          pet.currentSpeech = '';
        }
      }, resetDelay);
    }
  }

  private tryUnlockAchievements(pet: PetModel): void {
    if (pet.interactionStats.totalInteractions >= 1) {
      PetLifecycleService.unlockAchievement(pet, 'first_touch', '初次相遇', '完成第一次有效互动');
    }
    if (pet.interactionStats.totalInteractions >= 20) {
      PetLifecycleService.unlockAchievement(pet, 'active_companion', '高频陪伴', '累计互动达到20次');
    }
    if (pet.interactionStats.totalInteractions >= 100) {
      PetLifecycleService.unlockAchievement(pet, 'hundred_promise', '百次之约', '累计互动达到100次');
    }
    if (pet.interactionStats.feedCount >= 8) {
      PetLifecycleService.unlockAchievement(pet, 'care_feeder', '贴心饲养员', '累计喂食达到8次');
    }
    if (pet.interactionStats.playCount >= 8) {
      PetLifecycleService.unlockAchievement(pet, 'play_partner', '玩耍搭子', '累计玩耍达到8次');
    }
    if (pet.interactionStats.trainCount >= 6) {
      PetLifecycleService.unlockAchievement(pet, 'junior_trainer', '训练新秀', '累计训练达到6次');
    }
    if (pet.interactionStats.chatCount >= 10) {
      PetLifecycleService.unlockAchievement(pet, 'heart_talker', '贴心话友', '累计聊天达到10次');
    }
    if (pet.attributes.intimacy >= 60) {
      PetLifecycleService.unlockAchievement(pet, 'intimacy_up', '亲密升级', '亲密度达到60');
    }
    if (pet.attributes.intimacy >= 80) {
      PetLifecycleService.unlockAchievement(pet, 'heart_sync', '心有灵犀', '亲密度达到80+');
    }
    if (pet.growthStage === '默契期') {
      PetLifecycleService.unlockAchievement(pet, 'growth_peak', '默契同频', '成长进入默契期');
    }
  }

  private resolveResetDelay(pet: PetModel, action: PetActionType, speechText: string): number {
    // 金毛由 PetSprite 帧动画驱动回待机：图片两遍→介绍→待机；sleep 停留最后一张不自动回待机
    if (pet.modelPath.toLowerCase().includes('golden')) {
      return 0;
    }
    const minDelayBySpeech: number = this.resolveSpeechMinDisplayDuration(pet, speechText);
    if (action === 'sleep') {
      return Math.max(3500, minDelayBySpeech);
    }
    if (action === 'chat') {
      return Math.max(2600, minDelayBySpeech);
    }
    if (action === 'eat') {
      return Math.max(3600, minDelayBySpeech);
    }
    if (action === 'play' || action === 'train' || action === 'bath') {
      return Math.max(2800, minDelayBySpeech);
    }
    if (action === 'interact') {
      return Math.max(2200, minDelayBySpeech);
    }
    return minDelayBySpeech;
  }

  private resolveSpeechMinDisplayDuration(pet: PetModel, speechText: string): number {
    const content: string = speechText.trim();
    if (content.length === 0) {
      return 0;
    }
    const voiceResult = this.cuteVoiceService.synthesizeSpeech(pet, content);
    const estimate: number = Math.max(540 + content.length * 120, voiceResult.speakDurationMs + 260);
    return Math.max(1800, Math.min(5600, estimate));
  }

  private applyAttributeDelta(pet: PetModel, changes: AttributeChanges): void {
    pet.attributes.health = this.clamp100(pet.attributes.health + changes.health);
    pet.attributes.mood = this.clamp100(pet.attributes.mood + changes.mood);
    pet.attributes.energy = this.clamp100(pet.attributes.energy + changes.energy);
    pet.attributes.intimacy = this.clamp100(pet.attributes.intimacy + Math.max(0, changes.intimacy));
    pet.attributes.obedience = this.clamp100(pet.attributes.obedience + changes.obedience);
    pet.attributes.toxicity = this.clamp100(pet.attributes.toxicity + changes.toxicity);
  }

  private buildResult(reaction: PetActionType, attributeChanges: AttributeChanges, bubbleText: string): InteractionResult {
    const result: InteractionResult = new InteractionResult();
    result.success = true;
    result.petReaction = reaction;
    result.attributeChanges = attributeChanges;
    result.bubbleText = bubbleText;
    result.timestamp = Date.now();
    return result;
  }

  private createChanges(health: number, mood: number, energy: number, intimacy: number, obedience: number, toxicity: number): AttributeChanges {
    const changes: AttributeChanges = new AttributeChanges();
    changes.health = health;
    changes.mood = mood;
    changes.energy = energy;
    changes.intimacy = intimacy;
    changes.obedience = obedience;
    changes.toxicity = toxicity;
    return changes;
  }

  private resolveMostFrequentType(pet: PetModel): InteractionType {
    let mostFrequentType: InteractionType = 'pet';
    let maxCount: number = pet.interactionStats.petCount;

    if (pet.interactionStats.feedCount > maxCount) {
      maxCount = pet.interactionStats.feedCount;
      mostFrequentType = 'feed';
    }
    if (pet.interactionStats.playCount > maxCount) {
      maxCount = pet.interactionStats.playCount;
      mostFrequentType = 'play';
    }
    if (pet.interactionStats.trainCount > maxCount) {
      maxCount = pet.interactionStats.trainCount;
      mostFrequentType = 'train';
    }
    if (pet.interactionStats.bathCount > maxCount) {
      maxCount = pet.interactionStats.bathCount;
      mostFrequentType = 'bath';
    }
    if (pet.interactionStats.sleepCount > maxCount) {
      maxCount = pet.interactionStats.sleepCount;
      mostFrequentType = 'sleep';
    }
    if (pet.interactionStats.chatCount > maxCount) {
      mostFrequentType = 'chat';
    }

    return mostFrequentType;
  }

  private clamp100(value: number): number {
    return Math.min(100, Math.max(0, value));
  }

  private randomRange(min: number, max: number): number {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  private resolveFoodName(foodId: string): string {
    if (foodId === 'cat_food') {
      return '猫粮';
    }
    if (foodId === 'fish') {
      return '小鱼干';
    }
    if (foodId === 'milk') {
      return '温牛奶';
    }
    return '美味食物';
  }

  private resolveToyName(toyId: string): string {
    if (toyId === 'ball') {
      return '弹力球';
    }
    if (toyId === 'yarn') {
      return '毛线球';
    }
    if (toyId === 'frisbee') {
      return '飞盘';
    }
    return '玩具';
  }

  private resolveCommandName(commandId: string): string {
    if (commandId === 'sit') {
      return '坐下';
    }
    if (commandId === 'shake_hand') {
      return '握手';
    }
    if (commandId === 'turn') {
      return '转圈';
    }
    return '新指令';
  }
}
