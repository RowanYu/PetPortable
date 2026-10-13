import { router } from '@kit.ArkUI';
import { CommonConstants } from '../common/constants/CommonConstants';
// 定义位置接口
interface MyPositionOptions {
  top?: Dimension;
  bottom?: Dimension;
  left?: Dimension;
  right?: Dimension;
}

@Entry
@Component
struct WelcomePage {
  @State backBtnScale: number = 1;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {

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


      // 1. 背景色
      Rect().width('100%').height('100%').fill('#012A3E')

      // 2. 装饰性背景圆
      this.BackgroundDecorations()

      // 3. 宠物大图（强制宽度 100%，按设计图比例计算高度，允许顶部溢出，底部绝对贴合）
      Image($r('app.media.welcome_puppy'))
        .width('100%')
        .aspectRatio(700 / 1575)
        .objectFit(ImageFit.Cover)
        .position({ bottom: 0 })

      // 4. 装饰小点与浮动标签
      this.DecorativePoints()
      this.FloatingTag('喂养我', { top: '35%', right: '10%' }, -6)
      this.FloatingTag('陪我玩', { top: '48%', left: '5%' }, 5)
      this.FloatingTag('照顾我', { bottom: '30%', left: '10%' }, -6)

      // 5. 顶部文本与底部按钮
      Column() {
        // 顶部 Logo 和 标题
        Row({ space: 8 }) {
          Image($r('app.media.ic_logo_small'))
            .width(38)
            .height(20)
            .objectFit(ImageFit.Contain)
          
          Text('虚拟宠物')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .fontFamily('ADLaM Display')
        }
        .margin({ top: 60, bottom: 40 })

        // 主标语
        Text() {
          Span('与您的')
          Span('新虚拟伙伴')
            .fontWeight(FontWeight.Bolder)
          Span('\n一起建立健康习惯！')
        }
        .fontSize(24)
        .fontColor('#DEE1FE')
        .textAlign(TextAlign.Center)
        .lineHeight(36)
        .letterSpacing(0.84)
        .margin({ left: 24, right: 24 })

        Blank()

        // 底部按钮区域
        Row() {
          Blank()
          
          // 下一步按钮 (点击进入注册/登录)
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_next_arrow'))
              .width(24)
              .height(24)
          }
          .width(62)
          .height(62)
          .backgroundColor('#F3F3F3')
          .shadow({ radius: 20, color: '#20000000', offsetX: 0, offsetY: 10 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/RegisterPage' })
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: CommonConstants.CLICK_SCALE })
        }
        .width('100%')
        // 根据 Figma 截图，按钮紧贴屏幕右下角，并且没有过高的留白
        .padding({ right: 20, bottom: 20 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  // 背景装饰组件
  @Builder
  BackgroundDecorations() {
    Stack() {
      Circle()
        .width(600)
        .height(600)
        .fill('#BCF9FF')
        .opacity(0.05)
        .position({ x: -200, y: -100 })
      
      Circle()
        .width(380)
        .height(380)
        .fill('#BCF9FF')
        .opacity(0.05)
        .position({ x: 200, y: 500 })
    }
    .width('100%')
    .height('100%')
  }

  // 浮动标签构建器
  @Builder
  FloatingTag(text: string, pos: MyPositionOptions, rotate: number) {
    Text(text)
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      // ArkTS 的透明度颜色格式为 #AARRGGBB，40%透明的白应为 #66FFFFFF
      .backgroundColor('#66FFFFFF')
      .border({ width: 2, color: '#1FFFFFFF' })
      .borderRadius(10)
      .rotate({ angle: rotate })
      .position(pos)
  }

  // 装饰性小点
  @Builder
  DecorativePoints() {
    Stack() {
      Circle({ width: 12, height: 12 }).fill(Color.White).position({ x: '20%', y: '40%' })
      Circle({ width: 20, height: 20 }).fill(Color.White).position({ x: '85%', y: '65%' })
      Circle({ width: 7, height: 7 }).stroke('#81ECFF').strokeWidth(2).position({ x: '80%', y: '50%' })
      Circle({ width: 7, height: 7 }).stroke('#81ECFF').strokeWidth(2).position({ x: '15%', y: '75%' })
    }
    .width('100%')
    .height('100%')
  }
}
