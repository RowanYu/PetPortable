import { router } from '@kit.ArkUI';

interface PetBreed {
  id: string;
  name: string;
  image: Resource;
  modelPath: string;
}

@Entry
@Component
struct AddPetPage {
  @State selectedBreedId: string = 'duck_default';
  
  // 交互反馈：点击项缩放效果
  @State btnScaleContinue: number = 1;
  @State btnScaleOther: number = 1;
  @State backBtnScale: number = 1;

  petBreeds: PetBreed[] = [
    { id: 'duck_default', name: '\u9e2d\u5b50', image: $r('app.media.pet_duck_full'), modelPath: 'duck_default' },
    { id: 'fox_default', name: '狐狸', image: $r('app.media.fox_idle_01'), modelPath: 'fox_default' },
    { id: 'golden_default', name: '金毛', image: $r('app.media.golden_idle_01'), modelPath: 'golden_default' },
    { id: 'cat_default', name: '猫', image: $r('app.media.cat_idle_01'), modelPath: 'cat_default' },
    {
      id: 'live2d_mao',
      name: '虹色猫',
      image: $r('app.media.live2d_mao_idle_01'),
      modelPath: 'live2d_mao_pro'
    },
    {
      id: 'live2d_real_mao_pro',
      name: '虹色猫·真',
      image: $r('app.media.live2d_mao_idle_01'),
      modelPath: 'live2d_real:mao_pro'
    },
    {
      id: 'live2d_real_shizuku',
      name: '雫·真',
      image: $r('app.media.live2d_mao_idle_01'),
      modelPath: 'live2d_real:shizuku'
    },
    { id: 'coyote', name: '郊狼', image: $r('app.media.pet_dog_1'), modelPath: 'coyote.glb' },
    { id: 'dog_1', name: '中华田园犬', image: $r('app.media.pet_dog_1'), modelPath: '' },
    { id: 'corgi', name: '柯基', image: $r('app.media.pet_corgi'), modelPath: '' },
    { id: 'akita', name: '秋田犬', image: $r('app.media.pet_akita'), modelPath: '' },
    { id: 'beagle', name: '比格犬', image: $r('app.media.pet_beagle'), modelPath: '' },
    { id: 'bichon_frise', name: '比熊犬', image: $r('app.media.pet_bichon_frise'), modelPath: '' },
    { id: 'border_collie', name: '边境牧羊犬', image: $r('app.media.pet_border_collie'), modelPath: '' },
    { id: 'boxer', name: '拳师犬', image: $r('app.media.pet_boxer'), modelPath: '' },
    { id: 'chow_chow', name: '松狮犬', image: $r('app.media.pet_chow_chow'), modelPath: '' }
  ];

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
            Text('品种')
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
              Text('2')
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
            .width('22%')
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

      // 宠物列表区域
      Scroll() {
        Grid() {
          ForEach(this.petBreeds, (pet: PetBreed) => {
            GridItem() {
              this.PetCardView(pet)
            }
          }, (pet: PetBreed) => pet.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(16)
        .rowsGap(16)
        .padding({ left: 24, right: 24, top: 16, bottom: 120 }) // 底部留出空间给固定按钮
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
          .backgroundColor('#0894bd')
          .fontColor('#ffffff')
          .fontSize(16)
          .fontWeight(500)
          .borderRadius(14)
          .scale({ x: this.btnScaleContinue, y: this.btnScaleContinue })
          .animation({ duration: 150 })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) this.btnScaleContinue = 0.95;
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.btnScaleContinue = 1;
          })
          .onClick(() => {
            let selectedPet = this.petBreeds.find(p => p.id === this.selectedBreedId);
            if (selectedPet) {
              router.pushUrl({
                url: 'pages/AddPetNamePage',
                params: {
                  petId: selectedPet.id,
                  petBreedName: selectedPet.name,
                  // 这里传递资源 ID 路径的字符串给下一个页面，也可以直接传 Resource
                  petImage: selectedPet.image,
                  petModelPath: selectedPet.modelPath
                }
              });
            }
          })

        Button('添加其他动物')
          .type(ButtonType.Normal)
          .width('100%')
          .height(54)
          .backgroundColor(Color.Transparent)
          .fontColor('#f7fafc')
          .fontSize(14)
          .fontWeight(500)
          .scale({ x: this.btnScaleOther, y: this.btnScaleOther })
          .animation({ duration: 150 })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) this.btnScaleOther = 0.95;
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.btnScaleOther = 1;
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
    .backgroundColor('#012a3e')
  }

  @Builder
  PetCardView(pet: PetBreed) {
    Stack({ alignContent: Alignment.Top }) {
      // 标题
      Text(pet.name)
        .fontSize(14)
        .fontWeight(600)
        .fontColor(this.selectedBreedId === pet.id ? '#1b85f3' : '#ffffff')
        .margin({ top: 20 })
        .zIndex(2)

      // 底部同心圆装饰
      Stack() {
        Circle({ width: 126, height: 126 }).fill('rgba(247, 250, 252, 0.07)')
        Circle({ width: 108, height: 108 }).fill('rgba(247, 250, 252, 0.04)')
        Circle({ width: 86, height: 86 }).fill('rgba(255, 255, 255, 0.02)')
      }
      .margin({ top: 68 })
      .zIndex(1)

      // 宠物图片
      Image(pet.image)
        .width(146)
        .height(117)
        .objectFit(ImageFit.Contain)
        .margin({ top: 50 })
        .zIndex(3)
    }
    .width('100%')
    .height(175)
    .backgroundColor('#062137')
    .borderRadius(14)
    .border({ 
      width: 2, 
      color: this.selectedBreedId === pet.id ? '#1b85f3' : 'transparent' 
    })
    .shadow({ radius: 20, color: 'rgba(50, 50, 71, 0.05)' })
    .clip(true)
    .onClick(() => {
      this.selectedBreedId = pet.id;
    })
  }
}
