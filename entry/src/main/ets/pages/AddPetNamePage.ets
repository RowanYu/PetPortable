import { router } from '@kit.ArkUI';
import { PetModel } from '../common/models/PetModel';
import { PetStore } from '../common/services/PetStore';

@Entry
@Component
struct AddPetNamePage {
  @State petId: string = '';
  @State petBreedName: string = '';
  @State petImage: Resource | undefined = undefined;
  @State petModelPath: string = '';
  
  @State petNameInput: string = '';
  @State backBtnScale: number = 1;
  @State btnScaleContinue: number = 1;

  aboutToAppear() {
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      this.petId = params['petId'] as string;
      this.petBreedName = params['petBreedName'] as string;
      this.petImage = params['petImage'] as Resource;
      this.petModelPath = params['petModelPath'] as string;
    }
  }

  build() {
    Column() {
      // 顶部导航与进度区域
      Column() {
        Row() {
          // 返回按钮
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

          // 标题区域
          Column({ space: 4 }) {
            Text('添加宠物档案')
              .fontSize(16)
              .fontWeight(600)
              .fontColor('#ffffff')
            Text('名字')
              .fontSize(14)
              .fontColor('#f7fafc')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          // 步骤
          Column({ space: 2 }) {
            Text('步骤')
              .fontSize(11)
              .fontColor('#ffffff')
            Row() {
              Text('3')
                .fontSize(11)
                .fontWeight(600)
                .fontColor('#ffffff')
              Text('/9')
                .fontSize(11)
                .fontColor('#ffffff')
            }
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
        .height(44)
        .padding({ left: 16, right: 16 })
        .margin({ top: 16, bottom: 16 })

        // 进度条
        Row() {
          Row()
            .width('33%')
            .height(4)
            .backgroundColor('#f2b415')
            .borderRadius(2)
          Row()
            .layoutWeight(1)
            .height(4)
            .backgroundColor('#4e5971')
            .borderRadius(2)
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        .margin({ bottom: 24 })
      }
      .width('100%')
      .backgroundColor('#012a3e')
      .shadow({ radius: 10, color: 'rgba(12, 26, 75, 0.08)', offsetY: 4 })
      .zIndex(2)

      // 主内容区
      Scroll() {
        Column({ space: 24 }) {
          // 宠物头像区域
          Stack({ alignContent: Alignment.BottomEnd }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle({ width: 280, height: 280 })
                .fill('transparent')
                .stroke('#606873')
                .strokeWidth(1)
                .opacity(0.5)
              Circle({ width: 226, height: 226 })
                .fill('#0894bd')
                .stroke('#606873')
                .strokeWidth(1)
                .opacity(0.5)
              
              if (this.petImage) {
                Image(this.petImage)
                  .width(251)
                  .height(202)
                  .objectFit(ImageFit.Contain)
                  .margin({ top: 20 })
              }
            }
            .width(328)
            .height(328)
            .margin({ top: 24 })

            // 相册小图标
            Row() {
              Image($r('app.media.ic_gallery'))
                .width(20)
                .height(20)
            }
            .width(46)
            .height(46)
            .backgroundColor('#ffffff')
            .borderRadius(14)
            .justifyContent(FlexAlign.Center)
            .shadow({ radius: 4, color: 'rgba(139, 158, 184, 0.2)', offsetY: 1 })
            .margin({ right: 64, bottom: 40 })
          }

          // 输入名称区域
          Column({ space: 16 }) {
            Text('您的宠物叫什么名字？')
              .fontSize(16)
              .fontWeight(500)
              .fontColor('#ffffff')

            TextInput({ placeholder: '宠物名字', text: this.petNameInput })
              .width('100%')
              .height(54)
              .backgroundColor('#313945')
              .fontColor('#ffffff')
              .placeholderColor('#f7fafc')
              .fontSize(16)
              .borderRadius(14)
              .border({ width: 1, color: '#606873' })
              .onChange((value: string) => {
                this.petNameInput = value;
              })
          }
          .padding({ left: 24, right: 24 })
          .width('100%')
        }
        .width('100%')
        .padding({ bottom: 120 })
      }
      .layoutWeight(1)
      .width('100%')
      .zIndex(1)

      // 底部悬浮按钮区域
      Column({ space: 12 }) {
        Button('继续')
          .type(ButtonType.Normal)
          .width('100%')
          .height(54)
          .backgroundColor(this.petNameInput.trim().length > 0 ? '#0894bd' : '#0c4180')
          .fontColor(this.petNameInput.trim().length > 0 ? '#ffffff' : '#a0aec0')
          .fontSize(16)
          .fontWeight(500)
          .borderRadius(14)
          .scale({ x: this.btnScaleContinue, y: this.btnScaleContinue })
          .animation({ duration: 150 })
          .onTouch((event: TouchEvent) => {
            if (this.petNameInput.trim().length > 0) {
              if (event.type === TouchType.Down) this.btnScaleContinue = 0.95;
              if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.btnScaleContinue = 1;
            }
          })
          .onClick(() => {
            if (this.petNameInput.trim().length > 0) {
              let newPet = new PetModel(this.petNameInput.trim(), this.petBreedName, this.petImage, this.petModelPath);
              // 入列表并设为当前选中宠物（保留之前已添加的所有宠物）
              PetStore.addPet(newPet);

              // 路由回宠物档案页面，并传递信息
              // 注意：为了清空历史页面栈，或者返回到特定页面并带参数
              router.clear(); // 清空栈（可选，取决于产品需求，通常可以用 router.replaceUrl 或 router.back() 方案）
              router.replaceUrl({
                url: 'pages/PetProfilePage',
                params: {
                  newPetAdded: true,
                  petName: this.petNameInput.trim(),
                  petBreedName: this.petBreedName,
                  petImage: this.petImage,
                  petModelPath: this.petModelPath,
                  adoptionDate: new Date().toLocaleDateString()
                }
              })
            }
          })
      }
      .width('100%')
      .backgroundColor('#012a3e')
      .borderRadius({ topLeft: 26, topRight: 26 })
      .padding({ top: 24, left: 24, right: 24, bottom: 32 })
      .shadow({ radius: 8, color: 'rgba(73, 77, 90, 0.12)', offsetY: -3 })
      .position({ y: '100%' })
      .translate({ y: '-100%' })
      .zIndex(3)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#081e2a')
  }
}
