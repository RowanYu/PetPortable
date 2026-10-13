import { PetAttributes } from '../models/PetModel';
import { CommonConstants } from '../constants/CommonConstants';

@Component
export struct PetStatusBar {
  @ObjectLink attributes: PetAttributes;
  @Prop personalityLabel: string = '温顺';

  build() {
    Column({ space: 8 }) {
      Row({ space: CommonConstants.SPACE_12 }) {
        this.AttributeItem('健康', `${this.attributes.health}`)
        this.AttributeItem('心情', `${this.attributes.mood}`)
        this.AttributeItem('精力', `${this.attributes.energy}`)
      }
      Row({ space: CommonConstants.SPACE_12 }) {
        this.AttributeItem('亲密', `${this.attributes.intimacy}`)
        this.AttributeItem('顺从', `${this.attributes.obedience}`)
        this.AttributeItem('性格', this.personalityLabel)
      }
    }
    .width('100%')
    .padding(CommonConstants.SPACE_16)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  AttributeItem(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.75)')
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
    }
    .width('30%')
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor('#2A3641') // 深灰蓝
    .borderRadius(CommonConstants.BORDER_RADIUS_16)
    .shadow({ radius: 4, color: '#10000000', offsetX: 0, offsetY: 2 })
  }
}
