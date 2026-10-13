import { router } from '@kit.ArkUI';
import { PetModel } from '../common/models/PetModel';
import { PetStore } from '../common/services/PetStore';

type PersonalityDimensionKey = 'cheerful' | 'independence' | 'curiosity' | 'naughty' | 'warmth';

class PersonalityTrendDisplay {
  value: number = 0;
  score: number = 0;
  label: string = '稳定';
  color: string = '#A0B3C6';
  progressWidth: string = '6%';
}

class StageExplainDisplay {
  active: boolean = false;
  titleColor: string = '#FFFFFF';
  rangeColor: string = '#A0B3C6';
  detailColor: string = '#A0B3C6';
  backgroundColor: string = '#062137';
  borderWidth: number = 0;
}

@Entry
@Component
struct PetProfilePage {
  @StorageLink('currentPet') pet: PetModel = new PetModel('小黄鸭', '宠物', $r('app.media.pet_duck_full'), 'duck_default');
  @StorageLink('petList') petList: PetModel[] = [];
  @StorageLink('currentPetIndex') currentPetIndex: number = 0;
  @State currentIndex: number = 0;
  @State btnScaleAdd: number = 1;
  @State btnScaleDetail: number = 1;
  @State btnScaleRecord: number = 1;
  @State backBtnScale: number = 1;

  aboutToAppear(): void {
    // 初始化宠物列表与当前选中索引
    this.petList = PetStore.getList();
    this.currentPetIndex = PetStore.getCurrentIndex();
  }

  private isPetSelected(index: number): boolean {
    return this.currentPetIndex === index;
  }

  private selectPet(index: number): void {
    if (index === this.currentPetIndex) {
      return;
    }
    PetStore.switchByIndex(index);
    // currentPetIndex 与 pet 由 @StorageLink 自动同步刷新
  }

  private hasPet(): boolean {
    return this.pet.name.trim().length > 0;
  }

  private formatAdoptionDate(): string {
    return new Date(this.pet.adoptedTimestamp).toLocaleDateString();
  }

  private formatLastInteraction(): string {
    if (this.pet.interactionStats.lastInteractionTime <= 0) {
      return '暂无';
    }
    return new Date(this.pet.interactionStats.lastInteractionTime).toLocaleString();
  }

  private resolvePersonalityValue(dimension: PersonalityDimensionKey): number {
    if (dimension === 'cheerful') {
      return this.pet.personality.cheerful;
    }
    if (dimension === 'independence') {
      return this.pet.personality.independence;
    }
    if (dimension === 'curiosity') {
      return this.pet.personality.curiosity;
    }
    if (dimension === 'naughty') {
      return this.pet.personality.naughty;
    }
    return this.pet.personality.warmth;
  }

  private clampTrend(value: number): number {
    return Math.max(-6, Math.min(9, value));
  }

  private resolveTrendScore(dimension: PersonalityDimensionKey): number {
    const stats = this.pet.interactionStats;
    const personalityValue: number = this.resolvePersonalityValue(dimension);
    let behaviorScore: number = 0;
    if (dimension === 'cheerful') {
      behaviorScore = Math.floor((stats.playCount + stats.chatCount + stats.petCount) / 3) - 2;
    } else if (dimension === 'independence') {
      behaviorScore = Math.floor((stats.trainCount + stats.sleepCount) / 2) - 2;
    } else if (dimension === 'curiosity') {
      behaviorScore = Math.floor((stats.playCount + stats.trainCount + stats.chatCount) / 3) - 2;
    } else if (dimension === 'naughty') {
      behaviorScore = Math.floor((stats.playCount * 2 + stats.trainCount) / 4) - 2;
    } else {
      behaviorScore = Math.floor((stats.petCount + stats.chatCount + stats.feedCount) / 3) - 2;
    }
    const personalityBias: number = Math.floor((personalityValue - 50) / 20);
    return this.clampTrend(behaviorScore + personalityBias);
  }

  private resolveStageSummary(): string {
    if (this.pet.growthStage === '初识期') {
      return '害羞、简单互动、基础对话';
    }
    if (this.pet.growthStage === '熟悉期') {
      return '主动互动、记忆积累、性格初显';
    }
    if (this.pet.growthStage === '亲密期') {
      return '深度对话、情绪共鸣、性格稳定';
    }
    return '心有灵犀、独特人格、专属记忆';
  }

