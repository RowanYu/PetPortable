import { router } from '@kit.ArkUI';
import { CommonConstants } from '../constants/CommonConstants';
import { PetModel } from '../models/PetModel';

interface PetMenuItem {
  label: string;
  icon: Resource;
  route: string;
}

@Component
export struct PetActionMenu {
  @ObjectLink pet: PetModel;

  private readonly menuItems: PetMenuItem[] = [
    { label: '聊天', icon: $r('app.media.ic_menu_chat'), route: 'pages/ChatPage' },
    { label: '梦境', icon: $r('app.media.ic_menu_dream'), route: 'pages/DreamDiaryPage' },
    { label: '环境', icon: $r('app.media.ic_menu_sensor'), route: 'pages/SensorPanelPage' },
    { label: '档案', icon: $r('app.media.ic_menu_profile'), route: 'pages/PetProfilePage' },
    { label: '设置', icon: $r('app.media.ic_menu_setting'), route: 'pages/PersonalPage' }
  ];

  build() {
    Scroll() {
      Row({ space: 10 }) {
        ForEach(this.menuItems, (item: PetMenuItem) => {
          this.MenuItem(item);
        }, (item: PetMenuItem) => item.label);
      }
      .padding({ left: 16, right: 16 });
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .padding({ top: 12, bottom: 24 })
    .backgroundColor('#2A3641')
    .borderRadius({ topLeft: 24, topRight: 24 })
    .shadow({ radius: 20, color: '#10000000', offsetX: 0, offsetY: -5 })
    .scrollBar(BarState.Off);
  }

  @Builder
  private MenuItem(item: PetMenuItem) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 40, height: 40 })
          .fill('rgba(8, 148, 189, 0.22)');
        Image(item.icon)
          .width(20)
          .height(20);
      }

      Text(item.label)
        .fontSize(12)
        .fontColor('#FFFFFF');
    }
    .width(56)
    .onClick(() => {
      this.handleMenuItem(item);
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: CommonConstants.CLICK_SCALE });
  }

  private handleMenuItem(item: PetMenuItem): void {
    router.pushUrl({ url: item.route });
  }
}
