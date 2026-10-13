import { PetModel } from '../models/PetModel';

export type PetVoiceRole = '鸭子' | '狐狸' | '猫' | '金毛' | '伙伴';
export type PetTouchActionType = 'pet' | 'play' | 'train' | 'chat' | 'speak';
export type PetTouchBodyPart = '头顶' | '脸颊' | '小爪' | '肚肚' | '尾巴';

export class PetVoiceSynthesisResult {
  voiceRole: PetVoiceRole = '伙伴';
  voiceText: string = '';
  displayText: string = '';
  speakDurationMs: number = 900;
}

export class PetTouchReactionPlan {
  bodyPart: PetTouchBodyPart = '头顶';
  actionType: PetTouchActionType = 'pet';
  promptText: string = '';
  toyId: string = 'ball';
  commandId: string = 'sit';
  speechText: string = '';
}

export class PetCuteVoiceService {
  private static instance: PetCuteVoiceService | undefined = undefined;

  private readonly toyIds: string[] = ['ball', 'yarn', 'frisbee'];
  private readonly commandIds: string[] = ['sit', 'shake_hand', 'turn'];

  private constructor() {
  }

  static getInstance(): PetCuteVoiceService {
    if (!PetCuteVoiceService.instance) {
      PetCuteVoiceService.instance = new PetCuteVoiceService();
    }
    return PetCuteVoiceService.instance;
  }

  synthesizeSpeech(pet: PetModel, content: string): PetVoiceSynthesisResult {
    const result: PetVoiceSynthesisResult = new PetVoiceSynthesisResult();
    result.voiceRole = this.resolveVoiceRole(pet);
    const normalized: string = this.normalizeContent(content);
    const prefix: string = this.resolveVoicePrefix(result.voiceRole);
    const suffix: string = this.resolveVoiceSuffix(result.voiceRole);
    result.voiceText = `${prefix}${normalized}${suffix}`;
    result.displayText = `${result.voiceRole}配音：${result.voiceText}`;
    result.speakDurationMs = this.resolveSpeakDuration(result.voiceText);
    return result;
  }

  buildRandomTouchReaction(pet: PetModel): PetTouchReactionPlan {
    const bodyPart: PetTouchBodyPart = this.resolveRandomBodyPart();
    return this.buildTouchReactionByBodyPart(pet, bodyPart);
  }

  buildTouchReactionByBodyPart(pet: PetModel, bodyPart: PetTouchBodyPart): PetTouchReactionPlan {
    const plan: PetTouchReactionPlan = new PetTouchReactionPlan();
    const role: PetVoiceRole = this.resolveVoiceRole(pet);
    plan.bodyPart = bodyPart;
    plan.promptText = this.resolvePromptByBodyPart(plan.bodyPart);
    plan.actionType = this.resolveActionByBodyPart(plan.bodyPart);

    if (plan.actionType === 'play') {
      plan.toyId = this.toyIds[this.randomRange(0, this.toyIds.length - 1)];
    }
    if (plan.actionType === 'train') {
      plan.commandId = this.commandIds[this.randomRange(0, this.commandIds.length - 1)];
    }

    const baseSpeech: string = this.resolveTouchBaseSpeech(plan.bodyPart, plan.actionType, role);
    plan.speechText = `${plan.promptText}，${baseSpeech}`;
    return plan;
  }

  resolveVoiceRole(pet: PetModel): PetVoiceRole {
    const modelPath: string = pet.modelPath.toLowerCase();
    const breed: string = pet.breed.toLowerCase();

    if (modelPath.includes('duck') || breed.includes('鸭')) {
      return '鸭子';
    }
    if (modelPath.includes('fox') || breed.includes('狐')) {
      return '狐狸';
    }
    if (modelPath.includes('cat') || breed.includes('猫')) {
      return '猫';
    }
    if (modelPath.includes('golden') || breed.includes('金毛')) {
      return '金毛';
    }
    return '伙伴';
  }

