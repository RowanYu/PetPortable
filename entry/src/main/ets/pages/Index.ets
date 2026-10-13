import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { PetActionMenu } from '../common/components/PetActionMenu';
import { PetSprite } from '../common/components/PetSprite';
import { PetStatusBar } from '../common/components/PetStatusBar';
import { PetModel } from '../common/models/PetModel';
import { InteractionService } from '../common/services/InteractionService';
import { PetLifecycleService } from '../common/services/PetLifecycleService';
import { PetActionSoundService } from '../common/services/PetActionSoundService';
import { PetVideoRelayService } from '../common/services/PetVideoRelayService';
import { EnvironmentSnapshot, PetSensorService } from '../common/services/PetSensorService';
import { CommonConstants } from '../common/constants/CommonConstants';

interface SideActionItem {
  label: string;
  icon: Resource;
  kind: 'action' | 'route' | 'sheet';
  action?: 'interact' | 'train' | 'bath' | 'sleep';
  route?: string;
  sheet?: 'feed' | 'play';
}

interface FeedSheetOption {
  id: string;
  label: string;
  quantity: number;
}

interface PlaySheetOption {
  id: string;
  label: string;
  duration: number;
}

@Entry
@Component
struct Index {
  @StorageLink('currentPet') pet: PetModel = new PetModel('\u5c0f\u9ec4\u9e2d', '\u5ba0\u7269', $r('app.media.pet_duck_full'), 'duck_default');
  @State backBtnScale: number = 1;
  @State envTip: string = '';
  @State envVisible: boolean = false;
  @State snapshot: EnvironmentSnapshot = PetSensorService.getLatest();
  @State sideRailExpanded: boolean = true;
  @State feedSheetVisible: boolean = false;
  @State playSheetVisible: boolean = false;
  @State actionSheetOffsetY: number = 96;
  @State selectedFeedId: string = 'fish_meal';
  @State selectedPlayId: string = 'ball';
  @State devPanelVisible: boolean = false;
  @State devSheetOffsetY: number = 96;
  @State devBtnScale: number = 1;
  @State extremeReactionMode: 'auto' | 'manual' = 'auto';
  @State relayDiagTip: string = '';
  @State relayDiagVisible: boolean = false;
  @State relayPingBusy: boolean = false;
  private readonly sideActionItems: SideActionItem[] = [
    { label: '摸摸', icon: $r('app.media.ic_side_pet'), kind: 'action', action: 'interact' },
    { label: '喂食', icon: $r('app.media.ic_side_feed'), kind: 'sheet', sheet: 'feed' },
    { label: '玩耍', icon: $r('app.media.ic_side_play'), kind: 'sheet', sheet: 'play' },
    { label: '训练', icon: $r('app.media.ic_side_train'), kind: 'action', action: 'train' },
    { label: '洗澡', icon: $r('app.media.ic_side_bath'), kind: 'action', action: 'bath' },
    { label: '休息', icon: $r('app.media.ic_side_sleep'), kind: 'action', action: 'sleep' }
  ];
  private readonly feedOptions: FeedSheetOption[] = [
    { id: 'fish_meal', label: '鲜鱼餐', quantity: 1 },
    { id: 'grain_snack', label: '谷物点心', quantity: 1 },
    { id: 'vitamin_mix', label: '营养拼盘', quantity: 2 }
  ];
  private readonly playOptions: PlaySheetOption[] = [
    { id: 'ball', label: '弹力球', duration: 20_000 },
    { id: 'rope', label: '拉力绳', duration: 28_000 },
    { id: 'bubble', label: '泡泡追逐', duration: 35_000 }
  ];

  private decayTimerId: number = -1;
  private envTimerId: number = -1;
  // TTP223 触摸事件轮询定时器；服务端已锁存事件，因此短促脉冲不会丢失。
  private touchTimerId: number = -1;
  private touchPollInFlight: boolean = false;

