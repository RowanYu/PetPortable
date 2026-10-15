import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PetModel } from '../models/PetModel';
import { PetCuteVoiceService, PetVoiceRole } from './PetCuteVoiceService';

class PetVoicePlaybackProfile {
  speed: number = 1.2;
  pitch: number = 1.08;
  volume: number = 0.92;
}

class PetTtsExtraParams {
  queueMode: Number = new Number(0);
  speed: Number = new Number(1.2);
  pitch: Number = new Number(1.08);
  volume: Number = new Number(0.92);
  playType: Number = new Number(1);
}

export class PetTtsService {
  private static instance: PetTtsService | undefined = undefined;

  private engine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private activePersonId: number = -1;
  private isCreatingEngine: boolean = false;
  private pendingText: string = '';
  private pendingRole: PetVoiceRole = '伙伴';
  private readonly cuteVoiceService: PetCuteVoiceService = PetCuteVoiceService.getInstance();

  private constructor() {
  }

  static getInstance(): PetTtsService {
    if (!PetTtsService.instance) {
      PetTtsService.instance = new PetTtsService();
    }
    return PetTtsService.instance;
  }

  ensureEngine(): void {
    this.ensureEngineForRole('伙伴');
  }

  private ensureEngineForRole(role: PetVoiceRole): void {
    const personId: number = this.resolveVoicePerson(role);
    if (this.engine && this.activePersonId === personId) {
      return;
    }
    if (this.isCreatingEngine) {
      return;
    }

    this.recreateEngine(personId);
  }

  private recreateEngine(personId: number): void {
    if (this.engine && this.engine.isBusy()) {
      this.engine.stop();
    }
    this.engine = undefined;
    this.activePersonId = -1;
    this.createEngineByMode(1, personId, true);
  }

  private createEngineByMode(onlineMode: 0 | 1, personId: number, allowDefaultPersonFallback: boolean): void {
    if (this.engine || this.isCreatingEngine) {
      return;
    }

    this.isCreatingEngine = true;
    const createParams: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: personId,
      online: onlineMode
    };

