import {
  MemoryType,
  PetAchievementRecord,
  PetEmotion,
  PetGrowthStage,
  PetMemoryRecord,
  PetModel
} from '../models/PetModel';

export type PersonalityInteractionType = 'pet' | 'feed' | 'play' | 'train' | 'bath' | 'sleep' | 'chat';

class MemoryScoreItem {
  memory: PetMemoryRecord = new PetMemoryRecord();
  score: number = 0;
}

export class PetLifecycleService {
  private static readonly DECAY_WINDOW_MS: number = 10 * 60 * 1000;
  private static readonly IDLE_WARNING_MS: number = 24 * 60 * 60 * 1000;
  private static readonly MEMORY_LIMIT: number = 120;
  private static readonly DIALOGUE_SUMMARY_BATCH: number = 10;

  static applyNaturalDecay(pet: PetModel, now: number = Date.now()): void {
    const elapsed: number = now - pet.lastInteractionTime;
    if (elapsed < PetLifecycleService.DECAY_WINDOW_MS) {
      PetLifecycleService.updateEmotionAndStage(pet);
      return;
    }

    const steps: number = Math.floor(elapsed / PetLifecycleService.DECAY_WINDOW_MS);
    const accelerating: boolean = elapsed > PetLifecycleService.IDLE_WARNING_MS;
    const healthDecay: number = accelerating ? steps * 2 : steps;
    const moodDecay: number = accelerating ? steps * 3 : steps * 2;
    const energyDecay: number = accelerating ? steps * 3 : steps * 2;

    pet.attributes.health = PetLifecycleService.clamp(pet.attributes.health - healthDecay);
    pet.attributes.mood = PetLifecycleService.clamp(pet.attributes.mood - moodDecay);
    pet.attributes.energy = PetLifecycleService.clamp(pet.attributes.energy - energyDecay);

    pet.lastInteractionTime = now - (elapsed % PetLifecycleService.DECAY_WINDOW_MS);
    PetLifecycleService.updateEmotionAndStage(pet);
  }

  static addMemory(pet: PetModel, type: MemoryType, content: string, now: number = Date.now()): void {
    const normalizedContent: string = content.trim();
    if (normalizedContent.length === 0) {
      return;
    }
    PetLifecycleService.pushMemory(pet, type, normalizedContent, now);

    if (type === '对话记忆') {
      PetLifecycleService.tryCompressDialogueMemories(pet, now);
    }

    PetLifecycleService.trimMemories(pet);
  }

  static recallMemories(pet: PetModel, query: string, limit: number = 3): PetMemoryRecord[] {
    const safeLimit: number = Math.max(1, Math.floor(limit));
    if (pet.memories.length === 0) {
      return [];
    }

    const normalizedQuery: string = query.trim();
    if (normalizedQuery.length === 0) {
      return pet.memories.slice(0, safeLimit);
    }

    const keywords: string[] = PetLifecycleService.extractKeywords(normalizedQuery);
    const scanLimit: number = Math.min(80, pet.memories.length);
    const scored: MemoryScoreItem[] = [];
    for (let i: number = 0; i < scanLimit; i += 1) {
      const memory: PetMemoryRecord = pet.memories[i];
      let score: number = 0;
      if (memory.content.includes(normalizedQuery)) {
        score += 5;
      }
      for (let j: number = 0; j < keywords.length; j += 1) {
        if (memory.content.includes(keywords[j])) {
          score += 1;
        }
      }
      if (memory.type === '长期记忆' || memory.type === '情感记忆') {
        score += 1;
      }
      if (score > 0) {
        const scoreItem: MemoryScoreItem = new MemoryScoreItem();
        scoreItem.memory = memory;
        scoreItem.score = score;
        scored.push(scoreItem);
      }
    }

    if (scored.length === 0) {
      const fallback: PetMemoryRecord[] = [];
      for (let i: number = 0; i < pet.memories.length; i += 1) {
        const memory: PetMemoryRecord = pet.memories[i];
        if (memory.type !== '行为记忆') {
          fallback.push(memory);
        }
        if (fallback.length >= safeLimit) {
          break;
        }
      }
      return fallback.length > 0 ? fallback : pet.memories.slice(0, safeLimit);
    }

    scored.sort((left: MemoryScoreItem, right: MemoryScoreItem) => {
      if (right.score === left.score) {
        return right.memory.timestamp - left.memory.timestamp;
      }
      return right.score - left.score;
    });

    return scored.slice(0, safeLimit).map((item: MemoryScoreItem) => item.memory);
  }

  static applyPersonalityGrowth(pet: PetModel, interactionType: PersonalityInteractionType): void {
    let cheerfulDelta: number = 0;
    let independenceDelta: number = 0;
    let curiosityDelta: number = 0;
    let naughtyDelta: number = 0;
    let warmthDelta: number = 0;

    if (interactionType === 'pet') {
      cheerfulDelta = 2;
      warmthDelta = 3;
    } else if (interactionType === 'feed') {
      cheerfulDelta = 1;
      warmthDelta = 2;
    } else if (interactionType === 'play') {
      cheerfulDelta = 2;
      curiosityDelta = 3;
      naughtyDelta = 2;
    } else if (interactionType === 'train') {
      independenceDelta = 2;
      naughtyDelta = -1;
    } else if (interactionType === 'bath') {
      independenceDelta = 1;
      warmthDelta = pet.attributes.intimacy >= 35 ? 2 : 1;
    } else if (interactionType === 'sleep') {
      independenceDelta = 2;
    } else if (interactionType === 'chat') {
      cheerfulDelta = 1;
      warmthDelta = 3;
      curiosityDelta = 1;
    }

    pet.personality.cheerful = PetLifecycleService.clamp(pet.personality.cheerful + cheerfulDelta);
    pet.personality.independence = PetLifecycleService.clamp(pet.personality.independence + independenceDelta);
    pet.personality.curiosity = PetLifecycleService.clamp(pet.personality.curiosity + curiosityDelta);
    pet.personality.naughty = PetLifecycleService.clamp(pet.personality.naughty + naughtyDelta);
    pet.personality.warmth = PetLifecycleService.clamp(pet.personality.warmth + warmthDelta);
  }

