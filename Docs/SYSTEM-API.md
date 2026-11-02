# Dynamic Stage X 系统桥接：API、证据和未验证边界

状态：**源码候选适配器已实现；没有 iOS SDK 编译、没有连接/附加设备、没有安装或真机行为验证。** 目标 iOS 15.0 起，不存在最高 OS gate。头文件存在和本机 C 测试通过不等于 iOS 15/17/以后系统已可用。

## Swift 集成合同

入口 `Sources/System/DXSystemBridge.h`，`DXSystemBridge.shared()`；保留 CONTRACT.md 的 applications/frontmost/acquire/apply/focus/release/native activation/keyboard focus PID/lock API。两个额外通知是常量而非必须新增的 Swift 调用：

- `DXSystemSceneInvalidatedNotification` = `com.tsangbaby.dynamicstagex/scene-invalidated`：主队列；object 为失效 handle，整个原生上下文丢失时为 nil。失效立刻禁用自有宿主交互，桥接自行发起幂等 release；协调器仍应关闭双窗、释放其它 handle。
- `DXSystemKeyboardFocusChangedNotification` = `com.tsangbaby.dynamicstagex/keyboard-focus-changed`：主队列；object 为实际系统焦点对应的有效本项目 handle，否则 nil。userInfo 仅有已知的 `sceneIdentifier`、`bundleIdentifier`、`processIdentifier`，**没有输入内容、没有虚构 keyboard frame**。上层仍须即时查询焦点，不能用旧通知授权新会话。

同步查询仅主线程有效；off-main applications=[]、frontmost=nil、PID=0、isLocked=YES。所有异步调用从任意线程可入，完成只在主队列、至多一次。正常确认轮询间隔 50ms；acquire/apply/release 预算各 2s，focus 1.5s，native activation 4s；apply/focus 已取得本次操作所有权后失败会追加最多 2s 的 release 清理。因此含回收的完成预算分别最多约 4s/3.5s。所有时间界限为**主线程可运行条件下的协作超时**；不能中断挂死的私有同步方法，主线程被系统阻塞时也不可能承诺硬实时完成。排队过期的非清理操作不执行；过期 release 仍在主线程恢复后做一次 best-effort 清理并返回 Timeout，不伪称已确认恢复。

### 正确时序与暂存上限

1. acquire 仅发现**已存在**的主显示应用 Scene，不私造 Scene、不选择随机第一个 Scene。按 clientProcess.bundleIdentifier + main-display membership + live process + UIApplicationSceneSettings 过滤；恰好一个才接受，多 Scene 返回 AmbiguousScene。acquire 返回准备态真实 native presentationView，不表示已交互。
2. 最多 **3 个有界租约**：两个可见 pane，另一个仅供下窗替换的暂存候选。协调器不得把三个都当正式可见窗口；旧下窗释放确认后才请求新焦点。同 App 重复租约被拒绝。
3. 把新 host 插入**已附着、非 hidden、主显示的 window** 后 apply。Frame 为主显示全局 points；桥接用自己 presenter 的原生 UITransform/UITransformer 将 Scene 原点平移到宿主局部原点，无像素缩放伪装逻辑尺寸。允许同时准备两 Scene；apply 时实际 frontmost 必须属于已注册的目标之一。
4. apply 同时确认 Scene settings、FBScene active、FBProcess foreground、presenter active/hosting、真实图层/上下文及原生事件路径门禁。只有这一步通过才可展示“已就绪”。父协调器应序列化 focus 与 geometry；忙碌拒绝不会释放被另一个 in-flight 操作持有的 handle。
5. focus 走原生 workspace 用户焦点请求，比较真实 `sceneWithFocusIncludingSpringBoard` 和 PID，同时核对 `userFocusRequestGeneration`。已经是目标焦点时不重复抢焦点。原生焦点 observer 只通报实况，不把自己的请求误当第三方上下文切换。
6. `release` 幂等；重复 release 共享进行中的恢复确认，恢复期间拒绝新 acquire/native activation。必须等待所有 release 完成再 native fallback。
7. 冷启动：NoScene → release-all/等待 → activateNative → **等待目标实际成为 frontmost 且唯一 live/active/foreground Scene 出现** → acquire 原顶窗与新底窗两者 → attach → apply → focus。原生打开会短暂切换全屏，这是有意保留的原生过渡，不是静默后台启动能力。

## 真实实现路径和 ABI 门禁

