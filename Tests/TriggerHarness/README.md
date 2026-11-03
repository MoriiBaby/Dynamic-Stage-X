# TriggerHarness：真实 UIKit / XCUI 上滑回归

## 状态与边界

本机是 Linux/iSH，没有 `xcodebuild`，**没有执行 Swift 编译、UIKit 或 XCUI 回归，也不声称 alpha3 已通过**。本机仅完成 Python 语法检查、临时 PBX 工程生成、OpenStep PBX 解析/目标引用/源文件检查，以及无 Xcode 时退出码 2 / `status: not-run` 验证。云端实际结果以新生成的 xcresult 与 `trigger-summary.json` 为准。

宿主使用真实 `UIApplicationDelegate` / `UIWindowSceneDelegate`、实际 `.foregroundActive` 的 app scene。背景 `UIWindow` 有真实按钮和 pan 控件且保持 key；生产 `DXEdgeTriggerWindow(windowScene:)` 高于它一个 window level，仅设置 `isHidden = false`，从不请求成为 key。宿主文字 UI 显示回调次数、背景事件数、scene 状态及 non-key 状态。

仅编入以下两个生产文件，复制后不改写，执行前/后校验 SHA-256：

- `Sources/Presentation/DXEdgeTriggerWindow.swift`
- `Sources/Presentation/DXPresentationGeometry.swift`

不链接 Scene bridge、Core、私有框架，不伪造 `UIPanGestureRecognizer.state`，不调用 production handler / `accessibilityActivate()`。触摸由公开 `XCUIApplication` / `XCUICoordinate.press(...thenDragTo:withVelocity:thenHoldForDuration:)` 发出。测试宿主仅依赖 `onTrigger`、`triggerSide`、`isContextEnabled`；不要求 `onGestureFeedback`。

这是**前台普通 app 内真实 UIKit**验证，不是 SpringBoard 进程注入；不验证远端触摸/HID投递、越狱权限/授权、后台场景/系统上下文、真实 Home indicator 冲突或真机桥接。测试通过不能替代真机验收。

## 云端执行

前提：macOS 15、已选择 Xcode 16.4，存在可用 iOS Simulator runtime；不安装 brew/xcodegen/第三方依赖。由主代理现有云构建执行；本改动不改 workflow。

```sh
cd /path/to/repository
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
python3 ci/test_trigger_simulator.py
```

若该云机的 Xcode 路径不同，使用其已有 `DEVELOPER_DIR`，勿盲目套用上述路径。可明确固定 runtime/device：

```sh
python3 ci/test_trigger_simulator.py --runtime 18.5 --device-type 'iPhone 16 Pro'
```

默认优先 iPhone 16 Pro，选择与 SDK 兼容的最新可用 iOS runtime。每次 `simctl create` 新的独立 UUID，boot/bootstatus 后，仅向该 UUID 运行：

```sh
xcodebuild -project <temporary>/fixed/TriggerHarness.xcodeproj \
  -scheme TriggerHarness -configuration Debug -destination id=<created-UUID> \
  -destination-timeout 120 -derivedDataPath <temporary>/fixed/DerivedData \
  -resultBundlePath <evidence>/trigger-fixed.xcresult \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 120 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
```

仅有 Debug 配置。不连接/attach/install 任何真机，不 respring、不打包发布、不 merge、不 push。Xcode 会向独立模拟器安装测试 app/runner，这是模拟器测试的必要步骤。`finally` 尝试 shutdown 并 delete **本次创建的唯一模拟器**；失败也会记录，不碰共享 `booted` 模拟器。进程被外部 SIGKILL/云机强制终止时无法保证 finally 执行，可根据 summary 内 UUID 清理。

## 覆盖（14 个测试，全部需实际执行且不跳过）

1. 右边可见竖条中心，上滑 110pt。
2. 左边中心，上滑 100pt。
3. 右边中心，上滑 80pt。
4. 左边中心，上滑 140pt。
5. 右边慢上滑 110pt，请求 65pt/s。
6. 左边慢上滑 110pt，请求 65pt/s。
7. 每 30ms 同 side 再赋值，同时真实上滑不应被 cancel。
8. 40ms 坐标短按，不触发（不使用 accessibility activation）。
9. 水平 140pt，拒绝。
10. 横向 140pt / 向上 70pt 的明显横斜滑，拒绝。
11. 向下滑，拒绝。
12. 区域外真实上滑传给背景 pan，背景按钮前后可点击。
13. disabled 时在原触发位置真实上滑，触发数 0、背景 pan 数 1。
14. 左侧目标至少 44pt 宽 / 56pt 高，可见竖条中心向右偏 23pt 仍可上滑。

每个测试独立 launch，验证 app scene active、key 在背景、edge 非 key 且 level 更高；每次手势后用背景 checkpoint 按钮刷新文字计数并再次检查窗口关系。坐标来自生产 handle 的真实 accessibility frame，输入是屏幕坐标，不直接调用手势代理或 policy。

## 证据与失败语义

默认输出 `build-evidence/trigger-<UTC>-<suffix>/`；也可用 `--evidence-dir <新建或空目录>`。保存：

- `trigger-summary.json`：总体状态、版本、scene 范围、独立 UUID、清理结果。
- `trigger-commands.json`、`trigger-*.log`：完整命令、返回码、stdout/stderr。
- `trigger-fixed-sources.json`：生产文件与拷贝 SHA-256、宿主测试文件 SHA-256。
- `trigger-fixed.xcresult`：测试明细、每条测试 JSON 计数/请求坐标/速度附件、最终截图（成功与失败都保留附件）。
- `trigger-fixed-tests.json`：Xcode 16 `xcresulttool get test-results summary` 输出。
- `trigger-fixed-last-host-state.json`：最后一次启动宿主的 Documents 快照（如存在），不代表整组测试。

退出码 0 仅在 xcodebuild 成功、实际执行至少 14 个测试、失败 0、跳过 0、生产文件哈希不变且清理成功时返回。无 macOS/Xcode 返回 2，明确 `not-run`。构建失败、空结果、缺 runtime、哈希改变、测试失败、清理失败均不会伪报通过。

## 可选旧版独立对照

不阻碍主回归，默认关闭；fixed 先跑完，通过后才进行只读 git snapshot 对照：

```sh
python3 ci/test_trigger_simulator.py \
  --baseline-ref b94b66683b3351cd43cb171ed7a2551414dd6c7b
```

基线两个文件用 `git show` 取出到另一临时目录，用同一真实 XCUI 套件独立构建，保存 `trigger-baseline.*` / `trigger-baseline-*.json/log`。不 checkout/reset、不改 main/alpha2/工作树。旧版测试失败仅标记 `baseline-tests-failed`，不冒充 fixed 失败；基线构建/测试未完整执行仍使整次任务失败。不能预先声称基线必现用户问题；请读取真实测试结果。

## 仅生成，不执行

```sh
python3 ci/test_trigger_simulator.py --generate-only /tmp/dxtrigger-inspect
```

目标目录应不存在或为空；输出 `generated-only-not-executed`。可以在 Linux 上检查生成工程/哈希，但不能据此声明 UIKit/XCUI 通过。运行器仅使用 Python 标准库。
