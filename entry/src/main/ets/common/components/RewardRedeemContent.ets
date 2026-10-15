import { PetModel, PetRedeemedRewardRecord } from '../models/PetModel';
import { PetLifecycleService } from '../services/PetLifecycleService';

interface RewardItem {
  id: string;
  title: string;
  description: string;
  cost: number;
  boostLabel: string;
}

class RewardSummary {
  earnedPoints: number = 0;
  spentPoints: number = 0;
  availablePoints: number = 0;
}

@Component
export struct RewardRedeemContent {
  @ObjectLink pet: PetModel;
  onBack: () => void = () => {};
  @State backBtnScale: number = 1;

  private readonly rewardItems: RewardItem[] = [
    { id: 'energy_pack', title: '活力补给', description: '适合现场演示前快速恢复精力和健康状态', cost: 80, boostLabel: '健康 +8 · 精力 +12' },
    { id: 'mood_treat', title: '开心零食', description: '提升心情，让宠物进入更积极的陪伴状态', cost: 120, boostLabel: '心情 +12 · 亲密 +4' },
    { id: 'training_badge', title: '训练徽章', description: '记录一次训练成果，增强服从度与成长经验', cost: 160, boostLabel: '服从 +10 · 经验 +20' },
    { id: 'memory_album', title: '记忆相册', description: '把本次兑换沉淀为长期记忆，丰富个人中心展示数据', cost: 220, boostLabel: '长期记忆 +1 · 成就尝试解锁' }
  ];

  private buildSummary(): RewardSummary {
    const summary: RewardSummary = new RewardSummary();
    summary.earnedPoints = this.calculateEarnedPoints();
    summary.spentPoints = this.calculateSpentPoints();
    summary.availablePoints = Math.max(0, summary.earnedPoints - summary.spentPoints);
    return summary;
  }

  private calculateEarnedPoints(): number {
    const interactionPoints: number = this.pet.interactionStats.totalInteractions * 8;
    const todayPoints: number = this.pet.interactionStats.todayCount * 2;
    const achievementPoints: number = this.pet.achievements.length * 40;
    const intimacyPoints: number = this.pet.attributes.intimacy * 2;
    const dreamPoints: number = this.pet.dreams.length * 12;
    const levelPoints: number = this.pet.level * 20;
    return interactionPoints + todayPoints + achievementPoints + intimacyPoints + dreamPoints + levelPoints;
  }

  private calculateSpentPoints(): number {
    let total: number = 0;
    for (let i: number = 0; i < this.pet.redeemedRewards.length; i += 1) {
      total += this.pet.redeemedRewards[i].cost;
    }
    return total;
  }

  private hasRedeemed(id: string): boolean {
    return this.pet.redeemedRewards.some((item: PetRedeemedRewardRecord) => item.id === id);
  }

  private canRedeem(item: RewardItem): boolean {
    return !this.hasRedeemed(item.id) && this.buildSummary().availablePoints >= item.cost;
  }