  private resolvePersonalityTrendDisplay(dimension: PersonalityDimensionKey): PersonalityTrendDisplay {
    const display: PersonalityTrendDisplay = new PersonalityTrendDisplay();
    const value: number = this.resolvePersonalityValue(dimension);
    const trendScore: number = this.resolveTrendScore(dimension);

    display.value = value;
    display.score = trendScore;
    display.label = trendScore > 1 ? '上升' : trendScore < -1 ? '回落' : '稳定';
    display.color = trendScore > 1 ? '#34C759' : trendScore < -1 ? '#FF6B6B' : '#A0B3C6';
    display.progressWidth = `${Math.max(6, value)}%`;
    return display;
  }

  private resolveStageExplainDisplay(stage: string): StageExplainDisplay {
    const display: StageExplainDisplay = new StageExplainDisplay();
    const active: boolean = this.pet.growthStage === stage;
    display.active = active;
    display.titleColor = active ? '#8FD9EF' : '#FFFFFF';
    display.rangeColor = active ? '#8FD9EF' : '#A0B3C6';
    display.detailColor = active ? '#D7F5FF' : '#A0B3C6';
    display.backgroundColor = active ? 'rgba(8, 148, 189, 0.20)' : '#062137';
    display.borderWidth = active ? 1 : 0;
    return display;
  }

  private resolveTrendScoreText(dimension: PersonalityDimensionKey): string {
    const score: number = this.resolvePersonalityTrendDisplay(dimension).score;
    return score >= 0 ? `+${score}` : `${score}`;
  }

