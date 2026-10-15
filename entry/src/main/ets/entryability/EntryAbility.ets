import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PetPersistenceService } from '../common/services/PetPersistenceService';
import { PetConversationService } from '../common/services/PetConversationService';
import { PetStore } from '../common/services/PetStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 启动恢复：宠物档案 + 当前宠物的多轮聊天记录
    try {
      const restored: boolean = await PetPersistenceService.restore(this.context);
      if (restored) {
        const pet = PetStore.getCurrent();
        await PetConversationService.restoreHistory(PetPersistenceService.resolvePetKey(pet), this.context);
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'Pet store restored.');
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Restore failed. Cause: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/WelcomePage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // 退后台即落盘，避免强杀丢数据
    void PetPersistenceService.persist(this.context);
  }
}