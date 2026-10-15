import { router } from '@kit.ArkUI';
import { PetModel } from '../common/models/PetModel';
import { InteractionLogItem, InteractionService, InteractionType } from '../common/services/InteractionService';

@Entry
@Component
struct PetProfileRecords {
  @State backBtnScale: number = 1;
  @StorageLink('currentPet') pet: PetModel = new PetModel('小橘', '宠物', $r('app.media.pet_duck_full'), 'duck_default');
  @State logs: InteractionLogItem[] = [];
  @State mostFrequentType: string = '暂无';
  @State lastInteractionLabel: string = '暂无';

  aboutToAppear(): void {
    this.logs = InteractionService.getInstance().getRecentLogs(30);
    void this.loadStats();
  }

  private async loadStats(): Promise<void> {
    const stats = await InteractionService.getInstance().getInteractionStats(this.pet);
    this.mostFrequentType = stats.totalInteractions > 0 ? this.resolveTypeName(stats.mostFrequentType) : '暂无';
    this.lastInteractionLabel = this.formatTime(stats.lastInteractionTime);
  }

  private formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '暂无';
    }
    const date: Date = new Date(timestamp);
    return `${date.getMonth() + 1}月${date.getDate()}日 ${date.getHours()}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  private resolveTypeName(type: InteractionType): string {
    if (type === 'pet') {
      return '抚摸';
    }
    if (type === 'feed') {
      return '喂食';
    }
    if (type === 'play') {
      return '玩耍';
    }
    if (type === 'train') {
      return '训练';
    }
    if (type === 'bath') {
      return '洗澡';
    }
    if (type === 'sleep') {
      return '休息';
    }
    return '聊天';
  }

  @Builder
  private StatCard(title: string, value: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.7)');
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF');
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor('#2A3641')
    .borderRadius(14);
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

        Text('互动记录')
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

      Column({ space: 10 }) {
        Row({ space: 10 }) {
          this.StatCard('累计互动', `${this.pet.interactionStats.totalInteractions}`)
          this.StatCard('今日互动', `${this.pet.interactionStats.todayCount}`)
        }

        Row({ space: 10 }) {
          this.StatCard('训练次数', `${this.pet.interactionStats.trainCount}`)
          this.StatCard('聊天次数', `${this.pet.interactionStats.chatCount}`)
        }

        Row({ space: 10 }) {
          this.StatCard('最高频互动', this.mostFrequentType)
          this.StatCard('最近互动', this.lastInteractionLabel)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 8 });

      Scroll() {
        Column({ space: 10 }) {
          if (this.logs.length === 0) {
            Text('暂无互动日志，先和宠物互动一次吧')
              .fontSize(14)
              .fontColor('rgba(255,255,255,0.72)')
              .margin({ top: 24 });
          } else {
            ForEach(this.logs, (item: InteractionLogItem) => {
              Column({ space: 5 }) {
                Row() {
                  Text(this.resolveTypeName(item.type))
                    .fontSize(13)
                    .fontColor('#8FD9EF')
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .backgroundColor('rgba(8,148,189,0.2)')
                    .borderRadius(9);

                  Blank();

                  Text(this.formatTime(item.result.timestamp))
                    .fontSize(11)
                    .fontColor('rgba(255,255,255,0.6)');
                }
                .width('100%');

                Text(item.result.bubbleText ?? '完成一次互动')
                  .fontSize(14)
                  .fontColor('#FFFFFF')
                  .width('100%');

                Text(`变化：心情 ${item.result.attributeChanges.mood ?? 0}，精力 ${item.result.attributeChanges.energy ?? 0}，亲密 ${item.result.attributeChanges.intimacy ?? 0}`)
                  .fontSize(12)
                  .fontColor('rgba(255,255,255,0.72)')
                  .width('100%');
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#2A3641')
              .borderRadius(14)
              .shadow({ radius: 6, color: '#12000000', offsetX: 0, offsetY: 3 });
            }, (item: InteractionLogItem) => `${item.type}-${item.result.timestamp}`);
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 24 });
      }
      .layoutWeight(1)
      .width('100%');

    }
    .width('100%')
    .height('100%')
    .backgroundColor('#081E2A')
  }
}