  aboutToAppear(): void {
    if (this.pet.modelPath === 'burmese_bull.glb') {
      this.pet.name = '\u5c0f\u9ec4\u9e2d';
      this.pet.type = '\u5ba0\u7269';
      this.pet.image = $r('app.media.pet_duck_full');
      this.pet.modelPath = 'duck_default';
      this.pet.currentSpeech = '';
    }

    // 同步中转服务地址到 CommonConstants 配置的主机/端口，
    // 避免 PetSprite 构造时拿到旧默认值导致首次 swap 走错地址。
    PetVideoRelayService.getInstance()
      .setRelayAddress(CommonConstants.RELAY_SERVER_HOST, CommonConstants.RELAY_SERVER_PORT);

    this.applyDecayAndEmotion();
    this.extremeReactionMode = PetSensorService.getExtremeReactionMode();
    this.refreshEnvironment();

    this.decayTimerId = setInterval(() => {
      this.applyDecayAndEmotion();
    }, 30_000);

    this.envTimerId = setInterval(() => {
      this.refreshEnvironment();
    }, 18_000);

    // 首次立即读取，之后每 400ms 检查一次锁存事件，兼顾响应速度与局域网开销。
    void this.pollTtp223Touch();
    this.touchTimerId = setInterval(() => {
      void this.pollTtp223Touch();
    }, 400);
  }

  aboutToDisappear(): void {
    if (this.decayTimerId >= 0) {
      clearInterval(this.decayTimerId);
      this.decayTimerId = -1;
    }
    if (this.envTimerId >= 0) {
      clearInterval(this.envTimerId);
      this.envTimerId = -1;
    }
    if (this.touchTimerId >= 0) {
      clearInterval(this.touchTimerId);
      this.touchTimerId = -1;
    }
  }

  private applyDecayAndEmotion(): void {
    PetLifecycleService.applyNaturalDecay(this.pet);
    if (this.pet.emotion === '困倦' && this.pet.currentAction !== 'sleep') {
      this.pet.currentSpeech = '';
    }
    if (this.pet.emotion === '兴奋') {
      this.pet.currentSpeech = '';
    }
  }

  private refreshEnvironment(): void {
    this.snapshot = PetSensorService.sample();
    this.envTip = PetSensorService.applyEnvironmentImpact(this.pet, this.snapshot);
    this.envVisible = true;
    setTimeout(() => {
      this.envVisible = false;
    }, 2600);
  }

  /**
   * 轮询 PC 端 img_server.py 的 /env 端点，检测 TTP223 触摸传感器 OFF→ON 边沿。
   * 检测到一次新触摸时，触发与点击宠物图像等效的摸头交互：
   *   播放 touch.mp3 + 调用 InteractionService.pet 触发 feel_head 序列帧。
   * 边沿检测由 PetSensorService 内部维护，长按不会重复触发。
   */
  private async pollTtp223Touch(): Promise<void> {
    if (this.touchPollInFlight) {
      return;
    }
    this.touchPollInFlight = true;
    try {
      const touched: boolean = await PetSensorService.fetchTtp223Touch();
      if (!touched) {
        return;
      }
      // 仅金毛宠物响应硬件触摸（与 PetSprite 屏幕点击逻辑保持一致）
      if (!this.pet.modelPath.toLowerCase().includes('golden')) {
        return;
      }
      const ctx: common.Context = getContext(this) as common.Context;
      PetActionSoundService.getInstance().playTouchSound(ctx);
      await InteractionService.getInstance().pet(this.pet);
    } finally {
      this.touchPollInFlight = false;
    }
  }

  private openDevPanel(): void {
    this.devSheetOffsetY = 96;
    this.feedSheetVisible = false;
    this.playSheetVisible = false;
    this.devPanelVisible = true;
    setTimeout(() => {
      this.devSheetOffsetY = 0;
    }, 16);
  }

  private closeDevPanel(): void {
    if (!this.devPanelVisible) {
      return;
    }
    this.devSheetOffsetY = 96;
    setTimeout(() => {
      this.devPanelVisible = false;
    }, 180);
  }

