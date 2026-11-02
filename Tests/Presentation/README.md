# Presentation tests

## 本地实际结果

本轮环境：Alpine/iSH；`which swift`、`which swiftc` 均无结果；没有 Apple UIKit SDK。**未编译 Swift，未运行 UIKit XCTest，未连接/附加设备，未安装或运行插件。** `verify_source_contract.py` 是文本契约检查，不能代替任何上述验证。

```sh
python3 Tests/Presentation/verify_source_contract.py
```

## 在具备 iOS SDK 时的测试接入（本轮未执行）

创建本地 iOS Unit Testing target，deployment target 15.0、Swift language mode 5、host application 使用普通空白 UIKit App。两种接法选其一：

1. 将生产 `Sources/Presentation/*.swift`、`Sources/Core/DXGeometry.swift` 与本目录 `DXPresentationTests.swift` 加入**同一个测试 target**；真实 ObjC `Sources/System/*.m` / `*.c` 加入 target，bridging header 导入真实 `Sources/System/DXSystemBridge.h`，链接 UIKit / Foundation / QuartzCore 等生产系统模块所需框架。不要创建假的 `DXSlot`、`DXApplicationRecord` 或假的 UIKit SDK。
2. 父工程将真实生产模块产出为可导入且开启 testability 的 `DynamicStageX` module 后，在测试文件加 `@testable import DynamicStageX`，仅测试 target 编译测试文件。当前 Theos dylib 不是现成的 Xcode XCTest 工程；本目录不宣称已有可运行 test scheme。

不要将 `Sources/Entry/`、hook/启动代码注入测试 host；本测试不调用 bridge 私有 Scene 操作。

## 覆盖范围

直接调用生产代码验证：两个 UIView 实例安装、裁剪 mask/命中同路径、所有权条件下 detach 恢复、跨 pane 转移/外部重挂载、非取消手势属性、圆角钳制及动画 path topology、无关 layout 不清除 mask 动画、输入专注保存/恢复最新 split 目标、无效布局不覆盖当前布局、根视图空隙/圆角透传、选择器空列表/幂等取消、不伪造选择、名称/bundle ID 多词搜索、32×56pt 触发区和误滑负例。

普通 UIView 是**测试 fixture**，不是插件中的 App provider。非空 `DXApplicationRecord` 不用 KVC/私有初始化伪造；真实枚举列表、去重、排除和选择后的 Scene 启动须由父工程使用真实 bridge 记录做集成测试。

## 仍需 UIKit/真机验证

- 动画中连续更新/取消：presentation frame、mask path、opacity 不跳回旧目标，无短暂方角；上文 mask 动画存在性测试并非渲染器证明。
- 原生 remote host 四角真正受 mask 约束，跨进程触摸/滚动/文本输入及动画时事件坐标正确。
- overlay 不成为 remote App 的 key；搜索暂借 key 的获得/归还、系统抢走 key 后不反抢；picker 搜索事件不被父键盘模块当成 remote App 键盘。
- 真实 gesture arena 的 observer 不影响 App pan/tap/long-press；小条失败/cancel 不触发，物理区域外不截获，Home/切换器优先，VoiceOver 显式激活可用。
- parent 在锁屏、切换器、控制中心、Scene 失效时立即撤销上下文/隐藏窗口并解除真实输入焦点。没有公共 UIKit API 能重放已从小条接收的同一触摸流。
- Dynamic Type/VoiceOver、键盘高度变化、旋转/安全区更新、反复进入/退出和资源释放。

源码扫描结果与未执行项目分开记录在 `Docs/UI.md`，不得写成“iOS15+ 功能测试通过”。
