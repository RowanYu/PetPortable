import { webview } from '@kit.ArkWeb';
import { PetActionType } from '../models/PetModel';
import { common } from '@kit.AbilityKit';
import {
  isLive2DResourceUrl,
  resolveLive2DMimeType,
  resolveLive2DRawPath
} from '../services/Live2DResourceResolver';

const TAG: string = 'Live2DPetView';
const LIVE2D_SCHEME: string = 'petlive2d';

/**
 * 基于 ArkWeb Web 组件封装的真实 Live2D 渲染视图。
 */
@Component
export struct Live2DPetView {
  @Prop modelName: string = 'mao_pro';
  @Prop @Watch('onActionChange') action: PetActionType = 'idle';
  @State private isWebReady: boolean = false;
  @State private loadError: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    try {
      const scheme: webview.WebCustomScheme = {
        schemeName: LIVE2D_SCHEME,
        isSupportCORS: true,
        isSupportFetch: true,
        isStandard: true,
        isLocal: true,
        isSecure: true,
        isCodeCacheSupported: false
      };
      webview.WebviewController.customizeSchemes([scheme]);
      console.info(`${TAG} custom scheme registered: ${LIVE2D_SCHEME}`);
    } catch (error) {
      // ArkWeb 全局只需注册一次；重复进入页面时可能返回“已注册”错误。
      console.info(`${TAG} custom scheme already available: ${(error as Error).message}`);
    }
  }

  build() {
    Stack() {
      Web({ src: $rawfile('live2d/index.html'), controller: this.controller })
        .onPageEnd(() => this.onPageEnd())
        .onErrorReceive((e) => this.onWebError(e))
        .onInterceptRequest((event) => {
          return this.interceptLive2DResource(event.request.getRequestUrl());
        })
        .onControllerAttached(() => {
          console.info(`${TAG} Web controller attached`);
        })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .imageAccess(true)
        .onlineImageAccess(true)
        .geolocationAccess(false)
        .initialScale(100);

      if (!this.isWebReady) {
        Column({ space: 6 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color('#089EBD');
          Text(this.loadError.length > 0 ? this.loadError : '正在加载 Live2D 模型...')
            .fontSize(11)
            .fontColor('#081E2A')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(255,255,255,0.6)')
        .borderRadius(12);
      }
    }
    .width('100%')
    .height('100%');
  }

  private getContext(): common.Context | undefined {
    try {
      return this.getUIContext().getHostContext() as common.Context;
    } catch (e) {
      return undefined;
    }
  }

  private onPageEnd(): void {
    console.info(`${TAG} page loaded, init model: ${this.modelName}`);
    this.isWebReady = true;
    // 延迟 100ms 等待页面脚本完成初始化。
    setTimeout(() => {
      const script: string = `window.initLive2D && window.initLive2D('${this.modelName}');`;
      this.controller.runJavaScript(script)
        .then(() => {
          console.info(`${TAG} initLive2D dispatched for ${this.modelName}`);
        })
        .catch((e: Error) => {
          console.warn(`${TAG} initLive2D script failed: ${e.message}`);
          this.loadError = `初始化失败: ${e.message}`;
        });
    }, 100);
  }

  private interceptLive2DResource(url: string): WebResourceResponse | null {
    if (!isLive2DResourceUrl(url)) {
      return null;
    }

    const rawPath: string | null = resolveLive2DRawPath(url);
    if (!rawPath) {
      console.warn(`${TAG} rejected invalid Live2D resource URL: ${url}`);
      return this.createErrorResponse(400, `非法 Live2D 资源路径: ${url}`);
    }

    const context: common.Context | undefined = this.getContext();
    if (!context) {
      console.warn(`${TAG} host context unavailable for ${rawPath}`);
      return this.createErrorResponse(500, `无法读取 Live2D 资源: ${rawPath}`);
    }

    try {
      const data: Uint8Array = context.resourceManager.getRawFileContentSync(rawPath);
      const content: ArrayBuffer = new ArrayBuffer(data.byteLength);
      new Uint8Array(content).set(data);

      const response: WebResourceResponse = new WebResourceResponse();
      response.setResponseData(content);
      response.setResponseEncoding('utf-8');
      response.setResponseMimeType(resolveLive2DMimeType(rawPath));
      response.setResponseHeader([
        { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' },
        { headerKey: 'Cache-Control', headerValue: 'no-cache' }
      ]);
      response.setResponseCode(200);
      response.setReasonMessage('OK');
      console.info(`${TAG} rawfile response: ${rawPath} -> ${data.byteLength} bytes`);
      return response;
    } catch (error) {
      const message: string = (error as Error).message;
      console.warn(`${TAG} rawfile missing: ${rawPath}, ${message}`);
      return this.createErrorResponse(404, `Live2D 资源不存在: ${rawPath}`);
    }
  }

  private createErrorResponse(code: number, message: string): WebResourceResponse {
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseData(message);
    response.setResponseEncoding('utf-8');
    response.setResponseMimeType('text/plain');
    response.setResponseHeader([
      { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' },
      { headerKey: 'Cache-Control', headerValue: 'no-cache' }
    ]);
    response.setResponseCode(code);
    response.setReasonMessage(code === 400 ? 'Bad Request' : code === 404 ? 'Not Found' : 'Internal Server Error');
    return response;
  }

  private onActionChange(): void {
    this.dispatchAction(this.action);
  }

  private dispatchAction(action: PetActionType): void {
    if (!this.isWebReady) {
      console.info(`${TAG} action ${action} queued (web not ready)`);
      return;
    }
    const script: string = `window.setLive2DAction && window.setLive2DAction('${action}');`;
    this.controller.runJavaScript(script)
      .then(() => {
        console.info(`${TAG} action dispatched: ${action}`);
      })
      .catch((e: Error) => {
        console.warn(`${TAG} action dispatch failed: ${e.message}`);
      });
  }

  private onWebError(e: object): void {
    const errStr: string = JSON.stringify(e);
    console.warn(`${TAG} web error: ${errStr}`);
    this.loadError = `Web 错误: ${errStr.substring(0, 80)}`;
  }

  aboutToDisappear(): void {
    try {
      this.controller.runJavaScript('window.destroyLive2D && window.destroyLive2D();');
    } catch (e) {
      // 容错
    }
  }
}
