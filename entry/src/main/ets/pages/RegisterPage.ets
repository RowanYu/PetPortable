import { router } from '@kit.ArkUI';

@Entry
@Component
struct RegisterPage {
  @State currentStep: number = 0; // 0 for setup, 1 for account
  @State email: string = '';
  @State password: string = '';
  @State acceptedTerms: boolean = false;
  
  // 交互反馈：点击项缩放效果
  @State btnScaleSetup: number = 1;
  @State btnScaleLater: number = 1;
  @State btnScaleCreate: number = 1;
  @State backBtnScale: number = 1;

  build() {
    Column() {
      // 顶部返回按钮
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor('#ffffff')
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

      // 顶部图片区域
      Stack({ alignContent: Alignment.Bottom }) {
        Image($r('app.media.onboarding_pet'))
          .width(252)
          .height(304)
          .margin({ bottom: 32 })
        
        // 悬浮图标 (铅笔)
        Row() {
          Image($r('app.media.ic_pencil'))
            .width(36)
            .height(36)
        }
        .width(64)
        .height(64)
        .backgroundColor('#012a3e')
        .borderRadius(32)
        .border({ width: 2, color: '#1268cc' })
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: -32 }) // 悬浮在一半
        .zIndex(10)
      }
      .width('100%')
      .height(340)
      .margin({ top: 16 })
      
      // 底部卡片区域
      Column() {
        if (this.currentStep === 0) {
          this.SetupProfileView()
        } else {
          this.CreateAccountView()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#062137') // 采用深蓝色背景，区分层次
      .borderRadius({ topLeft: 26, topRight: 26 })
      .padding({ top: 48, left: 24, right: 24, bottom: 24 })
      .shadow({ radius: 20, color: 'rgba(12, 26, 75, 0.2)', offsetY: -4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#012a3e')
    .linearGradient({
      angle: 180,
      colors: [['rgba(16, 17, 19, 0)', 0.0], ['#101113', 0.55]]
    })
  }

  @Builder
  SetupProfileView() {
    Column() {
      // 进度条 (使用简单的Row和比例)
      Row({ space: 8 }) {
        Row().width(40).height(4).backgroundColor('#f2b415').borderRadius(2)
        Row().width(40).height(4).backgroundColor('#4e5971').borderRadius(2)
        Row().width(40).height(4).backgroundColor('#4e5971').borderRadius(2)
      }
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 24 })

      Column({ space: 16 }) {
        Text('设置个性化档案')
          .fontSize(26)
          .fontWeight(700)
          .fontColor('#ffffff')
          .textAlign(TextAlign.Center)
        
        Text('在宠物伙伴上为您心爱的宠物创建个性化档案。喂养它们，爱护它们，照顾它们。\n与它们共度美好时光')
          .fontSize(16)
          .fontWeight(500)
          .fontColor('#eceff2')
          .textAlign(TextAlign.Center)
          .lineHeight(24)
          .margin({ top: 10 })
      }

      Blank() // 占据剩余空间，将按钮推到底部

      Column({ space: 12 }) {
        Button('开始设置')
          .type(ButtonType.Normal)
          .width('100%')
          .height(54)
          .backgroundColor('#0894bd')
          .fontColor('#ffffff')
          .fontSize(16)
          .fontWeight(500)
          .borderRadius(14)
          .scale({ x: this.btnScaleSetup, y: this.btnScaleSetup })
          .animation({ duration: 150 })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) this.btnScaleSetup = 0.95;
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.btnScaleSetup = 1;
          })
          .onClick(() => {
            this.currentStep = 1;
          })

        Button('暂不注册')
          .type(ButtonType.Normal)
          .width('100%')
          .height(54)
          .backgroundColor(Color.Transparent)
          .fontColor('#f7fafc')
          .fontSize(14)
          .fontWeight(500)
          .scale({ x: this.btnScaleLater, y: this.btnScaleLater })
          .animation({ duration: 150 })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) this.btnScaleLater = 0.95;
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.btnScaleLater = 1;
          })
          .onClick(() => {
            router.back()
          })
      }
      .padding({ bottom: 12 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  CreateAccountView() {
    Column() {
      Column({ space: 10 }) {
        Text('创建账号')
          .fontSize(26)
          .fontWeight(700)
          .fontColor('#ffffff')
          .textAlign(TextAlign.Center)
        
        Text('欢迎！请输入您的信息以开始使用。')
          .fontSize(16)
          .fontWeight(500)
          .fontColor('#eceff2')
          .textAlign(TextAlign.Center)
          .lineHeight(24)
          .margin({ bottom: 16 })
      }

      Column({ space: 16 }) {
        TextInput({ placeholder: '您的邮箱', text: this.email })
          .width('100%')
          .height(54)
          .backgroundColor('#2355a1')
          .fontColor('#ffffff')
          .placeholderColor('#a0b3c6')
          .fontSize(16)
          .borderRadius(14)
          .border({ width: 1, color: '#223d61' })
          .onChange((value: string) => {
            this.email = value;
          })

        TextInput({ placeholder: '密码', text: this.password })
          .type(InputType.Password)
          .width('100%')
          .height(54)
          .backgroundColor('#2355a1')
          .fontColor('#ffffff')
          .placeholderColor('#a0b3c6')
          .fontSize(16)
          .borderRadius(14)
          .border({ width: 1, color: '#223d61' })
          .showPasswordIcon(true)
          .onChange((value: string) => {
            this.password = value;
          })

        Row({ space: 8 }) {
          Checkbox({ name: 'terms', group: 'termsGroup' })
            .select(this.acceptedTerms)
            .selectedColor('#0894bd')
            .unselectedColor('#2e3945')
            .width(16)
            .height(16)
            .onChange((value: boolean) => {
              this.acceptedTerms = value;
            })
          Text('同意服务条款和隐私政策')
            .fontSize(14)
            .fontColor('#f7fafc')
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ left: 4 })
      }

      Blank() // 占据剩余空间，将按钮推到底部

      Column({ space: 16 }) {
        Button('创建账号')
          .type(ButtonType.Normal)
          .width('100%')
          .height(54)
          .backgroundColor('#0894bd')
          .fontColor('#ffffff')
          .fontSize(16)
          .fontWeight(500)
          .borderRadius(14)
          .opacity(this.email && this.password && this.acceptedTerms ? 1 : 0.5)
          .scale({ x: this.btnScaleCreate, y: this.btnScaleCreate })
          .animation({ duration: 150 })
          .onTouch((event: TouchEvent) => {
            if (this.email && this.password && this.acceptedTerms) {
              if (event.type === TouchType.Down) this.btnScaleCreate = 0.95;
              if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.btnScaleCreate = 1;
            }
          })
          .onClick(() => {
            if (this.email && this.password && this.acceptedTerms) {
              router.replaceUrl({ url: 'pages/Index' })
            }
          })

        Row() {
          Text('已有账号？')
            .fontSize(14)
            .fontColor('#cbdbf0')
          Text('在此登录！')
            .fontSize(14)
            .fontColor('#ffffff')
            .fontWeight(500)
            .onClick(() => {
              router.replaceUrl({ url: 'pages/WelcomePage' })
            })
        }
        .padding(9)
      }
      .padding({ bottom: 12 })
    }
    .width('100%')
    .height('100%')
  }
}
