import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { PetModel, PetMemoryRecord, PetDreamRecord } from '../../../main/ets/common/models/PetModel';
import { PetStore } from '../../../main/ets/common/services/PetStore';
import {
  PetPersistenceService
} from '../../../main/ets/common/services/PetPersistenceService';

/**
 * PetPersistenceService：快照序列化与 Preferences 持久化测试
 */
export default function petPersistenceTest(): void {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();

  describe('PetPersistence', () => {
    it('快照往返保真', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const pet: PetModel = new PetModel('团子', '猫咪', undefined, 'cat_default');
      pet.attributes.intimacy = 66;
      const memory: PetMemoryRecord = new PetMemoryRecord();
      memory.type = '对话记忆';
      memory.content = '主人：我喜欢吃火锅';
      pet.memories.push(memory);
      const dream: PetDreamRecord = new PetDreamRecord();
      dream.title = '晴天散步记录';
      dream.content = '我们去了公园';
      pet.dreams.push(dream);

      const json: string = PetPersistenceService.toSnapshotJson([pet]);
      const restored: PetModel[] = PetPersistenceService.fromSnapshotJson(json);

      expect(restored.length).assertEqual(1);
      expect(restored[0].name).assertEqual('团子');
      expect(restored[0].type).assertEqual('猫咪');
      expect(restored[0].modelPath).assertEqual('cat_default');
      expect(restored[0].attributes.intimacy).assertEqual(66);
      expect(restored[0].memories.length).assertEqual(1);
      expect(restored[0].memories[0].content).assertEqual('主人：我喜欢吃火锅');
      expect(restored[0].dreams.length).assertEqual(1);
      expect(restored[0].dreams[0].title).assertEqual('晴天散步记录');
    });
    it('非法JSON解析为空数组不抛异常', TestType.FUNCTION | Size.SMALL_TEST | Level.LEVEL1, () => {
      const restored: PetModel[] = PetPersistenceService.fromSnapshotJson('垃圾字符串');
      expect(restored.length).assertEqual(0);
    });
    it('persist后restore恢复宠物列表与当前宠物', TestType.FUNCTION | Size.MEDIUM_TEST | Level.LEVEL1, async () => {
      const list: PetModel[] = PetStore.getList();
      if (list.length === 0) {
        PetStore.addPet(new PetModel('团子', '猫咪', undefined, 'cat_default'));
      }
      await PetPersistenceService.persist(context);
      const restored: boolean = await PetPersistenceService.restore(context);
      expect(restored).assertTrue();
      expect(PetStore.getList().length).assertEqual(list.length);
      expect(PetStore.getCurrent().name).assertEqual(list[PetStore.getCurrentIndex()].name);
    });
    it('聊天记录原样往返且无数据返回空串', TestType.FUNCTION | Size.MEDIUM_TEST | Level.LEVEL1, async () => {
      const empty: string = await PetPersistenceService.loadChat(context, 'empty_pet_key');
      expect(empty).assertEqual('');

      const messagesJson: string = '[{"id":"1","role":"主人","content":"你好","source":""}]';
      await PetPersistenceService.persistChat(context, 'pet_key_x', messagesJson);
      const loaded: string = await PetPersistenceService.loadChat(context, 'pet_key_x');
      expect(loaded).assertEqual(messagesJson);
    });
  });
}