  private showRelayDiag(text: string, durationMs: number = 2400): void {
    this.relayDiagTip = text;
    this.relayDiagVisible = true;
    setTimeout(() => {
      this.relayDiagVisible = false;
    }, durationMs);
  }

  private async pingRelayService(): Promise<void> {
    if (this.relayPingBusy) {
      return;
    }
    this.relayPingBusy = true;
    this.showRelayDiag('正在探测中转服务...', 3000);
    const ok: boolean = await PetVideoRelayService.getInstance().ping();
    this.relayPingBusy = false;
    if (ok) {
      this.showRelayDiag(`中转服务已连通 (${CommonConstants.RELAY_SERVER_HOST}:${CommonConstants.RELAY_SERVER_PORT})`, 3000);
    } else {
      this.showRelayDiag(`中转服务不可达，请检查 relay_server.py 与 IP 配置`, 3600);
    }
  }

  private async triggerRelayTestSwap(): Promise<void> {
    if (this.relayPingBusy) {
      return;
    }
    this.relayPingBusy = true;
    this.showRelayDiag('正在请求切换到 待机 素材...', 3000);
    // 强制触发，绕过 lastRelayedAction 去重；即使当前已是 待机 也能立刻刷新目标目录
    PetVideoRelayService.getInstance().forceSwapByAction('idle', this.resolveRelayProfile());
    setTimeout(() => {
      this.relayPingBusy = false;
      this.showRelayDiag('已发送切换请求，请检查电脑端中转服务的素材目录', 3600);
    }, 800);
  }

  private resolveRelayProfile(): string {
    const modelPath: string = this.pet.modelPath.trim();
    const type: string = this.pet.type.trim();
    const name: string = this.pet.name.trim();
    if (modelPath.length > 0 && type.length > 0 && name.length > 0) {
      return `${modelPath}|${type}|${name}`;
    }
    if (modelPath.length > 0 && type.length > 0) {
      return `${modelPath}|${type}`;
    }
    if (modelPath.length > 0) {
      return modelPath;
    }
    if (type.length > 0 && name.length > 0) {
      return `${type}|${name}`;
    }
    return type.length > 0 ? type : name;
  }

  /**
   * 应用开发者覆盖：设置温湿度为过高值并立即触发环境感知
   */
  private applyDevOverride(temperature: number | null, humidity: number | null): void {
    PetSensorService.setDevOverride(temperature, humidity);
    this.snapshot = PetSensorService.getLatest();
    this.envTip = PetSensorService.applyEnvironmentImpact(this.pet, this.snapshot);
    this.envVisible = true;
    setTimeout(() => {
      this.envVisible = false;
    }, 3000);
    this.closeDevPanel();
  }

  /**
   * 清除开发者覆盖：环境恢复正常，宠物从过热/过湿状态恢复
   */
  private clearDevOverrideAction(): void {
    PetSensorService.clearDevOverride();
    this.snapshot = PetSensorService.getLatest();
    this.envTip = PetSensorService.applyEnvironmentImpact(this.pet, this.snapshot);
    this.envVisible = true;
    setTimeout(() => {
      this.envVisible = false;
    }, 2600);
    this.closeDevPanel();
  }

  /**
   * 切换过热/过湿反应模式（自动 / 手动）
   */
  private setExtremeReactionMode(mode: 'auto' | 'manual'): void {
    if (this.extremeReactionMode === mode) {
      return;
    }
    this.extremeReactionMode = mode;
    PetSensorService.setExtremeReactionMode(mode);
    this.snapshot = PetSensorService.getLatest();
    this.envTip = PetSensorService.applyEnvironmentImpact(this.pet, this.snapshot);
    this.envVisible = true;
    setTimeout(() => {
      this.envVisible = false;
    }, 2600);
  }