实际适配器只有一条窄路径，不是通用插件注册框架，也不依赖参考产品：

- App 清单/名称：`SBApplicationController.sharedInstance`、`allApplications`、`SBApplication.bundleIdentifier/displayName`。icon 为可空，当前不调用未证实的图标接口。
- 原生 frontmost：SpringBoard `_accessibilityFrontMostApplication` → bundleIdentifier。锁屏：`SBLockScreenManager.sharedInstance.isUILocked`；任何缺失/异常均锁定处理，不尝试解锁。
- Scene：`SBSceneManagerCoordinator.mainDisplaySceneManager` → `allScenes` / `existingSceneHandleForScene:`；全局身份回查 `FBSceneManager.sharedInstance.sceneWithIdentifier:`。每次更新重查原 scene 对象、原 process 对象、PID、bundle、registry owner；相同 PID 字符串并不足够。
- Host：自己创建 `UIScenePresentationManager._initWithScene:` → 唯一 requester 的 `createPresenterWithIdentifier:` → native `_UIScenePresenter.presentationView`。不移动系统现有 host、不替换系统 Scene delegate、不改默认 manager context。只激活/失活/销毁自己的 presenter，最终释放自己 manager 的引用，**不 invalidate/destroy 系统 Scene/process**。
- Settings：读当前 settings，独立 mutableCopy，只写 `frame` / `backgrounded` / 存在且精确匹配的 `foreground`；`updateSettings:withTransitionContext:` 使用 nil context。不传未知 completion block，而以读回和 process/host 状态确认。若确需 activate 原先 inactive 的 Scene，预检对应 deactivate 逆操作并记账；原生已经接管该 App 时不强制 deactivate。
- Focus：`SBMainWorkspace.sharedInstance.keyboardFocusController` → `SBWorkspaceKeyboardFocusController.userFocusRequestForScene:reason:completion:`；completion 参数为 nil，因为 dump 未给出其 invoke 参数 ABI。查询实际 Scene 与 request generation，不猜回调参数、不全局改键盘规则、不直接改 `externalSceneIdentities`。
- Native activation：`createRequestForApplicationActivation:options:` 的 options=0，再 `executeTransitionRequest:`；仅发送请求不算成功，必须等实际目标 Scene/foreground 确认。

`DXRuntime` 每次调用前用 objc runtime 取得 Method，从**同一个已检查的 Method** 取 IMP；不使用通用 objc_msgSend、KVC 私有读写、猜测 ivar 或任意 selector 调用。`DXABIEncoding.c` 仅忽略方法编码中的栈大小和参数 offset；B/c、I/i、Q/q、@/@?、指针、限定符、结构名及成员布局必须精确匹配。CGRect/CGPoint 使用目标编译器 `@encode`。不做 ptrauth strip；arm64e 必须由实际 Apple 工具链/设备验证。

规范化候选编码：getter `@@:`、bool `B@:`、PID `i@:`、context `I@:`、generation `Q@:`；对象一参 `@@:@` / `v@:@`；settings update `v@:@@`；focus `v@:@@@?`；native create `@@:@Q` / execute `B@:@`；presentation context block `v@:@?`；几何 setter `v@:{CGRect={CGPoint=dd}{CGSize=dd}}`。实际编码逐方法 runtime 检查；不因类名/selector 命中就调用。

## 事件、键盘与恢复：不可混淆的边界

### 事件与前台 authority gate（已编码，尚未真机验证）

`nativeEventBindingReady` 要求：宿主已在主显示的可见 UIWindow，window 原生 `_usesWindowServerHitTesting` 为真且 `_contextId` 非零；native `_UIScenePresentationView` / `_UISceneLayerHostContainerView` 的 `_hitTest:withEvent:windowServerHitTestWindow:` 精确 ABI 存在；容器的 scene 是原对象；`_hostViews` 的真实 `_UISceneLayerHostView.sceneLayer` 同时属于当前 `FBSceneLayerManager.layers` 和容器 hostedLayers；排除 keyboard/proxy layers；其 `CALayerHost.contextId` 必须等于非零 `FBSceneLayer.contextID`。此外 apply/focus 必须观察到 FBProcess.isForeground 及对应 Scene/presenter 状态。

