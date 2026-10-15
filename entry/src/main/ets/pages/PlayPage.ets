import { router } from '@kit.ArkUI';
import { InteractionResult, InteractionService, PlayOptions } from '../common/services/InteractionService';
import { PetModel } from '../common/models/PetModel';

interface ToyItem {
  id: string;
  name: string;
  detail: string;
}

@Entry
@Component
struct PlayPage {
  @State backBtnScale: number = 1;
  @State feedbackText: string = '选择玩具与宠物互动吧';
  @StorageLink('currentPet') pet: PetModel = new PetModel('小橘', '宠物', $r('app.media.pet_duck_full'), 'duck_default');

  private readonly toys: ToyItem[] = [
    { id: 'ball', name: '弹力球', detail: '短时高兴奋' },
    { id: 'yarn', name: '毛线球', detail: '轻松陪伴型' },
    { id: 'frisbee', name: '飞盘', detail: '高消耗高互动' }
  ];

  private async playWithToy(toy: ToyItem): Promise<void> {
    const options: PlayOptions = {
      toyId: toy.id,
      duration: toy.id === 'frisbee' ? 45_000 : 30_000
    };
    const result: InteractionResult = await InteractionService.getInstance().play(this.pet, options);
    this.feedbackText = result.bubbleText ?? '玩耍结束';
  }

  private async trainPet(commandId: string): Promise<void> {
    const result: InteractionResult = await InteractionService.getInstance().train(this.pet, commandId);
    this.feedbackText = result.bubbleText ?? '训练完成';
  }

  build() {
    Column() {

      // 返回按钮
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

      Text('随心玩耍')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 8 });

      Text(this.feedbackText)
        .fontSize(13)
        .fontColor('rgba(255,255,255,0.82)')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 6, bottom: 12 });

      Column({ space: 12 }) {
        ForEach(this.toys, (toy: ToyItem) => {
          Row() {
            Column({ space: 4 }) {
              Text(toy.name)
                .fontSize(16)
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Medium);
              Text(toy.detail)
                .fontSize(12)
                .fontColor('rgba(255,255,255,0.72)');
            }
            .alignItems(HorizontalAlign.Start);

            Blank();

            Button('开始')
              .width(72)
              .height(36)
              .backgroundColor('#0894BD')
              .fontColor('#FFFFFF')
              .fontSize(13)
              .borderRadius(12)
              .onClick(() => {
                void this.playWithToy(toy);
              })
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 });
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#2A3641')
          .borderRadius(16)
          .shadow({ radius: 6, color: '#12000000', offsetX: 0, offsetY: 4 });
        }, (toy: ToyItem) => toy.id);
      }
      .width('100%')
      .padding({ left: 16, right: 16 });

      Row({ space: 10 }) {
        Button('训练坐下')
          .layoutWeight(1)
          .height(42)
          .backgroundColor('#31404D')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .onClick(() => {
            void this.trainPet('sit');
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 });

        Button('训练握手')
          .layoutWeight(1)
          .height(42)
          .backgroundColor('#31404D')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .onClick(() => {
            void this.trainPet('shake_hand');
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 });
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10 });

      Column({ space: 20 }) {
        Button('躲猫猫小游戏')
          .width('80%')
          .height(50)
          .backgroundColor('#0894BD')
          .fontColor('#FFFFFF')
          .borderRadius(16)
          .onClick(() => {
            router.pushUrl({ url: 'pages/HideSeekPage' })
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
      }
      .flexGrow(1)
      .justifyContent(FlexAlign.End)
      .padding({ bottom: 20 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#081E2A');
  }
}
