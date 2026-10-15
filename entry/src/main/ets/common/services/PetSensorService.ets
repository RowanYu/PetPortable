import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CommonConstants } from '../constants/CommonConstants';
import { PetModel } from '../models/PetModel';
import { PetLifecycleService } from './PetLifecycleService';

export interface EnvironmentSnapshot {
  temperature: number;
  humidity: number;
  light: number;
  comfortScore: number;
  statusText: string;
  infraredDetected: boolean;
  activityLevel: string;
  timestamp: number;
  source: 'device' | 'dev' | 'mock';
}

export interface EnvFetchResult {
  snapshot: EnvironmentSnapshot;
  message: string;
}

const TAG: string = 'PetSensorService';

export class PetSensorService {
  private static readonly WARNING_COOLDOWN_MS: number = 15 * 60 * 1000;
  // 过热/过湿动作的最短间隔，避免反复触发
  private static readonly EXTREME_ACTION_COOLDOWN_MS: number = 20 * 1000;
  private static latest: EnvironmentSnapshot = {
    temperature: 26.2,
    humidity: 56,
    light: 280,
    comfortScore: 84,
    statusText: '环境舒适，宠物状态稳定',
    infraredDetected: false,
    activityLevel: '中等活动',
    timestamp: Date.now(),
    source: 'mock'
  };
  private static lastWarningAt: number = 0;
  private static lastExtremeActionAt: number = 0;
  // 开发者覆盖：非 null 时使用该值替代真实/模拟值
  private static devTemperature: number | null = null;
  private static devHumidity: number | null = null;
  // 过热/过湿反应模式：auto 超阈值自动触发；manual 仅采集不自动触发，需手动点击触发按钮
  private static extremeReactionMode: 'auto' | 'manual' = 'auto';
  // 兼容旧版 img_server：没有触摸事件时间戳时，仍使用 OFF→ON 边沿检测。
  private static lastTtp223: string = 'OFF';
  // 新版 img_server 会锁存每次触摸的发生时间，避免短促 ON 脉冲被轮询漏掉。
  private static lastTouchEventTimestamp: number = 0;

  static sample(): EnvironmentSnapshot {
    // 开发者覆盖激活时，保持固定值不添加随机波动，便于测试过热/过湿
    if (PetSensorService.devTemperature !== null || PetSensorService.devHumidity !== null) {
      const devT: number = PetSensorService.devTemperature ?? PetSensorService.latest.temperature;
      const devH: number = PetSensorService.devHumidity ?? PetSensorService.latest.humidity;
      PetSensorService.applyReading(devT, devH, 'dev');
      return PetSensorService.latest;
    }

    const nextTemperature: number = PetSensorService.latest.temperature + PetSensorService.rangeFloat(-1.2, 1.2);
    const nextHumidity: number = PetSensorService.latest.humidity + PetSensorService.rangeInt(-3, 3);
    const nextLight: number = PetSensorService.latest.light + PetSensorService.rangeInt(-120, 120);

    const temperature: number = Math.max(8, Math.min(42, Number(nextTemperature.toFixed(1))));
    const humidity: number = Math.max(20, Math.min(95, nextHumidity));
    const light: number = Math.max(20, Math.min(1500, nextLight));
    const comfortScore: number = PetSensorService.computeComfortScore(temperature, humidity);

    const infraredDetected: boolean = Math.random() > 0.45;
    const activityLevel: string = PetSensorService.resolveActivityText(light, infraredDetected);
    const statusText: string = PetSensorService.resolveStatusText(temperature, humidity, comfortScore);

    PetSensorService.latest = {
      temperature,
      humidity,
      light,
      comfortScore,
      statusText,
      infraredDetected,
      activityLevel,
      timestamp: Date.now(),
      source: PetSensorService.latest.source
    };

    return PetSensorService.latest;
  }

  static getLatest(): EnvironmentSnapshot {
    return PetSensorService.latest;
  }

