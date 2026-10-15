export type PetActionType = 'idle' | 'interact' | 'play' | 'eat' | 'chat' | 'sleep' | 'train' | 'bath' | 'hot' | 'wet';
export type PetEmotion = '平静' | '快乐' | '兴奋' | '焦虑' | '悲伤' | '困倦';
export type PetGrowthStage = '初识期' | '熟悉期' | '亲密期' | '默契期';
export type MemoryType = '对话记忆' | '语义记忆' | '长期记忆' | '情感记忆' | '行为记忆';
export type PetPersonalityLabel = '活泼' | '胆小' | '温顺' | '好奇' | '独立' | '调皮' | '黏人';

@Observed
export class PetAttributes {
  health: number = 88;
  mood: number = 82;
  energy: number = 76;
  intimacy: number = 12;
  obedience: number = 48;
  toxicity: number = 16;
}

@Observed
export class PetPersonality {
  cheerful: number = 52;
  independence: number = 44;
  curiosity: number = 58;
  naughty: number = 35;
  warmth: number = 60;
}

@Observed
export class PetMemoryRecord {
  id: string = '';
  type: MemoryType = '行为记忆';
  content: string = '';
  timestamp: number = 0;
}

@Observed
export class PetDreamRecord {
  id: string = '';
  title: string = '';
  content: string = '';
  category: string = '';
  moodTag: string = '';
  timestamp: number = 0;
}

@Observed
export class PetAchievementRecord {
  id: string = '';
  title: string = '';
  description: string = '';
  unlockedAt: number = 0;
}

@Observed
export class PetRedeemedRewardRecord {
  id: string = '';
  title: string = '';
  cost: number = 0;
  redeemedAt: number = 0;
}

@Observed
export class PetInteractionStats {
  totalInteractions: number = 0;
  todayCount: number = 0;
  petCount: number = 0;
  feedCount: number = 0;
  playCount: number = 0;
  trainCount: number = 0;
  bathCount: number = 0;
  sleepCount: number = 0;
  chatCount: number = 0;
  voiceMinutes: number = 0;
  lastInteractionTime: number = 0;
}

@Observed
export class PetModel {
  name: string = '小橘';
  type: string = '宠物';
  breed: string = '陪伴动物';
  level: number = 1;
  exp: number = 0;
  attributes: PetAttributes = new PetAttributes();
  personality: PetPersonality = new PetPersonality();
  emotion: PetEmotion = '平静';
  growthStage: PetGrowthStage = '初识期';

  currentAction: PetActionType = 'idle';
  currentSpeech: string = '';
  image: Resource = $r('app.media.pet_duck_full');
  modelPath: string = '';
  actionVersion: number = 0;

  adoptedTimestamp: number = Date.now();
  lastInteractionTime: number = Date.now();
  memories: PetMemoryRecord[] = [];
  dreams: PetDreamRecord[] = [];
  achievements: PetAchievementRecord[] = [];
  redeemedRewards: PetRedeemedRewardRecord[] = [];
  interactionStats: PetInteractionStats = new PetInteractionStats();

  constructor(name: string, type: string, image?: Resource, modelPath?: string) {
    this.name = name;
    this.type = type;
    this.breed = type;
    if (image) {
      this.image = image;
    }
    if (modelPath) {
      this.modelPath = modelPath;
    }
  }

  /**
   * 由性格数值推导性格标签：取最突出的特质组合
   */
  resolvePersonalityLabel(): PetPersonalityLabel {
    const p: PetPersonality = this.personality;
    // 活泼：cheerful 高 + naughty 中
    if (p.cheerful >= 60 && p.naughty >= 40) {
      return '活泼';
    }
    // 黏人：warmth 高 + independence 低
    if (p.warmth >= 65 && p.independence < 50) {
      return '黏人';
    }
    // 胆小：independence 低 + curiosity 低 + cheerful 低
    if (p.cheerful < 45 && p.curiosity < 50) {
      return '胆小';
    }
    // 好奇：curiosity 最高
    if (p.curiosity >= 60 && p.curiosity >= p.cheerful && p.curiosity >= p.warmth) {
      return '好奇';
    }
    // 调皮：naughty 突出
    if (p.naughty >= 55) {
      return '调皮';
    }
    // 独立：independence 最高
    if (p.independence >= 60 && p.independence >= p.warmth) {
      return '独立';
    }
    // 温顺：默认
    return '温顺';
  }
}
