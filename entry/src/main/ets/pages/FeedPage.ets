import { router } from '@kit.ArkUI';
import { PetModel } from '../common/models/PetModel';
import { FeedOptions, InteractionResult, InteractionService } from '../common/services/InteractionService';

interface FoodItem {
  id: string;
  title: string;
  detail: string;
}

@Entry
@Component
struct FeedPage {
  @State backBtnScale: number = 1;
  @State quantity: number = 1;
  @State actionText: string = '给宠物选择一种食物吧';
  @StorageLink('currentPet') pet: PetModel = new PetModel('小橘', '宠物', $r('app.media.pet_duck_full'), 'duck_default');

  private readonly foods: FoodItem[] = [
    { id: 'cat_food', title: '营养猫粮', detail: '基础健康补给' },
    { id: 'fish', title: '小鱼干', detail: '高满足感加成' },
    { id: 'milk', title: '温牛奶', detail: '温和补充精力' }
  ];

  private async feed(food: FoodItem): Promise<void> {
    const options: FeedOptions = {
      foodId: food.id,
      quantity: this.quantity
    };
    const result: InteractionResult = await InteractionService.getInstance().feed(this.pet, options);
    this.actionText = result.bubbleText ?? '喂食完成';
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('sys.color.ohos_id_color_text_primary'))
          .scale({ x: this.backBtnScale, y: this.backBtnScale })
          .animation({ duration: 150 })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) this.backBtnScale = 0.9;
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.backBtnScale = 1;
          })
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .padding({ left: 16, top: 16 })
      .zIndex(20);

      Text('喂食中心')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 8 });

      Text(this.actionText)
        .fontSize(13)
        .fontColor('rgba(255,255,255,0.82)')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 6, bottom: 14 });

      Row({ space: 8 }) {
        Text('份量')
          .fontSize(13)
          .fontColor('#FFFFFF');

        Button('-')
          .width(34)
          .height(34)
          .backgroundColor('#31404D')
          .fontColor('#FFFFFF')
          .borderRadius(10)
          .onClick(() => {
            this.quantity = Math.max(1, this.quantity - 1);
          });

        Text(`${this.quantity}`)
          .fontSize(16)
          .fontColor('#FFFFFF')
          .width(28)
          .textAlign(TextAlign.Center);

        Button('+')
          .width(34)
          .height(34)
          .backgroundColor('#31404D')
          .fontColor('#FFFFFF')
          .borderRadius(10)
          .onClick(() => {
            this.quantity = Math.min(3, this.quantity + 1);
          });
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 12 });

      Column({ space: 12 }) {
        ForEach(this.foods, (food: FoodItem) => {
          Row() {
            Column({ space: 4 }) {
              Text(food.title)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF');
              Text(food.detail)
                .fontSize(12)
                .fontColor('rgba(255,255,255,0.7)');
            }
            .alignItems(HorizontalAlign.Start);

            Blank();

            Button('喂食')
              .width(72)
              .height(38)
              .backgroundColor('#0894BD')
              .fontColor('#FFFFFF')
              .fontSize(13)
              .borderRadius(12)
              .onClick(() => {
                void this.feed(food);
              })
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 });
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#2A3641')
          .borderRadius(16)
          .shadow({ radius: 6, color: '#12000000', offsetX: 0, offsetY: 4 });
        }, (food: FoodItem) => food.id);
      }
      .padding({ left: 16, right: 16 })
      .flexGrow(1)
      .justifyContent(FlexAlign.Start);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#081E2A');
  }
}
