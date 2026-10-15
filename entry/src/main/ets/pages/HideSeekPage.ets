import { router } from '@kit.ArkUI';

@Entry
@Component
struct HideSeekPage {
  @State backBtnScale: number = 1;

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
      .zIndex(20)


      Row() {
        Text('躲猫猫 - 准备')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .padding(16)
      .justifyContent(FlexAlign.Center)

      Column({ space: 24 }) {
        Text('准备好开始躲猫猫了吗？')
          .fontSize(16)
        Button('开始游戏')
          .width('80%')
          .height(50)
          .borderRadius(16)
          .onClick(() => {
            router.pushUrl({ url: 'pages/HideSeekGamePage' })
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
      }
      .flexGrow(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
