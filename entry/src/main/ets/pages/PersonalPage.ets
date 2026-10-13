import { router } from '@kit.ArkUI';
import { RewardRedeemContent } from '../common/components/RewardRedeemContent';
import { PetModel } from '../common/models/PetModel';

@Entry
@Component
struct PersonalPage {
  @State backBtnScale: number = 1;
  @State currentView: 'center' | 'redeem' = 'center';
  @StorageLink('currentPet') pet: PetModel = new PetModel('小黄鸭', '宠物', $r('app.media.pet_duck_full'), 'duck_default');

  private calculateRewardPoints(): number {
    let spentPoints: number = 0;
    for (let i: number = 0; i < this.pet.redeemedRewards.length; i += 1) {
      spentPoints += this.pet.redeemedRewards[i].cost;
    }
    const earnedPoints: number = this.pet.interactionStats.totalInteractions * 8
      + this.pet.interactionStats.todayCount * 2
      + this.pet.achievements.length * 40
      + this.pet.attributes.intimacy * 2
      + this.pet.dreams.length * 12
      + this.pet.level * 20;
    return Math.max(0, earnedPoints - spentPoints);
  }

  private formatLastInteraction(): string {
    if (this.pet.interactionStats.lastInteractionTime <= 0) {
      return '暂无';
    }
    const date: Date = new Date(this.pet.interactionStats.lastInteractionTime);
    return `${date.getMonth() + 1}月${date.getDate()}日 ${date.getHours()}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  build() {
    if (this.currentView === 'redeem') {
      RewardRedeemContent({
        pet: this.pet,
        onBack: () => {
          this.currentView = 'center';
        }
      });
    } else {
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
        Text('个人中心')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .width('100%')
      .padding(16)
      .justifyContent(FlexAlign.Center);

      Column({ space: 16 }) {
        Row({ space: 10 }) {
          this.StatCard('互动总次数', `${this.pet.interactionStats.totalInteractions}`)
          this.StatCard('已解锁成就', `${this.pet.achievements.length}`)
        }

        Row({ space: 10 }) {
          this.StatCard('可用积分', `${this.calculateRewardPoints()}`)
          this.StatCard('亲密度', `${this.pet.attributes.intimacy}`)
        }

        Column({ space: 12 }) {
          Row({ space: 12 }) {
            Image(this.pet.image)
              .width(72)
              .height(72)
              .objectFit(ImageFit.Contain)
              .backgroundColor('rgba(255,255,255,0.08)')
              .borderRadius(16)

            Column({ space: 6 }) {
              Text(this.pet.name)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
              Text(`${this.pet.breed} · ${this.pet.growthStage}`)
                .fontSize(13)
                .fontColor('#8FD9EF')
              Text(`当前情绪：${this.pet.emotion}`)
                .fontSize(12)
                .fontColor('rgba(255,255,255,0.72)')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          Text(`最近互动：${this.formatLastInteraction()} · 经验 ${this.pet.exp}`)
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.72)')
            .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#2A3641')
        .borderRadius(16)
        .shadow({ radius: 6, color: '#12000000', offsetX: 0, offsetY: 3 })

        Row() {
          Text('积分商城')
            .fontColor('#FFFFFF')
          Blank()
          Button('去兑换')
            .backgroundColor('#0894BD')
            .fontColor('#FFFFFF')
            .borderRadius(12)
            .onClick(() => {
              this.currentView = 'redeem';
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#2A3641')
        .borderRadius(16)

        Row() {
          Text('梦境日记')
            .fontColor('#FFFFFF')
          Blank()
          Button('查看')
            .backgroundColor('#31404D')
            .fontColor('#FFFFFF')
            .borderRadius(12)
            .onClick(() => {
              router.pushUrl({ url: 'pages/DreamDiaryPage' })
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#2A3641')
        .borderRadius(16)

        Row() {
          Text('环境感知')
            .fontColor('#FFFFFF')
          Blank()
          Button('查看')
            .backgroundColor('#31404D')
            .fontColor('#FFFFFF')
            .borderRadius(12)
            .onClick(() => {
              router.pushUrl({ url: 'pages/SensorPanelPage' })
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#2A3641')
        .borderRadius(16)
      }
      .padding(16)
      .flexGrow(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#081E2A')
    }
  }

  @Builder
  private StatCard(title: string, value: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.7)')
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
    }
    .layoutWeight(1)
    .padding(16)
    .backgroundColor('#2A3641')
    .borderRadius(16)
    .shadow({ radius: 6, color: '#12000000', offsetX: 0, offsetY: 3 })
  }
}
