import { PetActionType, PetModel } from '../models/PetModel';

export interface PetMotionProfile {
  action: PetActionType;
  floatOffsetY: number;
  scaleX: number;
  scaleY: number;
  rotateY: number;
  tiltZ: number;
  auraScale: number;
  auraOpacity: number;
  shadowScaleX: number;
  shadowScaleY: number;
  bodyOpacity: number;
  effectOpacity: number;
  effectOffset: number;
  animationDuration: number;
}

interface PetActionDescriptor {
  action: PetActionType;
  speech: string;
  autoResetDelay: number;
}

export class PetActionService {
  private static readonly IDLE_PROFILE: PetMotionProfile = {
    action: 'idle',
    floatOffsetY: -10,
    scaleX: 1.01,
    scaleY: 1.01,
    rotateY: 0,
    tiltZ: -1,
    auraScale: 1.04,
    auraOpacity: 0.18,
    shadowScaleX: 0.98,
    shadowScaleY: 0.92,
    bodyOpacity: 1,
    effectOpacity: 0.12,
    effectOffset: -8,
    animationDuration: 1800
  };

  static triggerAction(pet: PetModel, action: PetActionType): void {
    const descriptor: PetActionDescriptor = PetActionService.resolveActionDescriptor(action);
    pet.actionVersion += 1;
    const currentVersion: number = pet.actionVersion;
    pet.currentAction = descriptor.action;
    pet.currentSpeech = descriptor.speech;
    PetActionService.updateAttributes(pet, action);

    if (descriptor.autoResetDelay > 0) {
      setTimeout(() => {
        if (pet.actionVersion === currentVersion) {
          PetActionService.resetToIdle(pet);
        }
      }, descriptor.autoResetDelay);
    }
  }

  static resetToIdle(pet: PetModel): void {
    pet.currentAction = 'idle';
    pet.currentSpeech = '';
  }

  static resolveMotion(action: PetActionType): PetMotionProfile {
    switch (action) {
      case 'interact':
        return {
          action,
          floatOffsetY: -14,
          scaleX: 1.02,
          scaleY: 1.03,
          rotateY: 4,
          tiltZ: 2,
          auraScale: 1.08,
          auraOpacity: 0.24,
          shadowScaleX: 1.02,
          shadowScaleY: 0.9,
          bodyOpacity: 1,
          effectOpacity: 0.22,
          effectOffset: -18,
          animationDuration: 780
        };
      case 'play':
        return {
          action,
          floatOffsetY: -18,
          scaleX: 1.03,
          scaleY: 1.03,
          rotateY: 5,
          tiltZ: 3,
          auraScale: 1.12,
          auraOpacity: 0.28,
          shadowScaleX: 1.06,
          shadowScaleY: 0.88,
          bodyOpacity: 1,
          effectOpacity: 0.26,
          effectOffset: -20,
          animationDuration: 720
        };
      case 'eat':
        return {
          action,
          floatOffsetY: -8,
          scaleX: 1.02,
          scaleY: 1.02,
          rotateY: -3,
          tiltZ: -2,
          auraScale: 1.06,
          auraOpacity: 0.22,
          shadowScaleX: 1.04,
          shadowScaleY: 0.9,
          bodyOpacity: 1,
          effectOpacity: 0.22,
          effectOffset: -14,
          animationDuration: 860
        };
      case 'chat':
        return {
          action,
          floatOffsetY: -12,
          scaleX: 1.01,
          scaleY: 1.01,
          rotateY: 8,
          tiltZ: -3,
          auraScale: 1.1,
          auraOpacity: 0.24,
          shadowScaleX: 1,
          shadowScaleY: 0.9,
          bodyOpacity: 1,
          effectOpacity: 0.24,
          effectOffset: -22,
          animationDuration: 980
        };
      case 'sleep':
        return {
          action,
          floatOffsetY: -6,
          scaleX: 0.99,
          scaleY: 0.99,
          rotateY: -2,
          tiltZ: -3,
          auraScale: 1,
          auraOpacity: 0.14,
          shadowScaleX: 0.94,
          shadowScaleY: 0.86,
          bodyOpacity: 0.92,
          effectOpacity: 0.1,
          effectOffset: -10,
          animationDuration: 2200
        };
      case 'train':
        return {
          action,
          floatOffsetY: -12,
          scaleX: 1.01,
          scaleY: 1.02,
          rotateY: 2,
          tiltZ: 0,
          auraScale: 1.06,
          auraOpacity: 0.2,
          shadowScaleX: 1,
          shadowScaleY: 0.9,
          bodyOpacity: 1,
          effectOpacity: 0.18,
          effectOffset: -14,
          animationDuration: 860
        };
      case 'bath':
        return {
          action,
          floatOffsetY: -9,
          scaleX: 1.00,
          scaleY: 1.00,
          rotateY: -2,
          tiltZ: -1,
          auraScale: 1.04,
          auraOpacity: 0.2,
          shadowScaleX: 0.98,
          shadowScaleY: 0.9,
          bodyOpacity: 0.98,
          effectOpacity: 0.16,
          effectOffset: -12,
          animationDuration: 1020
        };
      case 'idle':
      default:
        return PetActionService.IDLE_PROFILE;
    }
  }

