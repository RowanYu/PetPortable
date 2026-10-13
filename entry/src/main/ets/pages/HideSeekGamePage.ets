import { router } from '@kit.ArkUI';

@Entry
@Component
struct HideSeekGamePage {
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
        Text('躲猫猫 - 游戏中')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .padding(16)
      .justifyContent(FlexAlign.Center)

      Column() {
        Text('游戏中...')
          .fontSize(16)
          
        Button('完成游戏')
          .margin({ top: 20 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/ThankYouPage' })
          })
      }
      .flexGrow(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