    textToSpeech.createEngine(createParams, (error: BusinessError, createdEngine: textToSpeech.TextToSpeechEngine): void => {
      this.isCreatingEngine = false;
      if (error) {
        if (onlineMode === 1) {
          this.createEngineByMode(0, personId, allowDefaultPersonFallback);
          return;
        }
        if (allowDefaultPersonFallback && personId !== 0) {
          this.createEngineByMode(1, 0, false);
          return;
        }
        console.error(`PetTtsService createEngine failed: ${error.code} ${error.message}`);
        return;
      }

      this.engine = createdEngine;
      this.activePersonId = personId;
      this.flushPending();
    });
  }

  speak(pet: PetModel, text: string): void {
    const normalizedText: string = text.trim();
    if (normalizedText.length === 0) {
      return;
    }

    this.pendingText = normalizedText;
    this.pendingRole = this.cuteVoiceService.resolveVoiceRole(pet);
    this.ensureEngineForRole(this.pendingRole);
    if (!this.engine) {
      return;
    }

    this.flushPending();
  }

  stop(): void {
    if (!this.engine) {
      this.pendingText = '';
      return;
    }

    if (this.engine.isBusy()) {
      this.engine.stop();
    }
    this.pendingText = '';
  }

  private flushPending(): void {
    if (!this.engine) {
      return;
    }

    const text: string = this.pendingText.trim();
    if (text.length === 0) {
      return;
    }
    const role: PetVoiceRole = this.pendingRole;
    const requiredPersonId: number = this.resolveVoicePerson(role);
    if (this.activePersonId !== requiredPersonId) {
      this.ensureEngineForRole(role);
      return;
    }
    this.pendingText = '';

    if (this.engine.isBusy()) {
      this.engine.stop();
    }

    const speakParams: textToSpeech.SpeakParams = this.buildSpeakParams(role, text);
    this.engine.speak(text, speakParams);
  }

  private buildSpeakParams(role: PetVoiceRole, text: string): textToSpeech.SpeakParams {
    const extraParams: Record<string, Object> = this.createExtraParamsRecord(this.resolveExtraParams(role, text));
    const speakParams: textToSpeech.SpeakParams = {
      requestId: `${Date.now()}`,
      extraParams
    };
    return speakParams;
  }

  private resolveExtraParams(role: PetVoiceRole, text: string): PetTtsExtraParams {
    const profile: PetVoicePlaybackProfile = this.resolvePlaybackProfile(role);
    const dynamicSpeed: number = this.resolveDynamicSpeed(profile.speed, text);
    const dynamicPitch: number = this.resolveDynamicPitch(profile.pitch, text);
    const params: PetTtsExtraParams = new PetTtsExtraParams();
    params.speed = new Number(dynamicSpeed);
    params.pitch = new Number(dynamicPitch);
    params.volume = new Number(profile.volume);
    return params;
  }

  private resolveVoicePerson(role: PetVoiceRole): number {
    if (role === '鸭子') {
      return 0;
    }
    if (role === '狐狸') {
      return 1;
    }
    if (role === '猫') {
      return 2;
    }
    if (role === '金毛') {
      return 3;
    }
    return 0;
  }

  private resolvePlaybackProfile(role: PetVoiceRole): PetVoicePlaybackProfile {
    const profile: PetVoicePlaybackProfile = new PetVoicePlaybackProfile();
    if (role === '鸭子') {
      profile.speed = 1.26;
      profile.pitch = 1.26;
      profile.volume = 0.95;
      return profile;
    }
    if (role === '狐狸') {
      profile.speed = 1.24;
      profile.pitch = 1.22;
      profile.volume = 0.93;
      return profile;
    }
    if (role === '猫') {
      profile.speed = 1.23;
      profile.pitch = 1.33;
      profile.volume = 0.92;
      return profile;
    }
    if (role === '金毛') {
      profile.speed = 1.24;
      profile.pitch = 1.12;
      profile.volume = 0.97;
      return profile;
    }
    profile.speed = 1.22;
    profile.pitch = 1.18;
    profile.volume = 0.93;
    return profile;
  }

  private resolveDynamicSpeed(baseSpeed: number, text: string): number {
    const length: number = text.trim().length;
    let speed: number = baseSpeed;
    if (length <= 8) {
      speed += 0.04;
    } else if (length >= 26) {
      speed -= 0.03;
    }
    return Math.max(1.14, Math.min(1.34, speed));
  }

  private resolveDynamicPitch(basePitch: number, text: string): number {
    const trimmedText: string = text.trim();
    const tail: string = trimmedText.slice(-1);
    let toneOffset: number = 0;
    if (tail === '？' || tail === '?') {
      toneOffset = 0.12;
    } else if (tail === '！' || tail === '!') {
      toneOffset = 0.08;
    } else if (tail === '。' || tail === '.') {
      toneOffset = -0.02;
    } else {
      toneOffset = 0.03;
    }

    const cuteOffset: number = this.resolveCuteOffset(trimmedText);
    const lengthOffset: number = trimmedText.length <= 8 ? 0.03 : (trimmedText.length >= 24 ? -0.01 : 0);
    const randomOffset: number = Math.random() * 0.08 - 0.04;
    const dynamicPitch: number = basePitch + toneOffset + cuteOffset + lengthOffset + randomOffset;
    return Math.max(0.96, Math.min(1.38, dynamicPitch));
  }

  private resolveCuteOffset(text: string): number {
    if (text.includes('呀') || text.includes('啦') || text.includes('呢') || text.includes('嘛') || text.includes('哇') || text.includes('嘿')) {
      return 0.04;
    }
    return 0.01;
  }

  private createExtraParamsRecord(params: PetTtsExtraParams): Record<string, Object> {
    const record: Record<string, Object> = new Object() as Record<string, Object>;
    record['queueMode'] = params.queueMode;
    record['speed'] = params.speed;
    record['pitch'] = params.pitch;
    record['volume'] = params.volume;
    record['playType'] = params.playType;
    return record;
  }
}