  @Builder
  private PersonalityTrendRow(title: string, dimension: PersonalityDimensionKey) {
    Column({ space: 8 }) {
      Row() {
        Text(title)
          .fontSize(13)
          .fontColor('#FFFFFF');

        Blank()
          .layoutWeight(1);

        Text(`${this.resolvePersonalityTrendDisplay(dimension).value}`)
          .fontSize(13)
          .fontColor('#ECEFF2');

        Text(` ${this.resolvePersonalityTrendDisplay(dimension).label} ${this.resolveTrendScoreText(dimension)}`)
          .fontSize(12)
          .fontColor(this.resolvePersonalityTrendDisplay(dimension).color)
          .margin({ left: 8 });
      }
      .width('100%');

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(8)
          .backgroundColor('#163449')
          .borderRadius(10);

        Row()
          .width(this.resolvePersonalityTrendDisplay(dimension).progressWidth)
          .height(8)
          .backgroundColor('#0894BD')
          .borderRadius(10);
      }
      .width('100%');
    }
    .width('100%');
  }

  @Builder
  private StageExplainItem(stage: string, rangeText: string, detail: string) {
    Column({ space: 6 }) {
      Row() {
        Text(stage)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveStageExplainDisplay(stage).titleColor);

        Blank()
          .layoutWeight(1);

        Text(rangeText)
          .fontSize(12)
          .fontColor(this.resolveStageExplainDisplay(stage).rangeColor);
      }
      .width('100%');

      Text(detail)
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.resolveStageExplainDisplay(stage).detailColor)
        .width('100%');
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.resolveStageExplainDisplay(stage).backgroundColor)
    .borderRadius(12)
    .border({ width: this.resolveStageExplainDisplay(stage).borderWidth, color: '#0894BD' });
  }

  @Builder
  private PetSelector() {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(this.petList, (item: PetModel, index: number) => {
          Column({ space: 6 }) {
            Stack() {
              Image(item.image)
                .width(56)
                .height(56)
                .objectFit(ImageFit.Cover)
                .borderRadius(28);
            }
            .width(56)
            .height(56)
            .borderRadius(28)
            .border({
              width: this.isPetSelected(index) ? 2 : 0,
              color: '#1B85F3'
            })
            .onClick(() => {
              this.selectPet(index);
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 });

            Text(item.name)
              .fontSize(12)
              .fontColor(this.isPetSelected(index) ? '#1B85F3' : '#ECEFF2')
              .fontWeight(this.isPetSelected(index) ? 600 : 400)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .width(72)
          .alignItems(HorizontalAlign.Center);
        }, (item: PetModel, index: number) => `${index}-${item.name}`);

        // 末尾「新增宠物」入口
        Column({ space: 6 }) {
          Stack() {
            Image($r('app.media.ic_add'))
              .width(20)
              .height(20);
          }
          .width(56)
          .height(56)
          .borderRadius(28)
          .backgroundColor('rgba(8, 148, 189, 0.18)')
          .border({ width: 1, color: 'rgba(143, 217, 239, 0.45)', style: BorderStyle.Dashed })
          .onClick(() => {
            router.pushUrl({ url: 'pages/AddPetPage' });
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 });

          Text('新增宠物')
            .fontSize(12)
            .fontColor('#8FD9EF');
        }
        .width(72)
        .alignItems(HorizontalAlign.Center);
      }
      .padding({ left: 4, right: 12 })
      .height(80)
      .alignItems(VerticalAlign.Center);
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(80);
  }

  @Builder
  private TabButton(title: string, index: number) {
    Column({ space: 4 }) {
      Text(title)
        .fontColor(this.currentIndex === index ? '#1B85F3' : '#F7FAFC')
        .fontSize(16)
        .fontWeight(this.currentIndex === index ? 600 : 500);

      if (this.currentIndex === index) {
        Row()
          .width(20)
          .height(3)
          .backgroundColor('#1B85F3')
          .borderRadius(2);
      }
    }
    .width('33%')
    .height(40)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentIndex = index;
    });
  }

  @Builder
  private PetInfoView() {
    Column({ space: 18 }) {
      this.PetSelector();

      Row() {
        Image(this.pet.image)
          .width(96)
          .height(112)
          .objectFit(ImageFit.Contain)
          .borderRadius(20)
          .backgroundColor('#081E2A')
          .border({ width: 2, color: '#1B85F3' });

        Column({ space: 8 }) {
          Text(this.pet.name)
            .fontSize(20)
            .fontWeight(700)
            .fontColor('#FFFFFF');

          Text(this.pet.breed)
            .fontSize(14)
            .fontColor('#ECEFF2');

          Text(`领养日期：${this.formatAdoptionDate()}`)
            .fontSize(12)
            .fontColor('#A0B3C6');

          Text(`当前情绪：${this.pet.emotion}`)
            .fontSize(12)
            .fontColor('#8FD9EF');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 16 });
      }
      .width('100%')
      .backgroundColor('#062137')
      .borderRadius(16)
      .padding(20);

      Column({ space: 10 }) {
        Text('基础状态')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF');

        Text(`健康 ${this.pet.attributes.health}  心情 ${this.pet.attributes.mood}  精力 ${this.pet.attributes.energy}`)
          .fontSize(13)
          .fontColor('#ECEFF2');

        Text(`亲密 ${this.pet.attributes.intimacy}  服从 ${this.pet.attributes.obedience}  毒舌 ${this.pet.attributes.toxicity}`)
          .fontSize(13)
          .fontColor('#A0B3C6');
      }
      .width('100%')
      .backgroundColor('#062137')
      .borderRadius(16)
      .padding(16);
    }
    .width('100%');
  }

  @Builder
  private GrowthView() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text(`成长阶段：${this.pet.growthStage}`)
          .fontSize(16)
          .fontColor('#FFFFFF');

        Text(this.resolveStageSummary())
          .fontSize(13)
          .fontColor('#8FD9EF');

        Text(`等级 ${this.pet.level} · 经验 ${this.pet.exp} · 已解锁成就 ${this.pet.achievements.length} 项`)
          .fontSize(13)
          .fontColor('#A0B3C6');
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#062137')
      .borderRadius(16)
      .shadow({ radius: 8, color: '#16000000', offsetX: 0, offsetY: 4 });

      Column({ space: 12 }) {
        Text('性格维度变化趋势')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .width('100%');

        this.PersonalityTrendRow('开朗度', 'cheerful')
        this.PersonalityTrendRow('独立性', 'independence')
        this.PersonalityTrendRow('好奇心', 'curiosity')
        this.PersonalityTrendRow('调皮度', 'naughty')
        this.PersonalityTrendRow('暖心度', 'warmth')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#062137')
      .borderRadius(16)
      .shadow({ radius: 8, color: '#16000000', offsetX: 0, offsetY: 4 });

      Column({ space: 10 }) {
        Text('成长阶段说明')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .width('100%');

        this.StageExplainItem('初识期', '0-7天', '害羞、简单互动、基础对话')
        this.StageExplainItem('熟悉期', '7-30天', '主动互动、记忆积累、性格初显')
        this.StageExplainItem('亲密期', '30-90天', '深度对话、情绪共鸣、性格稳定')
        this.StageExplainItem('默契期', '90天+', '心有灵犀、独特人格、专属记忆')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#062137')
      .borderRadius(16)
      .shadow({ radius: 8, color: '#16000000', offsetX: 0, offsetY: 4 });

      Button('查看详情')
        .type(ButtonType.Normal)
        .width(160)
        .height(44)
        .backgroundColor('#062137')
        .fontColor('#FFFFFF')
        .fontSize(14)
        .borderRadius(14)
        .border({ width: 1, color: '#223D61' })
        .scale({ x: this.btnScaleDetail, y: this.btnScaleDetail })
        .animation({ duration: 150 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.btnScaleDetail = 0.95;
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.btnScaleDetail = 1;
          }
        })
        .onClick(() => {
          router.pushUrl({ url: 'pages/PetProfileDetail' });
        });
    }
    .width('100%');
  }

  @Builder
  private DataView() {
    Column({ space: 16 }) {
      Text(`累计互动 ${this.pet.interactionStats.totalInteractions} 次`)
        .fontSize(16)
        .fontColor('#FFFFFF');

      Text(`最近互动：${this.formatLastInteraction()}`)
        .fontSize(13)
        .fontColor('#A0B3C6');

      Text(`抚摸 ${this.pet.interactionStats.petCount} · 喂食 ${this.pet.interactionStats.feedCount} · 玩耍 ${this.pet.interactionStats.playCount}`)
        .fontSize(13)
        .fontColor('#ECEFF2');

      Text(`训练 ${this.pet.interactionStats.trainCount} · 洗澡 ${this.pet.interactionStats.bathCount} · 聊天 ${this.pet.interactionStats.chatCount}`)
        .fontSize(13)
        .fontColor('#ECEFF2');

      Button('查看记录')
        .type(ButtonType.Normal)
        .width(160)
        .height(44)
        .backgroundColor('#062137')
        .fontColor('#FFFFFF')
        .fontSize(14)
        .borderRadius(14)
        .border({ width: 1, color: '#223D61' })
        .scale({ x: this.btnScaleRecord, y: this.btnScaleRecord })
        .animation({ duration: 150 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.btnScaleRecord = 0.95;
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.btnScaleRecord = 1;
          }
        })
        .onClick(() => {
          router.pushUrl({ url: 'pages/PetProfileRecords' });
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  private EmptyView() {
    Column({ space: 24 }) {
      Stack() {
        Circle({ width: 120, height: 120 })
          .fill('rgba(247, 250, 252, 0.04)');
        Circle({ width: 90, height: 90 })
          .fill('rgba(247, 250, 252, 0.08)');
        Image($r('app.media.ic_pencil'))
          .width(40)
          .height(40);
      }

      Text('您的宠物列表为空')
        .fontSize(18)
        .fontWeight(600)
        .fontColor('#FFFFFF');

      Text('添加您的第一只宠物，开始记录它的成长与互动数据。')
        .fontSize(14)
        .fontColor('#A0B3C6')
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
        .lineHeight(20);

      Button('添加信息')
        .type(ButtonType.Normal)
        .width(200)
        .height(50)
        .backgroundColor('#0894BD')
        .fontColor('#FFFFFF')
        .fontSize(16)
        .fontWeight(500)
        .borderRadius(14)
        .scale({ x: this.btnScaleAdd, y: this.btnScaleAdd })
        .animation({ duration: 150 })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.btnScaleAdd = 0.95;
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.btnScaleAdd = 1;
          }
        })
        .onClick(() => {
          router.pushUrl({ url: 'pages/AddPetPage' });
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
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
            router.replaceUrl({ url: 'pages/Index' });
          });

        Text('宠物档案')
          .fontSize(20)
          .fontWeight(700)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ right: 24 });
      }
      .width('100%')
      .padding({ top: 16, bottom: 16, left: 16, right: 16 });

      if (!this.hasPet()) {
        this.EmptyView();
      } else {
        Row() {
          this.TabButton('信息', 0);
          this.TabButton('成长', 1);
          this.TabButton('数据', 2);
        }
        .width('100%')
        .height(44);

        Scroll() {
          Column() {
            if (this.currentIndex === 0) {
              this.PetInfoView();
            } else if (this.currentIndex === 1) {
              this.GrowthView();
            } else {
              this.DataView();
            }
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 24, bottom: 32 });
        }
        .layoutWeight(1)
        .width('100%');
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#012A3E');
  }
}
