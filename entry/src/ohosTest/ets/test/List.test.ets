import { describe } from '@ohos/hypium';
import smokeTest from './Smoke.test.ets';
import petLlmClientTest from './PetLlmClient.test.ets';
import petAiContextTest from './PetAiContext.test.ets';
import petAiFallbackTest from './PetAiFallback.test.ets';
import petPersistenceTest from './PetPersistence.test.ets';

/**
 * ohosTest 测试入口：所有测试套件在此统一注册
 */
export default function testsuite(): void {
  smokeTest();
  petLlmClientTest();
  petAiContextTest();
  petAiFallbackTest();
  petPersistenceTest();
}