  /**
   * 手动触发过热/过湿反应：MP3 一遍 + 图片两遍 + 介绍 + 回待机，
   * 不受环境刷新打断。
   */
  private runManualExtremeReaction(action: 'hot' | 'wet'): void {
    if (this.extremeReactionMode !== 'manual') {
      this.envTip = '请先切换为手动模式';
      this.envVisible = true;
      setTimeout(() => {
        this.envVisible = false;
      }, 2000);
      return;
    }
    if (this.pet.currentAction === 'hot' || this.pet.currentAction === 'wet') {
      this.envTip = '宠物正在反应中，请稍候';
      this.envVisible = true;
      setTimeout(() => {
        this.envVisible = false;
      }, 2000);
      return;
    }
    PetSensorService.triggerManualReaction(this.pet, action);
    this.snapshot = PetSensorService.getLatest();
    this.envTip = action === 'hot' ? '已手动触发过热反应' : '已手动触发过湿反应';
    this.envVisible = true;
    setTimeout(() => {
      this.envVisible = false;
    }, 2600);
  }

  @Builder
  private SideActionRail() {
    Column({ space: 10 }) {
      this.SideRailToggleButton();

      if (this.sideRailExpanded) {
        ForEach(this.sideActionItems, (item: SideActionItem) => {
          this.SideActionButton(item);
        }, (item: SideActionItem) => item.label);
      }
    }
    .padding({ top: 12, bottom: 12, left: 10, right: 10 })
    .backgroundColor('rgba(6, 33, 55, 0.9)')
    .borderRadius(16)
    .border({ width: 1, color: 'rgba(143, 217, 239, 0.36)' })
    .shadow({ radius: 8, color: '#10000000', offsetX: 0, offsetY: 2 })
    .animation({ duration: 180, curve: Curve.EaseInOut });
  }

