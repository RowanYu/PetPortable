import { router } from '@kit.ArkUI';
import { PetAchievementRecord, PetModel } from '../common/models/PetModel';

@Entry
@Component
struct PetProfileDetail {
  @State backBtnScale: number = 1;
  @StorageLink('currentPet') pet: PetModel = new PetModel('小橘', '宠物', $r('app.media.pet_duck_full'), 'duck_default');

  private formatDate(timestamp: number): string {
    if (timestamp <= 0) {
      return '暂无';
    }
    return new Date(timestamp).toLocaleDateString();
  }

  @Builder
  private TagItem(title: string, value: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.68)');
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF');
    }
    .layoutWeight(1)
    .padding(14)
    .backgroundColor('#2A3641')
    .borderRadius(16);
  }

  @Builder
  private PersonalityRow(label: string, value: number) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#FFFFFF');

      Blank();

      Text(`${value}`)
        .fontSize(13)
        .fontColor('#8FD9EF');
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 });
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
            if (event.type === TouchType.Down) this.backBtnScale = 0.9;
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.backBtnScale = 1;
          })
          .onClick(() => {
            router.back();
          })

        Text('成长详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ right: 24 })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#081E2A');

      Scroll() {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            this.TagItem('成长阶段', this.pet.growthStage)
            this.TagItem('当前情绪', this.pet.emotion)
          }

          Row({ space: 10 }) {
            this.TagItem('等级', `${this.pet.level}`)
            this.TagItem('经验值', `${this.pet.exp}`)
          }

          Row({ space: 10 }) {
            this.TagItem('梦境记录', `${this.pet.dreams.length}`)
            this.TagItem('记忆总数', `${this.pet.memories.length}`)
          }

          Column({ space: 6 }) {
            Text('性格维度')
              .width('100%')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF');

            this.PersonalityRow('开朗', this.pet.personality.cheerful)
            this.PersonalityRow('独立', this.pet.personality.independence)
            this.PersonalityRow('好奇', this.pet.personality.curiosity)
            this.PersonalityRow('调皮', this.pet.personality.naughty)
            this.PersonalityRow('温暖', this.pet.personality.warmth)
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#2A3641')
          .borderRadius(16)
          .shadow({ radius: 6, color: '#12000000', offsetX: 0, offsetY: 4 });

          Column({ space: 10 }) {
            Row() {
              Text('成就记录')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF');
              Blank();
              Text(`${this.pet.achievements.length}项`)
                .fontSize(12)
                .fontColor('rgba(255,255,255,0.7)');
            }
            .width('100%');

            if (this.pet.achievements.length === 0) {
              Text('暂无成就，去互动解锁更多记录吧')
                .fontSize(13)
                .fontColor('rgba(255,255,255,0.72)');
            } else {
              ForEach(this.pet.achievements, (item: PetAchievementRecord) => {
                Column({ space: 4 }) {
                  Text(item.title)
                    .width('100%')
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                    .fontWeight(FontWeight.Medium);
                  Text(item.description)
                    .width('100%')
                    .fontSize(12)
                    .fontColor('rgba(255,255,255,0.78)');
                  Text(`解锁时间：${this.formatDate(item.unlockedAt)}`)
                    .width('100%')
                    .fontSize(11)
                    .fontColor('rgba(255,255,255,0.58)');
                }
                .width('100%')
                .padding(12)
                .backgroundColor('#31404D')
                .borderRadius(12);
              }, (item: PetAchievementRecord) => item.id);
            }
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#2A3641')
          .borderRadius(16)
          .shadow({ radius: 6, color: '#12000000', offsetX: 0, offsetY: 4 });
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 24 });
      }
      .layoutWeight(1)
      .width('100%');

    }
    .width('100%')
    .height('100%')
    .backgroundColor('#081E2A')
  }
}