这是调用**原生 remote hit-test 路径**的具体可行源码门禁，比“有画面”强，但仍不是实际 touch 投递/接收的真机证据。没有抓取/伪造 HID 事件，没有向整个屏幕安装 BKSHID 重定向规则。公开 `BKSHIDEventDeliveryManager` 头表明存在 predicate/target assertion，但未证实如何安全映射此双宿主并恢复，故没有靠猜测调用它。若设备上 native UIKit hosting graph 不给自建 presenter 事件/前台权限，当前路径会失败/超时并回收，不能声称已补齐权限。**尚缺独立验证：BackBoard 对每个宿主场景的真实事件授权/接收，以及双 App 在非原生布局下持续 foreground 的系统政策。** 如需补充 assertion，必须先取得其真实身份、最小授权语义及可回收 token，而不是把 `setForeground` 当成保活证明。

### 键盘 authority

焦点 PID 来自真实 `sceneWithFocusIncludingSpringBoard.clientProcess.pid`，不是最后点击 pane、不是键盘扩展进程 PID、不是 SpringBoard 键盘通知自报 ID。原生 `addKeyboardFocusObserver:` 注册前检查运行时 protocol 的必需/可选方法编码，收到回调后重查权威焦点。无此 observer 时，活动租约的 250ms watchdog 仍查询真实 Scene/PID，通知不会造假。

**确切缺口：当前采集头中没有已证实可供本桥直接订阅的跨进程键盘遮挡矩形 + 显示/坐标空间 + 交互进度/动画时序的权威 API。** `SBMainDisplaySceneManager._keyboardWillChangeFrame:` 只是系统内部接收方法，不证明任意 SB observer 都收到所有 App 的键盘变化。父层现有 UIKit keyboard frame 监听只能在桥接确认目标 PID 后作为有限候选使用；不能据此宣布第三方/悬浮/硬件键盘已完全兼容。本桥未新增不安全 IPC 或全局应用 Hook。

### 生命周期和恢复

- 采用 `FBScene.addObserver:` 的 `sceneDidInvalidate:`，从不覆盖系统 delegate；采用 `FBProcessManagerObserver.processManager:didRemoveProcess:`，过滤精确原 process 对象。原生 callback 缺失时 watchdog 仍检查 scene registry、PID、process running、自己的 presenter、settings/原生事件绑定。全部转到主队列、身份重查后才发失效通知。
- 活动 watchdog 为 250ms（40ms leeway），只在有租约时存在，不截图、不逐帧刷新。允许 frontmost 是上下/暂存目标中的一个；换成其它 App、无法确认 frontmost 或锁屏时丢失上下文并清理。自身焦点切换不等于外来 App 切换。
- 租约只保存原始 frame/foreground/backgrounded 和最后一次写值；恢复用**当前** settings 的 mutableCopy，按字段仅恢复仍等于本插件最后写值且同 Scene/process/registry owner 的字段。其它插件/原生修改过的字段不覆盖，已经是原值的字段不重复写。生产 `DXLeaseRestoreMask` 为本机 C 测试直接调用的同一函数。
- 焦点仅在 controller 身份、request generation、当前 Scene 仍匹配自己的请求/原焦点时，以新原生请求 supersede 旧请求；有新用户/系统请求就不抢回。Scene/process 失效后不根据旧 PID 复活。锁屏时不强制改焦点。
- 真实 limitation：Scene settings API 没有已证实的跨进程 compare-and-swap ownership token；值相同的第三方接管无法仅凭快照辨认。focus API 也没有已证实的 cancel token；superseding 请求的乱序/锁屏效果仍需实测。不能把源码的 value/generation 检查写成系统级原子事务证明。
- 每项清理隔离异常，销毁自己的 presenter、移除自己的 observer/host。若私有 observer token 的 `invalidate` 编码未知或移除抛异常，不猜测调用/不反复注册；保留至多一个原 token/移除目标待后续重试。该罕见分支有界但**不能声称已确认注销**；capabilityReport 可见注册状态，必须列为运行时诊断/回归事项。

## 本地实际验证与未执行项

执行 `sh Tests/Bridge/run-local.sh --require-evidence` 的真实输出：

```text
PASS: 21053 production ABI/lease/corpus checks (C only; no iOS runtime claims)
PASS: 93 pinned public-header SHA256 checks; 14 source-candidate declarations (not runtime verification)
```