  @Builder
  private SideRailToggleButton() {
    Text(this.sideRailExpanded ? '收起' : '展开')
      .fontSize(11)
      .fontColor('#FFFFFF')
      .width(52)
      .height(28)
      .textAlign(TextAlign.Center)
      .backgroundColor('rgba(8, 148, 189, 0.30)')
      .borderRadius(10)
      .onClick(() => {
        this.sideRailExpanded = !this.sideRailExpanded;
      })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 });
  }

  @Builder
  private SideActionButton(item: SideActionItem) {
    Column({ space: 4 }) {
      Image(item.icon)
        .width(22)
        .height(22);

      Text(item.label)
        .fontSize(11)
        .fontColor('#FFFFFF');
    }
    .width(52)
    .padding({ top: 8, bottom: 8 })
    .backgroundColor('rgba(8, 148, 189, 0.18)')
    .borderRadius(12)
    .onClick(() => {
      this.handleSideAction(item);
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 });
  }

  private handleSideAction(item: SideActionItem): void {
    if (item.kind === 'sheet' && item.sheet) {
      this.openActionSheet(item.sheet);
      return;
    }

    if (item.kind === 'route' && item.route) {
      router.pushUrl({ url: item.route });
      return;
    }

    if (item.kind === 'action' && item.action) {
      void this.runSideAction(item.action);
    }
  }

  private openActionSheet(sheet: 'feed' | 'play'): void {
    this.actionSheetOffsetY = 96;
    if (sheet === 'feed') {
      this.playSheetVisible = false;
      this.feedSheetVisible = true;
    } else {
      this.feedSheetVisible = false;
      this.playSheetVisible = true;
    }
    setTimeout(() => {
      this.actionSheetOffsetY = 0;
    }, 16);
  }

  private closeActionSheet(): void {
    if (!this.feedSheetVisible && !this.playSheetVisible) {
      return;
    }
    this.actionSheetOffsetY = 96;
    setTimeout(() => {
      this.feedSheetVisible = false;
      this.playSheetVisible = false;
    }, 180);
  }

  private async runSideAction(action: 'interact' | 'train' | 'bath' | 'sleep'): Promise<void> {
    const service: InteractionService = InteractionService.getInstance();
    if (action === 'interact') {
      await service.pet(this.pet);
      return;
    }
    if (action === 'sleep') {
      await service.sleep(this.pet);
      return;
    }
    if (action === 'bath') {
      await service.bath(this.pet);
      return;
    }
    await service.train(this.pet, 'sit');
  }

  private isFeedSelected(id: string): boolean {
    return this.selectedFeedId === id;
  }

  private isPlaySelected(id: string): boolean {
    return this.selectedPlayId === id;
  }

  private async confirmFeedAction(): Promise<void> {
    const selected: FeedSheetOption | undefined = this.feedOptions.find((item: FeedSheetOption) => item.id === this.selectedFeedId);
    if (!selected) {
      return;
    }
    await InteractionService.getInstance().feed(this.pet, { foodId: selected.id, quantity: selected.quantity });
    this.closeActionSheet();
  }

  private async confirmPlayAction(): Promise<void> {
    const selected: PlaySheetOption | undefined = this.playOptions.find((item: PlaySheetOption) => item.id === this.selectedPlayId);
    if (!selected) {
      return;
    }
    await InteractionService.getInstance().play(this.pet, { toyId: selected.id, duration: selected.duration });
    this.closeActionSheet();
  }

  @Builder
  private FeedActionSheet() {
    Column({ space: 10 }) {
      Row() {
        Text('喂食选择')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF');
        Blank();
        Text('收起')
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.72)')
          .onClick(() => {
            this.closeActionSheet();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 });
      }
      .width('100%');

      ForEach(this.feedOptions, (item: FeedSheetOption) => {
        Row() {
          Row({ space: 8 }) {
            Image($r('app.media.ic_side_feed'))
              .width(16)
              .height(16);
            Text(item.label)
              .fontSize(13)
              .fontColor('#FFFFFF');
          }
          Blank();
          Text(this.isFeedSelected(item.id) ? '已选中' : '选择')
            .fontSize(12)
            .fontColor(this.isFeedSelected(item.id) ? '#8FD9EF' : 'rgba(255,255,255,0.62)');
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(this.isFeedSelected(item.id) ? 'rgba(8,148,189,0.22)' : 'rgba(255,255,255,0.08)')
        .borderRadius(12)
        .onClick(() => {
          this.selectedFeedId = item.id;
        })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 });
      }, (item: FeedSheetOption) => item.id);

      Button('确认喂食')
        .type(ButtonType.Normal)
        .width('100%')
        .height(42)
        .backgroundColor('#0894BD')
        .fontColor('#FFFFFF')
        .fontSize(14)
        .borderRadius(12)
        .onClick(() => {
          void this.confirmFeedAction();
        });
    }
    .width('100%')
    .padding(14)
    .backgroundColor('rgba(6, 33, 55, 0.95)')
    .borderRadius(16)
    .border({ width: 1, color: 'rgba(143,217,239,0.30)' })
    .translate({ y: this.actionSheetOffsetY })
    .animation({ duration: 180, curve: Curve.EaseOut });
  }

  @Builder
  private PlayActionSheet() {
    Column({ space: 10 }) {
      Row() {
        Text('玩耍选择')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF');
        Blank();
        Text('收起')
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.72)')
          .onClick(() => {
            this.closeActionSheet();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 });
      }
      .width('100%');

      ForEach(this.playOptions, (item: PlaySheetOption) => {
        Row() {
          Row({ space: 8 }) {
            Image($r('app.media.ic_side_play'))
              .width(16)
              .height(16);
            Text(item.label)
              .fontSize(13)
              .fontColor('#FFFFFF');
          }
          Blank();
          Text(this.isPlaySelected(item.id) ? '已选中' : '选择')
            .fontSize(12)
            .fontColor(this.isPlaySelected(item.id) ? '#8FD9EF' : 'rgba(255,255,255,0.62)');
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(this.isPlaySelected(item.id) ? 'rgba(8,148,189,0.22)' : 'rgba(255,255,255,0.08)')
        .borderRadius(12)
        .onClick(() => {
          this.selectedPlayId = item.id;
        })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 });
      }, (item: PlaySheetOption) => item.id);

      Button('确认玩耍')
        .type(ButtonType.Normal)
        .width('100%')
        .height(42)
        .backgroundColor('#0894BD')
        .fontColor('#FFFFFF')
        .fontSize(14)
        .borderRadius(12)
        .onClick(() => {
          void this.confirmPlayAction();
        });
    }
    .width('100%')
    .padding(14)
    .backgroundColor('rgba(6, 33, 55, 0.95)')
    .borderRadius(16)
    .border({ width: 1, color: 'rgba(143,217,239,0.30)' })
    .translate({ y: this.actionSheetOffsetY })
    .animation({ duration: 180, curve: Curve.EaseOut });
  }

  @Builder
  private DevPanelSheet() {
    Column({ space: 10 }) {
      Row() {
        Text('开发者面板')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF');
        Blank();
        Text('收起')
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.72)')
          .onClick(() => {
            this.closeDevPanel();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 });
      }
      .width('100%');

      Text('用于测试过热/过湿触发链路，设置后立即生效')
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.6)')
        .width('100%');

      Column({ space: 8 }) {
        Row() {
          Text('过热/过湿反应')
            .fontSize(13)
            .fontColor('#FFFFFF');
          Blank();
          Text(this.extremeReactionMode === 'auto' ? '自动触发' : '手动触发')
            .fontSize(11)
            .fontColor(this.extremeReactionMode === 'auto' ? 'rgba(143,217,239,0.85)' : 'rgba(255,200,120,0.85)');
        }
        .width('100%');

        Row({ space: 0 }) {
          Text('自动触发')
            .layoutWeight(1)
            .height(32)
            .textAlign(TextAlign.Center)
            .fontSize(13)
            .fontColor(this.extremeReactionMode === 'auto' ? '#FFFFFF' : 'rgba(255,255,255,0.7)')
            .backgroundColor(this.extremeReactionMode === 'auto' ? '#0894BD' : 'rgba(255,255,255,0.08)')
            .borderRadius({ topLeft: 10, bottomLeft: 10, topRight: 0, bottomRight: 0 })
            .onClick(() => {
              this.setExtremeReactionMode('auto');
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 });
          Text('手动触发')
            .layoutWeight(1)
            .height(32)
            .textAlign(TextAlign.Center)
            .fontSize(13)
            .fontColor(this.extremeReactionMode === 'manual' ? '#FFFFFF' : 'rgba(255,255,255,0.7)')
            .backgroundColor(this.extremeReactionMode === 'manual' ? '#FFB74D' : 'rgba(255,255,255,0.08)')
            .borderRadius({ topLeft: 0, bottomLeft: 0, topRight: 10, bottomRight: 10 })
            .onClick(() => {
              this.setExtremeReactionMode('manual');
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 });
        }
        .width('100%')
        .borderRadius(10)
        .backgroundColor('rgba(255,255,255,0.04)');

        Text(this.extremeReactionMode === 'auto'
          ? '已启用 · 超阈值会自动触发动作'
          : '已启用 · 超阈值需点击下方按钮触发')
          .fontSize(11)
          .fontColor(this.extremeReactionMode === 'auto' ? 'rgba(143,217,239,0.85)' : 'rgba(255,200,120,0.85)')
          .width('100%');
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor(this.extremeReactionMode === 'auto' ? 'rgba(8,148,189,0.18)' : 'rgba(255,183,77,0.18)')
      .borderRadius(12);

      Row() {
        Column({ space: 4 }) {
          Text('设置温度过高')
            .fontSize(13)
            .fontColor('#FFFFFF');
          Text('35°C · 触发过热')
            .fontSize(11)
            .fontColor('rgba(255,152,0,0.85)');
        }
        .alignItems(HorizontalAlign.Start);

        Blank();

        Text(PetSensorService.isDevOverridden() && this.snapshot.temperature >= 32 ? '已激活' : '设置')
          .fontSize(12)
          .fontColor(PetSensorService.isDevOverridden() && this.snapshot.temperature >= 32 ? '#FF9800' : 'rgba(255,255,255,0.62)');
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor('rgba(255,152,0,0.18)')
      .borderRadius(12)
      .onClick(() => {
        this.applyDevOverride(35, null);
      })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 });

      Row() {
        Column({ space: 4 }) {
          Text('设置湿度过高')
            .fontSize(13)
            .fontColor('#FFFFFF');
          Text('85% · 触发过湿')
            .fontSize(11)
            .fontColor('rgba(143,217,239,0.85)');
        }
        .alignItems(HorizontalAlign.Start);

        Blank();

        Text(PetSensorService.isDevOverridden() && this.snapshot.humidity >= 80 ? '已激活' : '设置')
          .fontSize(12)
          .fontColor(PetSensorService.isDevOverridden() && this.snapshot.humidity >= 80 ? '#8FD9EF' : 'rgba(255,255,255,0.62)');
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor('rgba(8,148,189,0.22)')
      .borderRadius(12)
      .onClick(() => {
        this.applyDevOverride(null, 85);
      })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 });

      if (this.extremeReactionMode === 'manual') {
        Row({ space: 10 }) {
          Button('触发过热')
            .layoutWeight(1)
            .height(40)
            .type(ButtonType.Normal)
            .backgroundColor('rgba(255,152,0,0.85)')
            .fontColor('#FFFFFF')
            .fontSize(13)
            .borderRadius(12)
            .onClick(() => {
              this.runManualExtremeReaction('hot');
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 });

          Button('触发过湿')
            .layoutWeight(1)
            .height(40)
            .type(ButtonType.Normal)
            .backgroundColor('rgba(8,148,189,0.85)')
            .fontColor('#FFFFFF')
            .fontSize(13)
            .borderRadius(12)
            .onClick(() => {
              this.runManualExtremeReaction('wet');
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 });
        }
        .width('100%');
      }

      if (PetSensorService.isDevOverridden()) {
        Button('清除开发者覆盖')
          .type(ButtonType.Normal)
          .width('100%')
          .height(42)
          .backgroundColor('#3A4A55')
          .fontColor('#FFFFFF')
          .fontSize(14)
          .borderRadius(12)
          .onClick(() => {
            this.clearDevOverrideAction();
          });
      }

      Divider()
        .color('rgba(255,255,255,0.18)')
        .width('100%')
        .margin({ top: 4, bottom: 4 });

      Text('中转服务诊断')
        .fontSize(13)
        .fontColor('#FFFFFF')
        .width('100%')
        .margin({ top: 4 });

      Text(`地址: ${CommonConstants.RELAY_SERVER_HOST}:${CommonConstants.RELAY_SERVER_PORT}`)
        .fontSize(11)
        .fontColor('rgba(255,255,255,0.62)')
        .width('100%');

      if (this.relayDiagVisible) {
        Text(this.relayDiagTip)
          .fontSize(11)
          .fontColor('#8FD9EF')
          .width('100%')
          .margin({ top: 4 });
      }

      Row({ space: 10 }) {
        Button(this.relayPingBusy ? '探测中...' : '探测中转服务')
          .layoutWeight(1)
          .height(40)
          .type(ButtonType.Normal)
          .backgroundColor(this.relayPingBusy ? '#3A4A55' : '#0894BD')
          .fontColor('#FFFFFF')
          .fontSize(13)
          .borderRadius(12)
          .enabled(!this.relayPingBusy)
          .onClick(() => {
            void this.pingRelayService();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 });

        Button('试切到 待机 素材')
          .layoutWeight(1)
          .height(40)
          .type(ButtonType.Normal)
          .backgroundColor(this.relayPingBusy ? '#3A4A55' : '#0894BD')
          .fontColor('#FFFFFF')
          .fontSize(13)
          .borderRadius(12)
          .enabled(!this.relayPingBusy)
          .onClick(() => {
            void this.triggerRelayTestSwap();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 });
      }
      .width('100%');
    }
    .width('100%')
    .padding(14)
    .backgroundColor('rgba(6, 33, 55, 0.95)')
    .borderRadius(16)
    .border({ width: 1, color: 'rgba(143,217,239,0.30)' })
    .translate({ y: this.devSheetOffsetY })
    .animation({ duration: 180, curve: Curve.EaseOut });
  }

  @Builder
  private BackgroundLayer() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            ['#08283C', 0],
            ['#0B3246', 0.45],
            ['#102C3B', 1]
          ]
        });

      Circle({ width: 320, height: 320 })
        .fill('rgba(8, 148, 189, 0.22)')
        .position({ x: -80, y: -120 });

      Circle({ width: 260, height: 260 })
        .fill('rgba(255, 255, 255, 0.08)')
        .position({ x: 230, y: 120 });

      Circle({ width: 420, height: 420 })
        .fill('rgba(8, 148, 189, 0.12)')
        .position({ x: 120, y: 520 });

      Ellipse()
        .width(280)
        .height(80)
        .fill('rgba(255, 255, 255, 0.08)')
        .position({ x: 40, y: 520 });

      Row({ space: 10 }) {
        Circle({ width: 8, height: 8 }).fill('rgba(255,255,255,0.28)')
        Circle({ width: 6, height: 6 }).fill('rgba(255,255,255,0.18)')
        Circle({ width: 4, height: 4 }).fill('rgba(255,255,255,0.12)')
      }
      .position({ x: 36, y: 220 });

      Row({ space: 12 }) {
        Circle({ width: 6, height: 6 }).fill('rgba(255,255,255,0.2)')
        Circle({ width: 9, height: 9 }).fill('rgba(8,148,189,0.35)')
        Circle({ width: 6, height: 6 }).fill('rgba(255,255,255,0.16)')
      }
      .position({ x: 280, y: 260 });
    }
    .width('100%')
    .height('100%');
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      this.BackgroundLayer();

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

          Blank();

          Row({ space: 8 }) {
            Text(`舒适度 ${this.snapshot.comfortScore}%`)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor('rgba(8, 148, 189, 0.45)')
              .borderRadius(14);

            Stack({ alignContent: Alignment.Center }) {
              Image($r('app.media.ic_dev_tool'))
                .width(18)
                .height(18);
            }
            .width(32)
            .height(32)
            .backgroundColor(PetSensorService.isDevOverridden() ? 'rgba(255, 152, 0, 0.55)' : 'rgba(8, 148, 189, 0.45)')
            .borderRadius(16)
            .scale({ x: this.devBtnScale, y: this.devBtnScale })
            .animation({ duration: 150 })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.devBtnScale = 0.9;
              }
              if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.devBtnScale = 1;
              }
            })
            .onClick(() => {
              this.openDevPanel();
            });
          }
          .alignItems(VerticalAlign.Center);
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16 })
        .zIndex(20);

        PetStatusBar({ attributes: this.pet.attributes, personalityLabel: this.pet.resolvePersonalityLabel() });

        if (this.envVisible) {
          Text(this.envTip)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor('rgba(12, 31, 44, 0.84)')
            .borderRadius(12)
            .margin({ left: 16, right: 16, bottom: 6 })
            .animation({ duration: 220, curve: Curve.EaseInOut });
        }

        PetSprite({ pet: this.pet });

        PetActionMenu({ pet: this.pet })
          .zIndex(20);
      }
      .width('100%')
      .height('100%');

      Row() {
        this.SideActionRail();
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 12 })
      .margin({ top: 172 })
      .zIndex(30);

      if (this.feedSheetVisible || this.playSheetVisible) {
        Column() {
          Column()
            .layoutWeight(1)
            .width('100%')
            .onClick(() => {
              this.closeActionSheet();
            });

          if (this.feedSheetVisible) {
            this.FeedActionSheet();
          }

          if (this.playSheetVisible) {
            this.PlayActionSheet();
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 12, right: 12, bottom: 108 })
        .zIndex(40);
      }

      if (this.devPanelVisible) {
        Column() {
          Column()
            .layoutWeight(1)
            .width('100%')
            .onClick(() => {
              this.closeDevPanel();
            });

          this.DevPanelSheet();
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 12, right: 12, bottom: 108 })
        .zIndex(50);
      }
    }
    .width('100%')
    .height('100%');
  }
}
