import { router } from '@kit.ArkUI';
import { PetDreamRecord, PetModel } from '../common/models/PetModel';
import { PetAiService } from '../common/services/PetAiService';

@Entry
@Component
struct DreamDiaryPage {
  @StorageLink('currentPet') pet: PetModel = new PetModel('小橘', '宠物', $r('app.media.pet_duck_full'), 'duck_default');
  @State backBtnScale: number = 1;
  @State createBtnScale: number = 1;

  private findYesterdayDream(): PetDreamRecord | null {
    const now: Date = new Date();
    const yesterdayStart: number = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1).getTime();
    const todayStart: number = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    for (let i: number = 0; i < this.pet.dreams.length; i += 1) {
      const item: PetDreamRecord = this.pet.dreams[i];
      if (item.timestamp >= yesterdayStart && item.timestamp < todayStart) {
        return item;
      }
    }
    return null;
  }

  private viewYesterdayDream(): void {
    const yesterdayDream: PetDreamRecord | null = this.findYesterdayDream();
    if (yesterdayDream !== null) {
      this.pet.currentSpeech = '';
      return;
    }

    const yesterdayTime: number = Date.now() - 24 * 60 * 60 * 1000;
    const dream: PetDreamRecord = PetAiService.generateDream(this.pet, yesterdayTime);
    this.pet.currentSpeech = '';
  }

  @Builder
  private DreamCard(dream: PetDreamRecord) {
    Column({ space: 10 }) {
      Row() {
        Text(dream.title)
          .layoutWeight(1)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF');

        Text(dream.category)
          .fontSize(11)
          .fontColor('#8FD9EF')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('rgba(8, 148, 189, 0.2)')
          .borderRadius(10);
      }
      .width('100%');

      Text(dream.content)
        .fontSize(14)
        .lineHeight(22)
        .fontColor('rgba(255,255,255,0.85)');

      Text(`情绪标签：${dream.moodTag}`)
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.65)');
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#2A3641')
    .borderRadius(16)
    .shadow({ radius: 8, color: '#12000000', offsetX: 0, offsetY: 4 });
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor('#FFFFFF')
          .scale({ x: this.backBtnScale, y: this.backBtnScale })
          .animation({ duration: 150 })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.backBtnScale = 0.9;
            }
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.backBtnScale = 1;
            }
          })
          .onClick(() => {
            router.back();
          });

        Text('梦境日记')
          .layoutWeight(1)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .margin({ right: 24 });
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 10 });

      Button('查看昨天的梦境')
        .width('88%')
        .height(48)
        .backgroundColor('#0894BD')
        .fontColor('#FFFFFF')
        .fontSize(15)
        .borderRadius(14)
        .scale({ x: this.createBtnScale, y: this.createBtnScale })
        .animation({ duration: 150 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.createBtnScale = 0.95;
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.createBtnScale = 1;
          }
        })
        .onClick(() => {
          this.viewYesterdayDream();
        })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 });

      Scroll() {
        Column({ space: 12 }) {
          if (this.pet.dreams.length === 0) {
            Text('还没有梦境记录，点击上方按钮查看并记录昨天的梦境')
              .fontSize(14)
              .fontColor('rgba(255,255,255,0.72)')
              .margin({ top: 24 });
          } else {
            ForEach(this.pet.dreams, (dream: PetDreamRecord) => {
              this.DreamCard(dream);
            }, (dream: PetDreamRecord) => dream.id);
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 20 });
      }
      .layoutWeight(1)
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#081E2A');
  }
}
