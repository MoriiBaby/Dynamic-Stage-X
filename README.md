# Dynamic Stage X

独立 Swift 主体的 iPhone 上下双应用窗口插件。

- 插件名：**Dynamic Stage X**
- 包名 / 偏好域：**com.tsangbaby.dynamicstagex**
- 源码版本：**0.1.0-alpha1**（Debian 版本 `0.1.0~alpha1`）
- 开发目标：**iOS 15.0+**，无最高系统版本拦截。
- 本轮交付：**本地源码候选**，不是已构建、已安装或已证明兼容全部 iOS15+ 的成品。

## 实现范围

- Swift 布局与会话状态机、generation/会话取消与资源所有权。
- UIKit 上下独立窗口、真实宿主裁剪、连续圆角/同路径命中、可中断布局动画。
- 应用选择、下窗更换、关闭、有界收起重入；明确的边缘触发区域。
- 统一系统键盘，按系统实际输入 PID 校验归属，停靠键盘输入专注区域、恢复双窗、浮动/硬件键盘不错误占满宽度。
- SpringBoard 私有 Scene / 原生 presenter / native hit-testing 候选适配器：精确 ABI 检查、几何与焦点确认、有限超时、恢复所有权检查。
- 自有 Swift 设置页：总开关、圆角、间距和左右触发位置。
- 主插件默认关闭；没有按系统版本上限禁用的分支，能力不匹配会保留原生行为并报告具体失败原因。

## 工程结构

```text
Sources/Core/            Foundation-only 生产 Swift：布局/键盘/状态/有限资源
Sources/Coordinator/     主线程会话与串行系统命令、迟到回调和收尾
Sources/System/          类型化私有API薄桥、纯C ABI/恢复策略
Sources/Presentation/    圆角真实宿主、工具条、选择器、窗口和边缘触发
Sources/Input/           不读取输入内容的键盘frame观察器
Sources/Preferences/     独立偏好域、有限配置与UIKit几何桥接
Sources/Entry/           仅SpringBoard的延迟初始化入口
Preferences/             Swift设置面板与最小编译声明
Tests/                   生产逻辑XCTest、C与源码契约检查
Scripts/                 本地源码/语法检查与交付清单工具
Docs/                    接口依据、限制、验证与使用说明
```

## 源码机制与关键边界

使用系统真实 Scene/presenter，不用截图、录像或WebView冒充其它App。Scene存在、native event binding、process foreground、几何read-back和输入焦点是独立检查项；像素能显示不代表触摸已成功。

应用冷启动采用保守路径：已有目标Scene可直接托管；目标尚无Scene时，先释放本项目租约，经系统正常启动目标应用，确认后重建上下双窗。因此可能短暂出现原生启动过场，不猜测未证实的私有Scene创建ABI。应用退出或失去控制权后不伪造继续运行。

系统私有接口来自独立查阅的runtime headers，只采用经过类型编码检查的调用候选。源码不复制参考产品的函数实现、业务类、二进制、设置资源或包身份，也不依赖参考DEB。新系统缺少某项能力时保留原生行为，但不按OS版本号封禁。

键盘的几何事件目前依赖SpringBoard收到的系统UIKit通知，输入归属再经系统Scene/PID确认。跨进程键盘通知是否在每个系统完整送达属于必须验证项；这版不为了掩盖该缺口而向所有UIKit应用注入全局尺寸Hook或未经鉴权的IPC。

## 本地验证

普通Python：

```sh
python3 Scripts/check_source.py
python3 Tests/Core/verify_source_contract.py
```

纯C桥接策略测试按 `Tests/Bridge/` 中说明执行，无需iOS SDK。Swift核心有生产代码XCTest，具备Swift工具链后运行：

```sh
swift test
```

可选Swift文法检查（**不等于类型检查或编译**）：

```sh
python3 -m venv /tmp/dynamicstagex-python
/tmp/dynamicstagex-python/bin/pip install tree-sitter==0.25.2 tree-sitter-swift==0.7.4
/tmp/dynamicstagex-python/bin/python Scripts/check_swift_grammar.py
```

实际执行结果见 [VERIFICATION.md](Docs/VERIFICATION.md)。当前环境无 `swiftc` / `xcrun`；没有将源码扫描、文法分析或C测试称为Swift/UIKit编译通过。

## 未来构建说明（本轮未执行）

需要可信Mac/Xcode、对应越狱方案的Theos及合法可用的iOS SDK。使用实际支持iOS15部署和arm64e的工具链。当前配方以原生RootHide为默认：

```sh
make package THEOS_PACKAGE_SCHEME=roothide
```

不要使用 `make install`，除非用户后续明确要求设备安装。rootless必须使用原生工具链和对应架构控制字段独立验证，不能把RootHide DEB改名冒充。详见 [BUILD.md](Docs/BUILD.md)。源码没有自动CI工作流、远端URL、上传脚本或自动respring步骤。

## 验证与安全边界

本轮只写源码及执行本地可用检查；没有创建commit/push、触发CI、连接/attach设备、安装或respring。真实Scene/触摸/焦点/恢复、设备性能和逐版本兼容仍需后续用户指示后的原生构建与真机验证。

15.0最低部署目标不是全范围实测证明。详细限制见 [KNOWN-LIMITATIONS.md](Docs/KNOWN-LIMITATIONS.md)，接口和原始依据见 [SYSTEM-API.md](Docs/SYSTEM-API.md)。