  private static resolveActionDescriptor(action: PetActionType): PetActionDescriptor {
    switch (action) {
      case 'interact':
        return { action: 'interact', speech: '', autoResetDelay: 1800 };
      case 'play':
        return { action: 'play', speech: '', autoResetDelay: 2800 };
      case 'eat':
        return { action: 'eat', speech: '', autoResetDelay: 3600 };
      case 'chat':
        return { action: 'chat', speech: '', autoResetDelay: 2600 };
      case 'sleep':
        return { action: 'sleep', speech: '', autoResetDelay: 3200 };
      case 'train':
        return { action: 'train', speech: '', autoResetDelay: 2600 };
      case 'bath':
        return { action: 'bath', speech: '', autoResetDelay: 2800 };
      case 'idle':
      default:
        return { action: 'idle', speech: '', autoResetDelay: 0 };
    }
  }

  private static updateAttributes(pet: PetModel, action: PetActionType): void {
    switch (action) {
      case 'interact':
        pet.attributes.mood = Math.min(100, pet.attributes.mood + 6);
        pet.attributes.intimacy = Math.min(100, pet.attributes.intimacy + 4);
        break;
      case 'play':
        pet.attributes.mood = Math.min(100, pet.attributes.mood + 8);
        pet.attributes.energy = Math.max(0, pet.attributes.energy - 6);
        pet.attributes.intimacy = Math.min(100, pet.attributes.intimacy + 4);
        break;
      case 'eat':
        pet.attributes.health = Math.min(100, pet.attributes.health + 10);
        pet.attributes.energy = Math.min(100, pet.attributes.energy + 4);
        pet.attributes.mood = Math.min(100, pet.attributes.mood + 3);
        break;
      case 'chat':
        pet.attributes.intimacy = Math.min(100, pet.attributes.intimacy + 6);
        pet.attributes.mood = Math.min(100, pet.attributes.mood + 5);
        break;
      case 'sleep':
        pet.attributes.energy = Math.min(100, pet.attributes.energy + 10);
        pet.attributes.mood = Math.min(100, pet.attributes.mood + 2);
        break;
      case 'train':
        pet.attributes.obedience = Math.min(100, pet.attributes.obedience + 5);
        pet.attributes.toxicity = Math.max(0, Math.min(100, pet.attributes.toxicity + (Math.random() > 0.5 ? 2 : -2)));
        pet.attributes.energy = Math.max(0, pet.attributes.energy - 4);
        break;
      case 'bath':
        pet.attributes.health = Math.min(100, pet.attributes.health + 8);
        pet.attributes.mood = Math.min(100, pet.attributes.mood + 2);
        break;
      case 'idle':
      default:
        break;
    }
  }
}
