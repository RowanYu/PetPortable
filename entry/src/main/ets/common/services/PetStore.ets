import { PetModel } from '../models/PetModel';

/**
 * 宠物档案存储服务
 * 统一管理多只宠物列表与当前选中宠物，保证「宠物档案」页面可切换查看
 * - petList：所有宠物列表
 * - currentPetIndex：当前选中宠物在列表中的索引
 * - currentPet：当前选中宠物对象（与历史页面兼容，由本服务同步维护）
 */
export class PetStore {
  private static readonly KEY_PET_LIST: string = 'petList';
  private static readonly KEY_CURRENT_INDEX: string = 'currentPetIndex';
  private static readonly KEY_CURRENT_PET: string = 'currentPet';

  private constructor() {
    // 工具类禁止实例化
  }

  /**
   * 初始化宠物列表为默认宠物（仅当列表为空时调用）
   */
  private static ensureDefault(): PetModel[] {
    const list: PetModel[] | undefined = AppStorage.get<PetModel[]>(PetStore.KEY_PET_LIST);
    if (list && list.length > 0) {
      return list;
    }
    const defaultPet: PetModel = new PetModel('小黄鸭', '宠物', $r('app.media.pet_duck_full'), 'duck_default');
    const newList: PetModel[] = [defaultPet];
    AppStorage.setOrCreate(PetStore.KEY_PET_LIST, newList);
    AppStorage.setOrCreate(PetStore.KEY_CURRENT_INDEX, 0);
    AppStorage.setOrCreate(PetStore.KEY_CURRENT_PET, defaultPet);
    return newList;
  }

  /**
   * 获取宠物列表
   */
  static getList(): PetModel[] {
    return PetStore.ensureDefault();
  }

  /**
   * 获取当前选中宠物索引
   */
  static getCurrentIndex(): number {
    PetStore.ensureDefault();
    const idx: number | undefined = AppStorage.get<number>(PetStore.KEY_CURRENT_INDEX);
    if (idx === undefined || idx === null || idx < 0) {
      return 0;
    }
    const list: PetModel[] = PetStore.getList();
    if (idx >= list.length) {
      return list.length - 1;
    }
    return idx;
  }

  /**
   * 获取当前选中宠物
   */
  static getCurrent(): PetModel {
    const list: PetModel[] = PetStore.getList();
    const idx: number = PetStore.getCurrentIndex();
    if (idx < 0 || idx >= list.length) {
      return list[0];
    }
    return list[idx];
  }

  /**
   * 添加新宠物：追加到列表末尾并设为当前选中
   */
  static addPet(pet: PetModel): void {
    const list: PetModel[] = PetStore.getList();
    const newList: PetModel[] = list.concat([pet]);
    const newIndex: number = newList.length - 1;
    AppStorage.setOrCreate(PetStore.KEY_PET_LIST, newList);
    AppStorage.setOrCreate(PetStore.KEY_CURRENT_INDEX, newIndex);
    AppStorage.setOrCreate(PetStore.KEY_CURRENT_PET, pet);
  }

  /**
   * 根据索引切换当前选中宠物
   */
  static switchByIndex(index: number): void {
    const list: PetModel[] = PetStore.getList();
    if (index < 0 || index >= list.length) {
      return;
    }
    AppStorage.setOrCreate(PetStore.KEY_CURRENT_INDEX, index);
    AppStorage.setOrCreate(PetStore.KEY_CURRENT_PET, list[index]);
  }

  /**
   * 删除指定索引的宠物，删除后自动选中剩余位置（默认 0）
   */
  static removeAt(index: number): void {
    const list: PetModel[] = PetStore.getList();
    if (index < 0 || index >= list.length) {
      return;
    }
    const newList: PetModel[] = list.slice(0, index).concat(list.slice(index + 1));
    if (newList.length === 0) {
      // 删除后列表为空：清空当前宠物索引，保留空列表
      AppStorage.setOrCreate(PetStore.KEY_PET_LIST, newList);
      AppStorage.setOrCreate(PetStore.KEY_CURRENT_INDEX, -1);
      AppStorage.setOrCreate(PetStore.KEY_CURRENT_PET, new PetModel('', '', undefined, ''));
      return;
    }
    const newIndex: number = index >= newList.length ? newList.length - 1 : index;
    AppStorage.setOrCreate(PetStore.KEY_PET_LIST, newList);
    AppStorage.setOrCreate(PetStore.KEY_CURRENT_INDEX, newIndex);
    AppStorage.setOrCreate(PetStore.KEY_CURRENT_PET, newList[newIndex]);
  }

  /**
   * 用恢复出的列表整体替换当前列表，并设置当前选中索引（持久化恢复专用）
   */
  static setList(list: PetModel[], index: number): void {
    AppStorage.setOrCreate(PetStore.KEY_PET_LIST, list);
    const safeIndex: number = index >= 0 && index < list.length ? index : 0;
    AppStorage.setOrCreate(PetStore.KEY_CURRENT_INDEX, safeIndex);
    AppStorage.setOrCreate(PetStore.KEY_CURRENT_PET, list[safeIndex]);
  }

  /**
   * 列表是否为空（用于切换至空态视图）
   */
  static isEmpty(): boolean {
    const list: PetModel[] | undefined = AppStorage.get<PetModel[]>(PetStore.KEY_PET_LIST);
    return !list || list.length === 0;
  }
}
