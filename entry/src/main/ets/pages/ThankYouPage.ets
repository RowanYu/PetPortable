import { router } from '@kit.ArkUI';

@Entry
@Component
struct ThankYouPage {
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


      Column({ space: 24 }) {
        Image($r('sys.media.ohos_ic_public_ok'))
          .width(64).height(64)
          .fillColor($r('sys.color.ohos_id_color_emphasize'))

        Text('操作成功')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          
        Text('感谢您的使用')
          .fontSize(16)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))

        Button('返回主页')
          .width('80%')
          .height(50)
          .borderRadius(16)
          .onClick(() => {
            router.clear();
            router.replaceUrl({ url: 'pages/Index' })
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