C 覆盖：方法 offsets、block/id、BOOL/char、整数符号、CGRect/CGPoint 布局/名称、指针/限定符、畸形字符串；16×16×2×2 的恢复掩码/所有权穷举；20,000 个确定性畸形输入。编译产物只在 mktemp 的 /tmp 下，退出删除，没有 tweak/iOS/package 构建。

另已验证：证据目录缺失时显示 **NOT RUN**，普通模式 exit=0；`--require-evidence` exit=2，不把缺失写成 PASS。本地完整 raw headers 保留原样；**源码 ZIP 必须排除 `Tests/Bridge/evidence/**` 和 `__pycache__`，保留 `evidence-manifest.json`、fetch/check 脚本及本文件，不分发第三方头代码**。用户可主动 `python3 Tests/Bridge/fetch_evidence.py` 按固定 URL/SHA 下载再严格检查；该脚本只 HTTPS GET，不依赖 GitHub API 搜索/限流额度。

**没有执行**：ObjC/UIKit iOS 编译、Swift importer、arm64/arm64e 链接/PAC、设备 host graph/foreground/assertion、真实触摸/键盘、原生过渡恢复、锁屏/退出压力测试。不可用 stub SDK 或源码扫描冒充这些结果。实际构建需父工程编译本目录 `.m` 和 `.c`、启用 ARC/blocks，部署目标 15.0；本轮没有修改构建文件或运行 CI/打包/commit/push。

## 公开证据来源

2026-11-02 只读获取。主要来源是 MTACS 的 iOS 17 runtime header dump（仓库标注版本，不是已验证设备矩阵）；交叉研究 nst 历史 RuntimeBrowser dump 和 Theos 维护头。三者都只提供接口事实，不提供此产品的正确性保证。

- MTACS/iOS-17-Runtime-Headers：revision `d1d960dfaa4107765dd7fcf891e4967c0930d5fd`。
- nst/iOS-Runtime-Headers：revision `fbb634c78269b0169efdead80955ba64eaaa2f21`。
- theos/headers：revision `13c1f17176d7efe6871551cd69a75b71ac4eeaf1`。

全部 93 个文件的固定 raw URL、字节数、SHA256 与本地相对路径见可分发的 `Tests/Bridge/evidence-manifest.json`。下面列出当前路径的主要证据（SHA 是原始公开头文件全文，不是摘录）。研究期间 GitHub recursive tree 先遇 IncompleteRead，后 API 403 rate-limit；最终证据来自固定 raw URLs，已独立重算 SHA；没有把失败写成成功。Limneos HTTPS 因本环境 CA 链错误未作为证据采用，没有关闭 TLS 校验。

参考产品仅阅读指定 `stageduo-feasibility-20261102/binary/summary.md` 中的系统接口事实作为研究方向；没有读取/翻译其实现、复制类/资源或依赖样本。历史 `FBSceneHostManager` requester 路径已查，但未作为 raw pixel-host 的“兼容回退”，因为单凭它不能证明本任务所需事件/前台所有权闭环。

<!-- PINNED-EVIDENCE-TABLE -->

