import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  PetAchievementRecord,
  PetAttributes,
  PetDreamRecord,
  PetInteractionStats,
  PetMemoryRecord,
  PetModel,
  PetPersonality,
  PetActionType,
  PetEmotion,
  PetGrowthStage,
  MemoryType,
  PetRedeemedRewardRecord
} from '../models/PetModel';
import { PetStore } from './PetStore';

/** 宠物档案快照：PetModel 除 image 外全部字段（modelPath 承担图片还原键） */
export interface PetSnapshot {
  name: string;
  type: string;
  breed: string;
  level: number;
  exp: number;
  emotion: string;
  growthStage: string;
  currentAction: string;
  currentSpeech: string;
  modelPath: string;
  actionVersion: number;
  adoptedTimestamp: number;
  lastInteractionTime: number;
  attributes: PetSnapshotAttributes;
  personality: PetSnapshotPersonality;
  interactionStats: PetSnapshotStats;
  memories: PetSnapshotMemory[];
  dreams: PetSnapshotDream[];
  achievements: PetSnapshotAchievement[];
  redeemedRewards: PetSnapshotReward[];
}

export interface PetSnapshotAttributes {
  health: number;
  mood: number;
  energy: number;
  intimacy: number;
  obedience: number;
  toxicity: number;
}

export interface PetSnapshotPersonality {
  cheerful: number;
  independence: number;
  curiosity: number;
  naughty: number;
  warmth: number;
}

export interface PetSnapshotStats {
  totalInteractions: number;
  todayCount: number;
  petCount: number;
  feedCount: number;
  playCount: number;
  trainCount: number;
  bathCount: number;
  sleepCount: number;
  chatCount: number;
  voiceMinutes: number;
  lastInteractionTime: number;
}

export interface PetSnapshotMemory {
  id: string;
  type: string;
  content: string;
  timestamp: number;
}

export interface PetSnapshotDream {
  id: string;
  title: string;
  content: string;
  category: string;
  moodTag: string;
  timestamp: number;
}

export interface PetSnapshotAchievement {
  id: string;
  title: string;
  description: string;
  unlockedAt: number;
}

export interface PetSnapshotReward {
  id: string;
  title: string;
  cost: number;
  redeemedAt: number;
}

/**
 * 宠物档案与聊天记录持久化服务（Preferences JSON 快照）
 */
export class PetPersistenceService {
  private static readonly STORE_NAME: string = 'pet_store';
  private static readonly KEY_PET_LIST_JSON: string = 'petListJson';
  private static readonly KEY_CURRENT_INDEX: string = 'currentIndex';
  private static readonly KEY_CHAT_PREFIX: string = 'chat_';

  private constructor() {
    // 工具类禁止实例化
  }

  /** 宠物列表 → JSON 快照（逐字段手工拷贝，ArkTS 下不做解构剔除） */
  static toSnapshotJson(list: PetModel[]): string {
    const snapshots: PetSnapshot[] = [];
    for (let i: number = 0; i < list.length; i += 1) {
      snapshots.push(PetPersistenceService.toSnapshot(list[i]));
    }
    return JSON.stringify(snapshots);
  }

  /** JSON 快照 → 宠物列表；任何异常返回空数组不抛出 */
  static fromSnapshotJson(json: string): PetModel[] {
    const result: PetModel[] = [];
    try {
      const parsed: Object = JSON.parse(json) as Object;
      const snapshots: Array<Object> = parsed as Array<Object>;
      for (let i: number = 0; i < snapshots.length; i += 1) {
        const s: Record<string, Object> = snapshots[i] as Record<string, Object>;
        result.push(PetPersistenceService.fromSnapshot(s));
      }
    } catch (e) {
      console.error(`PetPersistence parse failed: ${json.length} chars`);
      return [];
    }
    return result;
  }

