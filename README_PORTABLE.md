# 可移交项目说明

这是从当前工作区抽取的可移交副本，仅保留鸿蒙应用源码、应用运行所需资源和构建配置；未包含 Git 历史、IDE 配置、依赖缓存、临时文件、设备固件和编译结果。

## 在其他电脑上运行鸿蒙应用

1. 安装与 `build-profile.json5` 中 `6.0.2(22)` 对应的 DevEco Studio、HarmonyOS SDK 和 Node.js/ohpm 工具链。
2. 用 DevEco Studio 打开本目录，不要打开 `entry` 子目录。
3. 等待依赖解析完成，选择 `default` 产品和 `entry` 模块，连接模拟器或真机后运行。
4. 如需连接电脑上的环境服务或素材中转服务，修改 `entry/src/main/ets/common/constants/CommonConstants.ets` 中的 `ENV_SERVER_HOST`，并将同一地址加入 `entry/src/main/resources/base/profile/network_config.json` 的明文网络白名单。

模拟器与服务运行在同一台电脑时可使用 `127.0.0.1`；真机运行时应改成电脑在同一局域网中的 IPv4 地址，并放行 6790、6791 端口。服务端脚本不在此副本中，环境数据和素材中转功能需要另外准备服务端。

## AI 配置

宠物聊天已接入真实 LLM 对话（传输层 `PetLlmClient.ets`，配置在 `CommonConstants.ets`）：

- **服务商**：StepFun（Anthropic Messages 协议兼容中转），端点 `https://api.stepfun.com/step_plan/v1/messages`，默认模型 `step-3.5-flash-2603`。
- **API Key**：当前为临时方案，写死在 `CommonConstants.LLM_API_KEY`。⚠️ 本仓库有 git 历史，Key 一旦提交并推送远端即视为泄漏，应立即在服务商侧轮换；后续应改造为安全存储（未包含在本次范围）。换其他 OpenAI/Anthropic 兼容服务只需改 `LLM_BASE_URL` 与 `LLM_MODEL` 两个常量。
- **失败回退**：未配置 Key、断网、HTTP 错误或响应异常时，全链路自动回退本地模板引擎秒回，消息带「本地」徽标，不报错不卡死。
- **多轮与记忆**：每次请求自动携带 `system（宠物人设 + 检索到的长期记忆） + 最近 10 条历史 + 当前消息`；聊天记录与宠物档案通过 Preferences 持久化，重启后恢复。
- **唤醒AI 语音按钮**：聊天页输入栏左侧宠物头像即「唤醒AI」。点击后申请麦克风权限并开启端侧语音识别（CoreSpeechKit），文字实时上屏、说完自动发送并播放 AI 回复；监听中再次点击安全取消。语音能力依赖真机（中国大陆系统镜像）与麦克风授权，模拟器或不受支持的设备会提示降级为文字输入，文字功能不受影响。

## 副本边界

已排除 `.git`、`.idea`、`.hvigor`、`.tools`、`oh_modules`、`docs`、`tools`、`outputs`、`tmp`、`entry/build`、`entry/.test`、`entry/.preview`、测试源码、本地配置和验证脚本。`entry/src/main/resources` 中的原始模型、图片和其他资源属于应用运行资源，因此保留。