  /**
   * 从 PC 端 img_server.py 的 /env HTTP 端点拉取真实温湿度。
   * 失败时回退到上一次快照。
   */
  static async fetchFromDevice(): Promise<EnvFetchResult> {
    const httpInstance: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpInstance.request(CommonConstants.ENV_ENDPOINT, {
        method: http.RequestMethod.GET,
        connectTimeout: 3000,
        readTimeout: 3000,
        expectDataType: http.HttpDataType.STRING
      });
      const body: string = (response.result as string) ?? '';
      if (body.length === 0) {
        return { snapshot: PetSensorService.latest, message: '环境服务返回空数据，使用上次数值' };
      }
      const parsed: EnvDevicePayload = PetSensorService.parseEnvJson(body);
      if (Number.isNaN(parsed.temperature) || Number.isNaN(parsed.humidity)) {
        return { snapshot: PetSensorService.latest, message: '环境数据解析失败，使用上次数值' };
      }
      PetSensorService.applyDeviceReading(parsed);
      return { snapshot: PetSensorService.latest, message: '已读取真实环境数据' };
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      console.warn(`${TAG} fetchFromDevice failed: ${err.code} ${err.message}`);
      return { snapshot: PetSensorService.latest, message: '环境服务连接失败，使用上次数值' };
    } finally {
      httpInstance.destroy();
    }
  }

  /**
   * 仅轮询 TTP223 触摸传感器状态，检测 OFF→ON 边沿（按下瞬间）。
   * 不更新温湿度，避免影响过热/过湿判断与展示数值。
   * 返回 true 表示本次轮询检测到一次新的触摸，调用方应触发摸头交互。
   */
  static async fetchTtp223Touch(): Promise<boolean> {
    const httpInstance: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpInstance.request(CommonConstants.ENV_ENDPOINT, {
        method: http.RequestMethod.GET,
        connectTimeout: 1500,
        readTimeout: 1500,
        expectDataType: http.HttpDataType.STRING
      });
      const body: string = (response.result as string) ?? '';
      if (body.length === 0) {
        return false;
      }
      const parsed: EnvDevicePayload = PetSensorService.parseEnvJson(body);
      if (parsed.touchEventTimestamp > 0) {
        const isNewEvent: boolean =
          parsed.touchEventTimestamp > PetSensorService.lastTouchEventTimestamp;
        PetSensorService.lastTouchEventTimestamp =
          Math.max(PetSensorService.lastTouchEventTimestamp, parsed.touchEventTimestamp);
        return isNewEvent && parsed.touchEventAgeMs >= 0 && parsed.touchEventAgeMs <= 5000;
      }
      const current: string = parsed.ttp223.toUpperCase() === 'ON' ? 'ON' : 'OFF';
      const touched: boolean = current === 'ON' && PetSensorService.lastTtp223 === 'OFF';
      PetSensorService.lastTtp223 = current;
      return touched;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      console.warn(`${TAG} fetchTtp223Touch failed: ${err.code} ${err.message}`);
      return false;
    } finally {
      httpInstance.destroy();
    }
  }

  /**
   * 开发者覆盖：传入非 null 值后，后续 sample/fetch 都使用该值。
   * 传 null 清除覆盖。
   */
  static setDevOverride(temperature: number | null, humidity: number | null): void {
    PetSensorService.devTemperature = temperature;
    PetSensorService.devHumidity = humidity;
    if (temperature !== null || humidity !== null) {
      const t: number = temperature ?? PetSensorService.latest.temperature;
      const h: number = humidity ?? PetSensorService.latest.humidity;
      PetSensorService.applyReading(t, h, 'dev');
    }
  }

  static clearDevOverride(): void {
    PetSensorService.devTemperature = null;
    PetSensorService.devHumidity = null;
    // 重置为正常环境值，避免残留的过高值继续触发过热/过湿
    PetSensorService.applyReading(25, 55, 'dev');
  }

  static isDevOverridden(): boolean {
    return PetSensorService.devTemperature !== null || PetSensorService.devHumidity !== null;
  }

  static setExtremeReactionMode(mode: 'auto' | 'manual'): void {
    PetSensorService.extremeReactionMode = mode;
  }

  static getExtremeReactionMode(): 'auto' | 'manual' {
    return PetSensorService.extremeReactionMode;
  }

  /**
   * 兼容旧接口：true 表示自动触发模式。
   */
  static isExtremeReactionEnabled(): boolean {
    return PetSensorService.extremeReactionMode === 'auto';
  }

  static isManualExtremeReaction(): boolean {
    return PetSensorService.extremeReactionMode === 'manual';
  }

  static applyEnvironmentImpact(pet: PetModel, snapshot: EnvironmentSnapshot): string {
    const now: number = Date.now();

    // 手动模式只采集与展示数值。手动动作的完整播放及回待机由 PetSprite 统一调度，
    // 环境轮询不得在中途改写动作，否则过热/过湿素材会被待机素材抢占。
    if (PetSensorService.extremeReactionMode === 'manual') {
      PetLifecycleService.updateEmotionAndStage(pet);
      return '手动模式：超阈值不自动触发，请点击触发按钮';
    }

    // 优先：温度过高 -> 触发过热动作
    if (snapshot.temperature >= CommonConstants.TEMP_TOO_HIGH) {
      PetSensorService.triggerExtremeAction(pet, 'hot');
      pet.attributes.mood = Math.max(0, pet.attributes.mood - 5);
      pet.attributes.health = Math.max(0, pet.attributes.health - 3);
      PetSensorService.recordWarning(pet, '温度过高，触发过热预警', now, snapshot.comfortScore);
      PetLifecycleService.updateEmotionAndStage(pet);
      return '温度过高，宠物过热';
    }

    // 湿度过高 -> 触发过湿动作
    if (snapshot.humidity >= CommonConstants.HUMIDITY_TOO_HIGH) {
      PetSensorService.triggerExtremeAction(pet, 'wet');
      pet.attributes.mood = Math.max(0, pet.attributes.mood - 4);
      pet.attributes.health = Math.max(0, pet.attributes.health - 2);
      PetSensorService.recordWarning(pet, '湿度过高，触发过湿预警', now, snapshot.comfortScore);
      PetLifecycleService.updateEmotionAndStage(pet);
      return '湿度过高，宠物过湿';
    }

    // 环境恢复正常时，若宠物仍处于过热/过湿状态，恢复到待机
    if (pet.currentAction === 'hot' || pet.currentAction === 'wet') {
      pet.currentAction = 'idle';
      pet.actionVersion += 1;
      pet.currentSpeech = '';
    }

    if (snapshot.comfortScore >= 80) {
      pet.attributes.mood = Math.min(100, pet.attributes.mood + 4);
      PetLifecycleService.updateEmotionAndStage(pet);
      return '环境很舒服，心情自然恢复';
    }

    if (snapshot.temperature < 10) {
      pet.attributes.mood = Math.max(0, pet.attributes.mood - 5);
      pet.attributes.health = Math.max(0, pet.attributes.health - 3);
      PetSensorService.recordWarning(pet, '温度异常，触发健康预警', now, snapshot.comfortScore);
      PetLifecycleService.updateEmotionAndStage(pet);
      return '温度异常，触发健康预警';
    }

    if (snapshot.humidity < 30) {
      pet.attributes.mood = Math.max(0, pet.attributes.mood - 3);
      pet.attributes.health = Math.max(0, pet.attributes.health - 2);
      PetSensorService.recordWarning(pet, '湿度异常，宠物出现轻微不适', now, snapshot.comfortScore);
      PetLifecycleService.updateEmotionAndStage(pet);
      return '湿度异常，宠物出现轻微不适';
    }

    if (snapshot.light < 100) {
      pet.attributes.energy = Math.min(100, pet.attributes.energy + 2);
      PetLifecycleService.updateEmotionAndStage(pet);
      return '环境光线偏暗，宠物更想休息';
    }

    PetLifecycleService.updateEmotionAndStage(pet);
    return '环境一般，状态维持稳定';
  }

  /**
   * 判断当前快照是否处于过热/过湿状态
   */
  static resolveExtremeAction(snapshot: EnvironmentSnapshot): 'hot' | 'wet' | null {
    if (snapshot.temperature >= CommonConstants.TEMP_TOO_HIGH) {
      return 'hot';
    }
    if (snapshot.humidity >= CommonConstants.HUMIDITY_TOO_HIGH) {
      return 'wet';
    }
    return null;
  }

  /**
   * 真实舒适度计算：基于温度、湿度偏离最佳区间的程度
   * 最佳：温度 22-26°C，湿度 45-65%
   */
  static computeComfortScore(temperature: number, humidity: number): number {
    // 温度偏差：以 24°C 为中心
    const tempDelta: number = Math.abs(temperature - 24);
    let tempScore: number = 100 - tempDelta * 3.2;
    if (temperature >= CommonConstants.TEMP_TOO_HIGH) {
      tempScore -= (temperature - CommonConstants.TEMP_TOO_HIGH) * 4;
    }
    if (temperature < 10) {
      tempScore -= (10 - temperature) * 3;
    }

    // 湿度偏差：以 55% 为中心
    const humDelta: number = Math.abs(humidity - 55);
    let humScore: number = 100 - humDelta * 0.6;
    if (humidity >= CommonConstants.HUMIDITY_TOO_HIGH) {
      humScore -= (humidity - CommonConstants.HUMIDITY_TOO_HIGH) * 2;
    }
    if (humidity < 30) {
      humScore -= (30 - humidity) * 1.5;
    }

    const score: number = Math.round(tempScore * 0.6 + humScore * 0.4);
    return Math.max(0, Math.min(100, score));
  }

  private static triggerExtremeAction(pet: PetModel, action: 'hot' | 'wet'): void {
    const now: number = Date.now();
    if (now - PetSensorService.lastExtremeActionAt < PetSensorService.EXTREME_ACTION_COOLDOWN_MS) {
      if (pet.currentAction !== action) {
        pet.currentAction = action;
        pet.actionVersion += 1;
      }
      return;
    }
    PetSensorService.lastExtremeActionAt = now;
    pet.currentAction = action;
    pet.actionVersion += 1;
    pet.currentSpeech = action === 'hot' ? '主人，我有点热，\n快热死我了。' : '主人，周围怎么感觉湿湿的，\n我想洗个澡。';
    PetLifecycleService.addMemory(pet, '情感记忆',
      action === 'hot' ? '环境过热，宠物感到不适' : '环境过湿，宠物感到不适', now);
  }

  /**
   * 手动触发过热/过湿反应：MP3 一遍 + 图片两遍 + 介绍 + 回待机。
   * 环境轮询不会中途打断，新的显式交互仍可覆盖当前动作。
   * 与自动触发共用同一份属性与记忆写入，但不计入自动触发的冷却时间。
   */
  static triggerManualReaction(pet: PetModel, action: 'hot' | 'wet'): void {
    const now: number = Date.now();
    const snapshot: EnvironmentSnapshot = PetSensorService.latest;
    pet.currentAction = action;
    pet.actionVersion += 1;
    pet.currentSpeech = action === 'hot' ? '主人，我有点热，\n快热死我了。' : '主人，周围怎么感觉湿湿的，\n我想洗个澡。';
    PetLifecycleService.addMemory(pet, '情感记忆',
      action === 'hot' ? '环境过热，宠物感到不适' : '环境过湿，宠物感到不适', now);

    if (action === 'hot') {
      pet.attributes.mood = Math.max(0, pet.attributes.mood - 5);
      pet.attributes.health = Math.max(0, pet.attributes.health - 3);
      PetSensorService.recordWarning(pet, '温度过高，触发过热预警', now, snapshot.comfortScore);
    } else {
      pet.attributes.mood = Math.max(0, pet.attributes.mood - 4);
      pet.attributes.health = Math.max(0, pet.attributes.health - 2);
      PetSensorService.recordWarning(pet, '湿度过高，触发过湿预警', now, snapshot.comfortScore);
    }
    PetLifecycleService.updateEmotionAndStage(pet);
  }

  private static applyDeviceReading(payload: EnvDevicePayload): void {
    const temperature: number = Math.max(0, Math.min(60, Number(payload.temperature.toFixed(1))));
    const humidity: number = Math.max(0, Math.min(100, Number(payload.humidity.toFixed(1))));
    PetSensorService.applyReading(temperature, humidity, 'device', payload.raw, payload.timestamp);
  }

  private static applyReading(temperature: number, humidity: number, source: 'device' | 'dev',
    raw?: string, timestamp?: number): void {
    const comfortScore: number = PetSensorService.computeComfortScore(temperature, humidity);
    const infraredDetected: boolean = raw ? raw.includes('TTP223 ON') : PetSensorService.latest.infraredDetected;
    const light: number = PetSensorService.latest.light;
    const activityLevel: string = PetSensorService.resolveActivityText(light, infraredDetected);
    const statusText: string = PetSensorService.resolveStatusText(temperature, humidity, comfortScore);

    PetSensorService.latest = {
      temperature,
      humidity,
      light,
      comfortScore,
      statusText,
      infraredDetected,
      activityLevel,
      timestamp: timestamp && timestamp > 0 ? timestamp : Date.now(),
      source
    };
  }

  private static parseEnvJson(body: string): EnvDevicePayload {
    const obj: EnvJsonShape = JSON.parse(body) as EnvJsonShape;
    return {
      temperature: Number(obj.temperature),
      humidity: Number(obj.humidity),
      ttp223: typeof obj.ttp223 === 'string' ? obj.ttp223 : 'OFF',
      raw: typeof obj.raw === 'string' ? obj.raw : '',
      timestamp: typeof obj.timestamp === 'number' ? obj.timestamp : 0,
      touchEventTimestamp: typeof obj.touchEventTimestamp === 'number' ? obj.touchEventTimestamp : 0,
      touchEventAgeMs: typeof obj.touchEventAgeMs === 'number' ? obj.touchEventAgeMs : -1
    };
  }

  private static recordWarning(pet: PetModel, message: string, now: number, comfortScore: number): void {
    if (now - PetSensorService.lastWarningAt < PetSensorService.WARNING_COOLDOWN_MS) {
      return;
    }

    PetSensorService.lastWarningAt = now;
    PetLifecycleService.addMemory(pet, '长期记忆', `环境预警：${message}`, now);
    PetLifecycleService.unlockAchievement(pet, 'weather_guardian', '患难与共', '经历一次环境异常预警并照顾宠物');

    if (comfortScore <= 45) {
      PetLifecycleService.unlockAchievement(pet, 'extreme_weather_guardian', '守护到底', '在低舒适度环境下持续守护宠物');
    }
  }

  private static resolveStatusText(temperature: number, humidity: number, comfortScore: number): string {
    if (temperature >= CommonConstants.TEMP_TOO_HIGH) {
      return '温度过高，已触发过热预警';
    }
    if (humidity >= CommonConstants.HUMIDITY_TOO_HIGH) {
      return '湿度过高，已触发过湿预警';
    }
    if (comfortScore >= 80) {
      return '环境舒适，宠物状态稳定';
    }
    if (temperature > 35) {
      return '环境偏热，建议降温';
    }
    if (temperature < 10) {
      return '环境偏冷，建议保暖';
    }
    if (humidity > 70) {
      return '环境偏潮，建议通风';
    }
    if (humidity < 30) {
      return '环境偏干，建议补湿';
    }
    return '环境一般，可继续观察';
  }

  private static resolveActivityText(light: number, infraredDetected: boolean): string {
    if (!infraredDetected) {
      return '低活动';
    }
    if (light > 900) {
      return '高活动';
    }
    if (light > 400) {
      return '中等活动';
    }
    return '轻活动';
  }

  private static rangeFloat(min: number, max: number): number {
    return Math.random() * (max - min) + min;
  }

  private static rangeInt(min: number, max: number): number {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }
}

interface EnvDevicePayload {
  temperature: number;
  humidity: number;
  ttp223: string;
  raw: string;
  timestamp: number;
  touchEventTimestamp: number;
  touchEventAgeMs: number;
}

interface EnvJsonShape {
  temperature: number;
  humidity: number;
  ttp223?: string;
  raw?: string;
  timestamp?: number;
  touchEventTimestamp?: number;
  touchEventAgeMs?: number;
}