  /** 持久化宠物列表与当前索引；失败仅记录日志 */
  static async persist(context: common.Context): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PetPersistenceService.STORE_NAME);
      await store.put(PetPersistenceService.KEY_PET_LIST_JSON, PetPersistenceService.toSnapshotJson(PetStore.getList()));
      await store.put(PetPersistenceService.KEY_CURRENT_INDEX, PetStore.getCurrentIndex());
      await store.flush();
    } catch (e) {
      console.error(`PetPersistence persist failed: ${(e as Error).message}`);
    }
  }

  /** 启动时恢复宠物档案；成功返回 true */
  static async restore(context: common.Context): Promise<boolean> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PetPersistenceService.STORE_NAME);
      const json: string = `${await store.get(PetPersistenceService.KEY_PET_LIST_JSON, '')}`;
      if (json.length === 0) {
        return false;
      }
      const list: PetModel[] = PetPersistenceService.fromSnapshotJson(json);
      if (list.length === 0) {
        return false;
      }
      const indexValue: preferences.ValueType = await store.get(PetPersistenceService.KEY_CURRENT_INDEX, 0);
      const index: number = typeof indexValue === 'number' ? indexValue : 0;
      PetStore.setList(list, index);
      return true;
    } catch (e) {
      console.error(`PetPersistence restore failed: ${(e as Error).message}`);
      return false;
    }
  }

  /** 持久化指定宠物的聊天记录（messagesJson 为 ChatMessage[] 序列化结果） */
  static async persistChat(context: common.Context, petKey: string, messagesJson: string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PetPersistenceService.STORE_NAME);
      await store.put(PetPersistenceService.KEY_CHAT_PREFIX + petKey, messagesJson);
      await store.flush();
    } catch (e) {
      console.error(`PetPersistence persistChat failed: ${(e as Error).message}`);
    }
  }

  /** 读取指定宠物的聊天记录；无数据返回空串 */
  static async loadChat(context: common.Context, petKey: string): Promise<string> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PetPersistenceService.STORE_NAME);
      const value: preferences.ValueType = await store.get(PetPersistenceService.KEY_CHAT_PREFIX + petKey, '');
      return typeof value === 'string' ? value : '';
    } catch (e) {
      console.error(`PetPersistence loadChat failed: ${(e as Error).message}`);
      return '';
    }
  }

  /** 聊天记录存储键：优先 modelPath，其次名称 */
  static resolvePetKey(pet: PetModel): string {
    return pet.modelPath.length > 0 ? pet.modelPath : pet.name;
  }

  /** modelPath → 图片资源；未命中返回默认鸭子 */
  static resolveImage(modelPath: string): Resource {
    if (modelPath === 'fox_default') {
      return $r('app.media.fox_idle_01');
    }
    if (modelPath === 'golden_default') {
      return $r('app.media.golden_idle_01');
    }
    if (modelPath === 'cat_default') {
      return $r('app.media.cat_idle_01');
    }
    if (modelPath === 'live2d_mao_pro' || modelPath === 'live2d_real:mao_pro' || modelPath === 'live2d_real:shizuku') {
      return $r('app.media.live2d_mao_idle_01');
    }
    if (modelPath === 'coyote.glb') {
      return $r('app.media.pet_dog_1');
    }
    return $r('app.media.pet_duck_full');
  }

  private static toSnapshot(pet: PetModel): PetSnapshot {
    const attributes: PetSnapshotAttributes = {
      health: pet.attributes.health,
      mood: pet.attributes.mood,
      energy: pet.attributes.energy,
      intimacy: pet.attributes.intimacy,
      obedience: pet.attributes.obedience,
      toxicity: pet.attributes.toxicity
    };
    const personality: PetSnapshotPersonality = {
      cheerful: pet.personality.cheerful,
      independence: pet.personality.independence,
      curiosity: pet.personality.curiosity,
      naughty: pet.personality.naughty,
      warmth: pet.personality.warmth
    };
    const stats: PetSnapshotStats = {
      totalInteractions: pet.interactionStats.totalInteractions,
      todayCount: pet.interactionStats.todayCount,
      petCount: pet.interactionStats.petCount,
      feedCount: pet.interactionStats.feedCount,
      playCount: pet.interactionStats.playCount,
      trainCount: pet.interactionStats.trainCount,
      bathCount: pet.interactionStats.bathCount,
      sleepCount: pet.interactionStats.sleepCount,
      chatCount: pet.interactionStats.chatCount,
      voiceMinutes: pet.interactionStats.voiceMinutes,
      lastInteractionTime: pet.interactionStats.lastInteractionTime
    };
    const memories: PetSnapshotMemory[] = [];
    for (let i: number = 0; i < pet.memories.length; i += 1) {
      const m: PetMemoryRecord = pet.memories[i];
      const item: PetSnapshotMemory = { id: m.id, type: m.type, content: m.content, timestamp: m.timestamp };
      memories.push(item);
    }
    const dreams: PetSnapshotDream[] = [];
    for (let i: number = 0; i < pet.dreams.length; i += 1) {
      const d: PetDreamRecord = pet.dreams[i];
      const item: PetSnapshotDream = {
        id: d.id, title: d.title, content: d.content,
        category: d.category, moodTag: d.moodTag, timestamp: d.timestamp
      };
      dreams.push(item);
    }
    const achievements: PetSnapshotAchievement[] = [];
    for (let i: number = 0; i < pet.achievements.length; i += 1) {
      const a: PetAchievementRecord = pet.achievements[i];
      const item: PetSnapshotAchievement = {
        id: a.id, title: a.title, description: a.description, unlockedAt: a.unlockedAt
      };
      achievements.push(item);
    }
    const rewards: PetSnapshotReward[] = [];
    for (let i: number = 0; i < pet.redeemedRewards.length; i += 1) {
      const r: PetRedeemedRewardRecord = pet.redeemedRewards[i];
      const item: PetSnapshotReward = { id: r.id, title: r.title, cost: r.cost, redeemedAt: r.redeemedAt };
      rewards.push(item);
    }

    const snapshot: PetSnapshot = {
      name: pet.name,
      type: pet.type,
      breed: pet.breed,
      level: pet.level,
      exp: pet.exp,
      emotion: pet.emotion,
      growthStage: pet.growthStage,
      currentAction: pet.currentAction,
      currentSpeech: pet.currentSpeech,
      modelPath: pet.modelPath,
      actionVersion: pet.actionVersion,
      adoptedTimestamp: pet.adoptedTimestamp,
      lastInteractionTime: pet.lastInteractionTime,
      attributes: attributes,
      personality: personality,
      interactionStats: stats,
      memories: memories,
      dreams: dreams,
      achievements: achievements,
      redeemedRewards: rewards
    };
    return snapshot;
  }

  private static fromSnapshot(s: Record<string, Object>): PetModel {
    const pet: PetModel = new PetModel(`${s['name'] ?? ''}`, `${s['type'] ?? ''}`);
    pet.breed = `${s['breed'] ?? ''}`;
    pet.level = Number(s['level'] ?? 1);
    pet.exp = Number(s['exp'] ?? 0);
    pet.emotion = `${s['emotion'] ?? '平静'}` as PetEmotion;
    pet.growthStage = `${s['growthStage'] ?? '初识期'}` as PetGrowthStage;
    pet.currentAction = `${s['currentAction'] ?? 'idle'}` as PetActionType;
    pet.currentSpeech = `${s['currentSpeech'] ?? ''}`;
    pet.modelPath = `${s['modelPath'] ?? ''}`;
    pet.actionVersion = Number(s['actionVersion'] ?? 0);
    pet.adoptedTimestamp = Number(s['adoptedTimestamp'] ?? Date.now());
    pet.lastInteractionTime = Number(s['lastInteractionTime'] ?? Date.now());
    pet.image = PetPersistenceService.resolveImage(pet.modelPath);

    const attr: Record<string, Object> = (s['attributes'] ?? {}) as Record<string, Object>;
    pet.attributes = new PetAttributes();
    pet.attributes.health = Number(attr['health'] ?? 88);
    pet.attributes.mood = Number(attr['mood'] ?? 82);
    pet.attributes.energy = Number(attr['energy'] ?? 76);
    pet.attributes.intimacy = Number(attr['intimacy'] ?? 12);
    pet.attributes.obedience = Number(attr['obedience'] ?? 48);
    pet.attributes.toxicity = Number(attr['toxicity'] ?? 16);

    const pers: Record<string, Object> = (s['personality'] ?? {}) as Record<string, Object>;
    pet.personality = new PetPersonality();
    pet.personality.cheerful = Number(pers['cheerful'] ?? 52);
    pet.personality.independence = Number(pers['independence'] ?? 44);
    pet.personality.curiosity = Number(pers['curiosity'] ?? 58);
    pet.personality.naughty = Number(pers['naughty'] ?? 35);
    pet.personality.warmth = Number(pers['warmth'] ?? 60);

    const stats: Record<string, Object> = (s['interactionStats'] ?? {}) as Record<string, Object>;
    pet.interactionStats = new PetInteractionStats();
    pet.interactionStats.totalInteractions = Number(stats['totalInteractions'] ?? 0);
    pet.interactionStats.todayCount = Number(stats['todayCount'] ?? 0);
    pet.interactionStats.petCount = Number(stats['petCount'] ?? 0);
    pet.interactionStats.feedCount = Number(stats['feedCount'] ?? 0);
    pet.interactionStats.playCount = Number(stats['playCount'] ?? 0);
    pet.interactionStats.trainCount = Number(stats['trainCount'] ?? 0);
    pet.interactionStats.bathCount = Number(stats['bathCount'] ?? 0);
    pet.interactionStats.sleepCount = Number(stats['sleepCount'] ?? 0);
    pet.interactionStats.chatCount = Number(stats['chatCount'] ?? 0);
    pet.interactionStats.voiceMinutes = Number(stats['voiceMinutes'] ?? 0);
    pet.interactionStats.lastInteractionTime = Number(stats['lastInteractionTime'] ?? 0);

    const memories: Array<Object> = (s['memories'] ?? []) as Array<Object>;
    for (let i: number = 0; i < memories.length; i += 1) {
      const m: Record<string, Object> = memories[i] as Record<string, Object>;
      const record: PetMemoryRecord = new PetMemoryRecord();
      record.id = `${m['id'] ?? ''}`;
      record.type = `${m['type'] ?? '行为记忆'}` as MemoryType;
      record.content = `${m['content'] ?? ''}`;
      record.timestamp = Number(m['timestamp'] ?? 0);
      pet.memories.push(record);
    }

    const dreams: Array<Object> = (s['dreams'] ?? []) as Array<Object>;
    for (let i: number = 0; i < dreams.length; i += 1) {
      const d: Record<string, Object> = dreams[i] as Record<string, Object>;
      const record: PetDreamRecord = new PetDreamRecord();
      record.id = `${d['id'] ?? ''}`;
      record.title = `${d['title'] ?? ''}`;
      record.content = `${d['content'] ?? ''}`;
      record.category = `${d['category'] ?? ''}`;
      record.moodTag = `${d['moodTag'] ?? ''}`;
      record.timestamp = Number(d['timestamp'] ?? 0);
      pet.dreams.push(record);
    }

    const achievements: Array<Object> = (s['achievements'] ?? []) as Array<Object>;
    for (let i: number = 0; i < achievements.length; i += 1) {
      const a: Record<string, Object> = achievements[i] as Record<string, Object>;
      const record: PetAchievementRecord = new PetAchievementRecord();
      record.id = `${a['id'] ?? ''}`;
      record.title = `${a['title'] ?? ''}`;
      record.description = `${a['description'] ?? ''}`;
      record.unlockedAt = Number(a['unlockedAt'] ?? 0);
      pet.achievements.push(record);
    }

    const rewards: Array<Object> = (s['redeemedRewards'] ?? []) as Array<Object>;
    for (let i: number = 0; i < rewards.length; i += 1) {
      const r: Record<string, Object> = rewards[i] as Record<string, Object>;
      const record: PetRedeemedRewardRecord = new PetRedeemedRewardRecord();
      record.id = `${r['id'] ?? ''}`;
      record.title = `${r['title'] ?? ''}`;
      record.cost = Number(r['cost'] ?? 0);
      record.redeemedAt = Number(r['redeemedAt'] ?? 0);
      pet.redeemedRewards.push(record);
    }

    return pet;
  }
}
