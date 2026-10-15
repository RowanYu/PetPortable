import { router } from '@kit.ArkUI';
import { RewardRedeemContent } from '../common/components/RewardRedeemContent';
import { PetModel } from '../common/models/PetModel';

@Entry
@Component
struct RedeemPage {
  @StorageLink('currentPet') pet: PetModel = new PetModel('小黄鸭', '宠物', $r('app.media.pet_duck_full'), 'duck_default');

  build() {
    Column() {
      RewardRedeemContent({
        pet: this.pet,
        onBack: () => {
          router.back();
        }
      });
    }
    .width('100%')
    .height('100%')
  }
}
