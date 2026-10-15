/** 连续聊天决策动作：restart 重启聆听；stop 终止连续模式；ignore 忽略（非连续模式） */
export type ContinuousTurnAction = 'restart' | 'stop' | 'ignore';

/**
 * 语音聊天手势与连续模式判定纯函数集：无状态、无依赖，便于单测。
 * 上滑进入连续聊天的位移阈值为 120vp（PanGesture offsetY 向上为负）。
 */
export class PetChatGesturePolicy {
  /** 上滑进入连续聊天的位移阈值（vp），offsetY <= -120 视为触发 */
  static readonly SWIPE_UP_ENTER_THRESHOLD_VP: number = 120;

  /** 判定上滑位移是否达到进入连续聊天的阈值 */
  static isSwipeUpEnter(swipeOffsetY: number): boolean {
    return swipeOffsetY <= -PetChatGesturePolicy.SWIPE_UP_ENTER_THRESHOLD_VP;
  }

  /**
   * 识别错误后的连续模式决策。
   * once 静默超时文案（PetSpeechRecognizerService）含「没有听到说话」→ 连续模式下重启聆听；
   * 其他错误在连续模式下终止；非连续模式一律忽略。
   */
  static resolveAfterError(errorText: string, continuousMode: boolean): ContinuousTurnAction {
    if (!continuousMode) {
      return 'ignore';
    }
    if (errorText.includes('没有听到说话')) {
      return 'restart';
    }
    return 'stop';
  }
}