  static updateEmotionAndStage(pet: PetModel): void {
    const attributes = pet.attributes;
    let nextEmotion: PetEmotion = '平静';

    if (attributes.energy <= 20) {
      nextEmotion = '困倦';
    } else if (attributes.mood <= 25 || attributes.health <= 30) {
      nextEmotion = '悲伤';
    } else if (attributes.mood <= 40) {
      nextEmotion = '焦虑';
    } else if (attributes.mood >= 88 && attributes.energy >= 70) {
      nextEmotion = '兴奋';
    } else if (attributes.mood >= 70) {
      nextEmotion = '快乐';
    }

    pet.emotion = nextEmotion;
    pet.growthStage = PetLifecycleService.resolveGrowthStage(pet);

    if (pet.growthStage !== '初识期') {
      PetLifecycleService.unlockAchievement(pet, 'stage_breakthrough', '破壳而出', '宠物顺利度过初识期');
    }
  }

  static unlockAchievement(pet: PetModel, id: string, title: string, description: string): boolean {
    const exists: boolean = pet.achievements.some((item: PetAchievementRecord) => item.id === id);
    if (exists) {
      return false;
    }

    const record: PetAchievementRecord = new PetAchievementRecord();
    record.id = id;
    record.title = title;
    record.description = description;
    record.unlockedAt = Date.now();
    pet.achievements.unshift(record);
    return true;
  }

  private static resolveGrowthStage(pet: PetModel): PetGrowthStage {
    const days: number = Math.floor((Date.now() - pet.adoptedTimestamp) / (24 * 60 * 60 * 1000));
    if (days >= 90 || pet.attributes.intimacy >= 90) {
      return '默契期';
    }
    if (days >= 30 || pet.attributes.intimacy >= 60) {
      return '亲密期';
    }
    if (days >= 7 || pet.attributes.intimacy >= 30) {
      return '熟悉期';
    }
    return '初识期';
  }

  private static pushMemory(pet: PetModel, type: MemoryType, content: string, now: number): void {
    const record: PetMemoryRecord = new PetMemoryRecord();
    record.id = `${now}-${type}-${pet.memories.length + 1}`;
    record.type = type;
    record.content = content;
    record.timestamp = now;
    pet.memories.unshift(record);
  }

  private static tryCompressDialogueMemories(pet: PetModel, now: number): void {
    const dialogueMemories: PetMemoryRecord[] = [];
    for (let i: number = 0; i < pet.memories.length; i += 1) {
      const memory: PetMemoryRecord = pet.memories[i];
      if (memory.type === '对话记忆' && memory.content.startsWith('主人：')) {
        dialogueMemories.push(memory);
      }
    }
    if (dialogueMemories.length === 0 || dialogueMemories.length % PetLifecycleService.DIALOGUE_SUMMARY_BATCH !== 0) {
      return;
    }

    const marker: string = `对话阶段摘要(${dialogueMemories.length}轮)`;
    const exists: boolean = pet.memories.some((memory: PetMemoryRecord) => {
      return memory.type === '语义记忆' && memory.content.includes(marker);
    });
    if (exists) {
      return;
    }

    const summaryLimit: number = Math.min(3, dialogueMemories.length);
    const summaryParts: string[] = [];
    for (let i: number = 0; i < summaryLimit; i += 1) {
      const rawContent: string = dialogueMemories[i].content.slice(3).trim();
      if (rawContent.length > 0) {
        summaryParts.push(rawContent.length > 20 ? `${rawContent.slice(0, 20)}…` : rawContent);
      }
    }
    if (summaryParts.length === 0) {
      return;
    }

    PetLifecycleService.pushMemory(pet, '语义记忆', `${marker}：${summaryParts.join('；')}`, now + 1);
  }

  private static trimMemories(pet: PetModel): void {
    while (pet.memories.length > PetLifecycleService.MEMORY_LIMIT) {
      let removeIndex: number = -1;
      for (let i: number = pet.memories.length - 1; i >= 0; i -= 1) {
        const memoryType: MemoryType = pet.memories[i].type;
        if (memoryType === '对话记忆' || memoryType === '行为记忆') {
          removeIndex = i;
          break;
        }
      }
      if (removeIndex < 0) {
        for (let i: number = pet.memories.length - 1; i >= 0; i -= 1) {
          const memoryType: MemoryType = pet.memories[i].type;
          if (memoryType === '语义记忆') {
            removeIndex = i;
            break;
          }
        }
      }
      if (removeIndex < 0) {
        removeIndex = pet.memories.length - 1;
      }
      pet.memories.splice(removeIndex, 1);
    }
  }

  private static extractKeywords(input: string): string[] {
    const parts: string[] = input.split(/[\s，。！？,.!?:：；、]+/);
    const keywords: string[] = [];
    for (let i: number = 0; i < parts.length; i += 1) {
      const token: string = parts[i].trim();
      if (token.length >= 2 && !keywords.includes(token)) {
        keywords.push(token);
      }
      if (keywords.length >= 6) {
        break;
      }
    }
    return keywords;
  }

  private static clamp(value: number): number {
    return Math.min(100, Math.max(0, value));
  }
}