  private resolveRandomBodyPart(): PetTouchBodyPart {
    const partIndex: number = this.randomRange(0, 4);
    if (partIndex === 0) {
      return '头顶';
    }
    if (partIndex === 1) {
      return '脸颊';
    }
    if (partIndex === 2) {
      return '小爪';
    }
    if (partIndex === 3) {
      return '肚肚';
    }
    return '尾巴';
  }

  private resolvePromptByBodyPart(bodyPart: PetTouchBodyPart): string {
    if (bodyPart === '头顶') {
      return '你摸了我的头顶';
    }
    if (bodyPart === '脸颊') {
      return '你轻轻碰了我的脸颊';
    }
    if (bodyPart === '小爪') {
      return '你点了我的小爪';
    }
    if (bodyPart === '肚肚') {
      return '你戳了我的肚肚';
    }
    return '你碰了我的尾巴';
  }

  private resolveActionByBodyPart(bodyPart: PetTouchBodyPart): PetTouchActionType {
    const roll: number = this.randomRange(0, 99);
    if (bodyPart === '头顶') {
      if (roll < 58) {
        return 'pet';
      }
      if (roll < 84) {
        return 'speak';
      }
      return 'chat';
    }
    if (bodyPart === '脸颊') {
      if (roll < 54) {
        return 'chat';
      }
      if (roll < 82) {
        return 'speak';
      }
      return 'pet';
    }
    if (bodyPart === '小爪') {
      if (roll < 48) {
        return 'train';
      }
      if (roll < 74) {
        return 'play';
      }
      return 'speak';
    }
    if (bodyPart === '肚肚') {
      if (roll < 60) {
        return 'play';
      }
      if (roll < 88) {
        return 'speak';
      }
      return 'pet';
    }
    if (roll < 44) {
      return 'pet';
    }
    if (roll < 72) {
      return 'chat';
    }
    return 'speak';
  }

  private resolveTouchBaseSpeech(bodyPart: PetTouchBodyPart, actionType: PetTouchActionType, role: PetVoiceRole): string {
    let speech: string = '';
    if (actionType === 'play') {
      if (bodyPart === '肚肚') {
        speech = this.pickOne(['哈哈哈，肚肚好痒，我们来追球吧', '好舒服呀，快陪我玩会儿', '我已经准备好一起撒欢啦']);
        return this.decorateTouchSpeechByRole(role, speech);
      }
      if (bodyPart === '小爪') {
        speech = this.pickOne(['牵住小爪，我们去玩接飞盘', '小爪爪已经就位，出发玩耍', '带我去玩吧，我超有活力']);
        return this.decorateTouchSpeechByRole(role, speech);
      }
      speech = this.pickOne(['要一起玩游戏吗，我超期待', '陪我玩一会儿吧，我已经兴奋啦', '我想和你一起跑跑跳跳']);
      return this.decorateTouchSpeechByRole(role, speech);
    }
    if (actionType === 'train') {
      speech = this.pickOne(['收到口令，我马上执行动作', '训练模式开启，我会认真配合', '我会努力表现给你看']);
      return this.decorateTouchSpeechByRole(role, speech);
    }
    if (actionType === 'chat') {
      if (bodyPart === '脸颊') {
        speech = this.pickOne(['贴贴你的手心，我在认真听你说话', '你的指尖暖暖的，我想继续听你聊天', '和你聊天的时候我最放松啦']);
        return this.decorateTouchSpeechByRole(role, speech);
      }
      speech = this.pickOne(['我在认真听你说话呢', '继续说嘛，我最爱听你的声音', '你的每句话我都记在心里']);
      return this.decorateTouchSpeechByRole(role, speech);
    }
    if (actionType === 'speak') {
      if (bodyPart === '头顶') {
        speech = this.pickOne(['摸摸头就会变乖哦', '再摸一下，我会更开心', '你的手一来我就想撒娇']);
        return this.decorateTouchSpeechByRole(role, speech);
      }
      if (bodyPart === '小爪') {
        speech = this.pickOne(['小爪爪给你，今天也要一起加油', '握住小爪，我们就是最默契搭档', '碰到小爪我就会乖乖贴着你']);
        return this.decorateTouchSpeechByRole(role, speech);
      }
      if (bodyPart === '肚肚') {
        speech = this.pickOne(['肚肚被你碰到就会想打滚', '你一戳肚肚，我就开心到冒泡', '轻轻碰肚肚，我就想在你身边赖着']);
        return this.decorateTouchSpeechByRole(role, speech);
      }
      if (bodyPart === '脸颊') {
        speech = this.pickOne(['脸颊热热的，是被你宠的', '被你碰一下脸颊，我心都化了', '你一贴近我就会脸红啦']);
        return this.decorateTouchSpeechByRole(role, speech);
      }
      speech = this.pickOne(['尾巴摇起来啦，我超喜欢你', '你碰到尾巴啦，我开心得停不下来', '再碰一下尾巴，我就给你表演转圈']);
      return this.decorateTouchSpeechByRole(role, speech);
    }
    if (bodyPart === '尾巴') {
      speech = this.pickOne(['尾巴摇摇，今天也最喜欢你', '你一碰尾巴，我就超级高兴', '贴贴你，我的尾巴根本停不下来']);
      return this.decorateTouchSpeechByRole(role, speech);
    }
    speech = this.pickOne(['你的触摸好温柔，我最喜欢你啦', '被你摸到的时候我最安心', '只要你在，我就会一直开心']);
    return this.decorateTouchSpeechByRole(role, speech);
  }

