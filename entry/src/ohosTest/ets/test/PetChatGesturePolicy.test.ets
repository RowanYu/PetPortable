import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { PetChatGesturePolicy } from '../../../main/ets/common/services/PetChatGesturePolicy';

/**
 * PetChatGesturePolicy 纯函数测试：上滑阈值判定与连续模式错误决策
 */
export default function petChatGesturePolicyTest(): void {
  describe('PetChatGesturePolicy', () => {
    it('isSwipeUpEnter_上滑超过阈值为真', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      expect(PetChatGesturePolicy.isSwipeUpEnter(-130)).assertTrue();
    });
    it('isSwipeUpEnter_恰好达到阈值为真', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      expect(PetChatGesturePolicy.isSwipeUpEnter(-PetChatGesturePolicy.SWIPE_UP_ENTER_THRESHOLD_VP)).assertTrue();
    });
    it('isSwipeUpEnter_未达阈值为假', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      expect(PetChatGesturePolicy.isSwipeUpEnter(-60)).assertFalse();
    });
    it('isSwipeUpEnter_下滑为假', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      expect(PetChatGesturePolicy.isSwipeUpEnter(50)).assertFalse();
    });
    it('resolveAfterError_静默超时且连续模式返回restart', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      expect(PetChatGesturePolicy.resolveAfterError('没有听到说话，请再试一次', true)).assertEqual('restart');
    });
    it('resolveAfterError_其他错误且连续模式返回stop', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      expect(PetChatGesturePolicy.resolveAfterError('语音识别出错，请再试一次', true)).assertEqual('stop');
    });
    it('resolveAfterError_非连续模式返回ignore', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      expect(PetChatGesturePolicy.resolveAfterError('没有听到说话，请再试一次', false)).assertEqual('ignore');
    });
  });
}