| Public header / pinned raw URL | SHA256 |
|---|---|
| [CALayerHost.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/Frameworks/QuartzCore.framework/CALayerHost.h) | `28587a95e5388396157326805cf5d864896d4f9e67aa9f6d3a44f08a9322d27f` |
| [BKSHIDEventDeliveryManager.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/BackBoardServices.framework/BKSHIDEventDeliveryManager.h) | `17f98b34a369de7914882919e589873e3f8c540cceba7b69849bfd2f82a11012` |
| [FBProcess.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/FrontBoard.framework/FBProcess.h) | `467b817d11ac5bf4f1a1f2b4e294570dd1a3d0872fa472448bed0daeb46dcc04` |
| [FBScene.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/FrontBoard.framework/FBScene.h) | `dd30a45ffef9b8e6260a45888225a46836cd1287d76f71c7924ae49437aea88f` |
| [FBSceneLayer.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/FrontBoard.framework/FBSceneLayer.h) | `c47b3cf20314f38cf15c997e6403a21983a3982dd5cfa2e138dd7bbd8bcbafed` |
| [FBSceneLayerManager.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/FrontBoard.framework/FBSceneLayerManager.h) | `1befef7b629a6483268e97aa75ac432b969d1321475e4904743c29594ac79dbf` |
| [FBSceneManager.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/FrontBoard.framework/FBSceneManager.h) | `a9e1f3b75da45ffa743bf5eeaff18d031b53729c76c93b3c272760251ebc4abc` |
| [FBSMutableSceneSettings.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/FrontBoardServices.framework/FBSMutableSceneSettings.h) | `f547f3b99571e05471d2f5ccfe0c15231201f406c1800a558e3330e5ae9f43ec` |
| [SBMainDisplaySceneManager.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/SpringBoard.framework/SBMainDisplaySceneManager.h) | `1cd283516b13759767a6a526ea572c1acec101d8f074c37ff3182b71ea65618f` |
| [SBMainWorkspace.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/SpringBoard.framework/SBMainWorkspace.h) | `abd398eb46a4c379dc6b97ce6c960593f9fe2d323beebe9eaf0a45c253cc7d88` |
| [SBSceneManager.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/SpringBoard.framework/SBSceneManager.h) | `b87a74ab92cf4781182a6a7f66641ad7894a898e7d17bca40bcf2245acb08222` |
| [SBSceneManagerCoordinator.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/SpringBoard.framework/SBSceneManagerCoordinator.h) | `cd7e66553953f8475a05f03fbe6d2aeda7caf73590ec9305c8473cb1b9b3c731` |
| [SBWorkspaceKeyboardFocusController.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/SpringBoard.framework/SBWorkspaceKeyboardFocusController.h) | `843e2bf045634bd88f088b65c43c5b275a32dc9510ad617db28df8a5a4ff9c85` |
| [UIMutableScenePresentationContext.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/UIKitCore.framework/UIMutableScenePresentationContext.h) | `d9bf45f910394a040fd10b640473f275bd5da95d56ad3d6225e8eb8a041f8b90` |
| [UIMutableTransformer.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/UIKitCore.framework/UIMutableTransformer.h) | `f59066acc544ff5f0ec0729bda8f2d379316f5501e3268bdeddf8eb73fba5cbb` |
| [UIScenePresentationManager.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/UIKitCore.framework/UIScenePresentationManager.h) | `59245aedd91f0106c3f0ffa9ee9cfdd62c3c749e7eb0ed349567f025fbec432c` |
| [UITransform.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/UIKitCore.framework/UITransform.h) | `dc341a23d0537bd5ac61995b2ba9cc24fda15fb0d38cc1d91de2556c108dd40d` |
| [UIWindow.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/UIKitCore.framework/UIWindow.h) | `c35e203681b119bc736e909d617e6065319a9e6e7124bcf27705a03e1084e692` |
| [_UISceneLayerHostContainerView.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/UIKitCore.framework/_UISceneLayerHostContainerView.h) | `3e8f312ccf02b2310609a09b3a45a3ababf51e89b8df3f68703461043177287b` |
| [_UISceneLayerHostView.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/UIKitCore.framework/_UISceneLayerHostView.h) | `de167c638a6c6d12d8cc1ae19c32d1694a06dbc966dbef34fa119a97b8a05ef6` |
| [_UIScenePresentationView.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/UIKitCore.framework/_UIScenePresentationView.h) | `6c1cbf334142c09f60684ec77f6ca170831f365a389c71d2f0321c540192541f` |
| [_UIScenePresenter.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/PrivateFrameworks/UIKitCore.framework/_UIScenePresenter.h) | `0daf6282de824ac680291014596d9a15ff5fccb8c7038ba0c478a89b964e242d` |
| [FBProcessManagerObserver.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/protocols/FBProcessManagerObserver.h) | `7f32f61ba9d49551c4d3dd8895574ffb6c09aca31cead1bbb047ad531484776d` |
| [FBSceneObserver.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/protocols/FBSceneObserver.h) | `66986bd46aafc88c8a3bd691e2b92f1b3de31c5273e7b0801a3f0a1718c9ff79` |
| [SBWorkspaceKeyboardFocusControllerObserver.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/d1d960dfaa4107765dd7fcf891e4967c0930d5fd/protocols/SBWorkspaceKeyboardFocusControllerObserver.h) | `724193b15888bc45a75fa674627e093f7b2158057cb58bf11eef1ae187ddd10e` |
| [FBSceneHostManager.h](https://raw.githubusercontent.com/nst/iOS-Runtime-Headers/fbb634c78269b0169efdead80955ba64eaaa2f21/PrivateFrameworks/FrontBoard.framework/FBSceneHostManager.h) | `195162c7d6edc31ce2d44f41f4d6619af058743f46ad028ee5ea5bf0c88b9909` |
