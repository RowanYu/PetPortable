import { PetModel } from '../models/PetModel';

export interface PetStageVisual {
  image: Resource;
  width: number;
  height: number;
  shadowWidth: number;
  shadowOpacity: number;
  stageHeight: number;
}

export class PetStageAssetResolver {
  static resolve(pet: PetModel): PetStageVisual {
    const modelPath: string = pet.modelPath.toLowerCase();

    if (modelPath.includes('coyote')) {
      return {
        image: $r('app.media.pet_dog_1'),
        width: 292,
        height: 236,
        shadowWidth: 180,
        shadowOpacity: 0.18,
        stageHeight: 336
      };
    }

    if (modelPath.includes('burmese_bull')) {
      return {
        image: $r('app.media.pet_duck_full'),
        width: 252,
        height: 316,
        shadowWidth: 156,
        shadowOpacity: 0.2,
        stageHeight: 360
      };
    }

    if (modelPath.includes('duck_default')) {
      return {
        image: $r('app.media.pet_duck_full'),
        width: 252,
        height: 316,
        shadowWidth: 156,
        shadowOpacity: 0.2,
        stageHeight: 360
      };
    }

    if (modelPath.includes('fox_default')) {
      return {
        image: $r('app.media.fox_idle_01'),
        width: 252,
        height: 316,
        shadowWidth: 156,
        shadowOpacity: 0.2,
        stageHeight: 360
      };
    }

    if (modelPath.includes('golden_default')) {
      return {
        image: $r('app.media.golden_idle_01'),
        width: 252,
        height: 316,
        shadowWidth: 156,
        shadowOpacity: 0.2,
        stageHeight: 360
      };
    }

    if (modelPath.includes('cat_default')) {
      return {
        image: $r('app.media.cat_head'),
        width: 270,
        height: 328,
        shadowWidth: 160,
        shadowOpacity: 0.16,
        stageHeight: 380
      };
    }

    if (modelPath.includes('live2d_mao')) {
      return {
        image: $r('app.media.live2d_mao_idle_01'),
        width: 286,
        height: 344,
        shadowWidth: 148,
        shadowOpacity: 0.16,
        stageHeight: 392
      };
    }

    if (modelPath.startsWith('live2d_real:')) {
      // 真实 Live2D（Web 组件渲染）舞台尺寸沿用 live2d_mao，保持视觉一致
      // 实际渲染由 Web 组件加载的 PIXI 完成，此处仅决定外层容器尺寸与阴影
      return {
        image: $r('app.media.live2d_mao_idle_01'),
        width: 286,
        height: 344,
        shadowWidth: 148,
        shadowOpacity: 0.16,
        stageHeight: 392
      };
    }

    return {
      image: pet.image,
      width: 292,
      height: 236,
      shadowWidth: 184,
      shadowOpacity: 0.18,
      stageHeight: 336
    };
  }
}