  private formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '暂无';
    }
    const date: Date = new Date(timestamp);
    return `${date.getMonth() + 1}月${date.getDate()}日 ${date.getHours()}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  private getRedeemStateText(item: RewardItem): string {
    if (this.hasRedeemed(item.id)) {
      return '已兑换';
    }
    if (this.canRedeem(item)) {
      return '立即兑换';
    }
    return '积分不足';
  }

  private getButtonColor(item: RewardItem): string {
    if (this.hasRedeemed(item.id)) {
      return '#31404D';
    }
    if (this.canRedeem(item)) {
      return '#0894BD';
    }
    return 'rgba(49, 64, 77, 0.78)';
  }

  private redeem(item: RewardItem): void {
    if (!this.canRedeem(item)) {
      return;
    }

    const record: PetRedeemedRewardRecord = new PetRedeemedRewardRecord();
    record.id = item.id;
    record.title = item.title;
    record.cost = item.cost;
    record.redeemedAt = Date.now();
    this.pet.redeemedRewards.unshift(record);

    if (item.id === 'energy_pack') {
      this.pet.attributes.health = Math.min(100, this.pet.attributes.health + 8);
      this.pet.attributes.energy = Math.min(100, this.pet.attributes.energy + 12);
    } else if (item.id === 'mood_treat') {
      this.pet.attributes.mood = Math.min(100, this.pet.attributes.mood + 12);
      this.pet.attributes.intimacy = Math.min(100, this.pet.attributes.intimacy + 4);
    } else if (item.id === 'training_badge') {
      this.pet.attributes.obedience = Math.min(100, this.pet.attributes.obedience + 10);
      this.pet.exp += 20;
    } else {
      PetLifecycleService.addMemory(this.pet, '长期记忆', `${this.pet.name}兑换了${item.title}，这是一次值得保存的奖励记录`);
    }

    this.pet.currentSpeech = '';
    PetLifecycleService.updateEmotionAndStage(this.pet);
    PetLifecycleService.unlockAchievement(this.pet, 'first_reward', '首次兑换', '完成第一次奖励兑换');
  }

  @Builder
  private Header() {
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
          this.onBack();
        });

      Text('奖励兑换')
        .layoutWeight(1)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .margin({ right: 24 });
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 10 });
  }

  @Builder
  private SummaryCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 6 }) {
          Text(`${this.buildSummary().availablePoints}`)
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF');
          Text('可用积分')
            .fontSize(13)
            .fontColor('rgba(255,255,255,0.72)');
        }
        .alignItems(HorizontalAlign.Start);

        Blank();

        Image(this.pet.image)
          .width(72)
          .height(72)
          .objectFit(ImageFit.Contain)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(16);
      }
      .width('100%');

      Text(`${this.pet.name} · ${this.pet.growthStage} · 亲密度 ${this.pet.attributes.intimacy}`)
        .fontSize(14)
        .fontColor('#D7F5FF')
        .width('100%');

      Row({ space: 8 }) {
        this.SmallStat('累计获取', `${this.buildSummary().earnedPoints}`)
        this.SmallStat('已使用', `${this.buildSummary().spentPoints}`)
        this.SmallStat('已兑换', `${this.pet.redeemedRewards.length}`)
      }
      .width('100%');
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#2A3641')
    .borderRadius(16)
    .shadow({ radius: 8, color: '#12000000', offsetX: 0, offsetY: 4 });
  }

  @Builder
  private SmallStat(title: string, value: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF');
      Text(title)
        .fontSize(11)
        .fontColor('rgba(255,255,255,0.65)');
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .backgroundColor('rgba(255,255,255,0.08)')
    .borderRadius(12);
  }

  @Builder
  private RewardCard(item: RewardItem) {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 6 }) {
          Text(item.title)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF');
          Text(item.description)
            .fontSize(12)
            .lineHeight(18)
            .fontColor('rgba(255,255,255,0.72)');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Text(`${item.cost}分`)
          .fontSize(13)
          .fontColor('#8FD9EF')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('rgba(8, 148, 189, 0.20)')
          .borderRadius(12);
      }
      .width('100%');

      Row() {
        Text(item.boostLabel)
          .fontSize(12)
          .fontColor('#D7F5FF');

        Blank();

        Button(this.getRedeemStateText(item))
          .type(ButtonType.Normal)
          .height(36)
          .backgroundColor(this.getButtonColor(item))
          .fontColor('#FFFFFF')
          .fontSize(13)
          .borderRadius(12)
          .enabled(this.canRedeem(item))
          .onClick(() => {
            this.redeem(item);
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 });
      }
      .width('100%');
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#2A3641')
    .borderRadius(16)
    .shadow({ radius: 8, color: '#12000000', offsetX: 0, offsetY: 4 });
  }

  @Builder
  private RedeemHistory() {
    Column({ space: 10 }) {
      Text('兑换记录')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%');

      if (this.pet.redeemedRewards.length === 0) {
        Text('暂无兑换记录，先用互动积分兑换一个奖励')
          .fontSize(13)
          .fontColor('rgba(255,255,255,0.68)')
          .width('100%');
      } else {
        ForEach(this.pet.redeemedRewards, (item: PetRedeemedRewardRecord) => {
          Row() {
            Text(item.title)
              .fontSize(13)
              .fontColor('#FFFFFF');
            Blank();
            Text(`${item.cost}分 · ${this.formatTime(item.redeemedAt)}`)
              .fontSize(11)
              .fontColor('rgba(255,255,255,0.62)');
          }
          .width('100%')
          .padding(12)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(12);
        }, (item: PetRedeemedRewardRecord) => `${item.id}-${item.redeemedAt}`);
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#2A3641')
    .borderRadius(16)
    .shadow({ radius: 8, color: '#12000000', offsetX: 0, offsetY: 4 });
  }

  build() {
    Column() {
      this.Header();

      Scroll() {
        Column({ space: 12 }) {
          this.SummaryCard();

          Text('可兑换奖励')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .width('100%')
            .margin({ top: 4 });

          ForEach(this.rewardItems, (item: RewardItem) => {
            this.RewardCard(item);
          }, (item: RewardItem) => item.id);

          this.RedeemHistory();
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 24 });
      }
      .layoutWeight(1)
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#081E2A');
  }
}