  private decorateTouchSpeechByRole(role: PetVoiceRole, speech: string): string {
    if (role === '猫') {
      return `${speech}，喵呜`;
    }
    if (role === '鸭子') {
      return `${speech}，嘎嘎`;
    }
    if (role === '狐狸') {
      return `${speech}，嘤`;
    }
    if (role === '金毛') {
      return `${speech}，汪呜`;
    }
    return speech;
  }

  private pickOne(options: string[]): string {
    if (options.length === 0) {
      return '';
    }
    const index: number = this.randomRange(0, options.length - 1);
    return options[index];
  }

  private normalizeContent(content: string): string {
    const trimmed: string = content.trim();
    if (trimmed.length === 0) {
      return '主人我在这里陪着你';
    }
    const normalized: string = trimmed.replace(/[。！？!?,，、；：]+/g, '');
    if (normalized.length > 26) {
      return `${normalized.slice(0, 26)}…`;
    }
    return normalized;
  }

  private resolveVoicePrefix(role: PetVoiceRole): string {
    if (role === '鸭子') {
      return '嘎嘎～扑棱扑棱，';
    }
    if (role === '狐狸') {
      return '嘤呜～尾巴摇摇，';
    }
    if (role === '猫') {
      return '喵呜～蹭蹭你，';
    }
    if (role === '金毛') {
      return '汪呜～贴贴主人，';
    }
    return '啾啾～在你身边，';
  }

  private resolveVoiceSuffix(role: PetVoiceRole): string {
    if (role === '鸭子') {
      return '呀～';
    }
    if (role === '狐狸') {
      return '呢～';
    }
    if (role === '猫') {
      return '喵～';
    }
    if (role === '金毛') {
      return '汪～';
    }
    return '呀～';
  }

  private resolveSpeakDuration(voiceText: string): number {
    const length: number = voiceText.trim().length;
    const estimate: number = 520 + length * 56;
    return Math.max(900, Math.min(3200, estimate));
  }

  private randomRange(min: number, max: number): number {
    const safeMin: number = Math.ceil(min);
    const safeMax: number = Math.floor(max);
    const randomValue: number = Math.random() * (safeMax - safeMin + 1);
    return safeMin + Math.floor(randomValue);
  }
}
