import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';

/**
 * 冒烟测试：验证 ohosTest 脚手架可用
 */
export default function smokeTest(): void {
  describe('SmokeTest', () => {
    it('基础断言可用', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL0, () => {
      expect(1 + 1).assertEqual(2);
    });
  });
}
