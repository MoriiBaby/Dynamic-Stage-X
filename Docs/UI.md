# Dynamic Stage X — UIKit 展示层

状态：本目录源码候选及12个UIKit XCTest方法已写入；源代码交付不等于iOS编译或真机验证。最低目标iOS15.0、Swift5；不设最高系统版本判断，不使用SwiftUI、截图或参考插件资源。

## 集成边界与约定

- 严格实现 `Docs/CONTRACT.md` 的 `DXRoundedPane`、`DXStageViewController`、`DXOverlayWindow`、`DXEdgeTriggerWindow` 名称及方法。`DXSlot` 来自 Core，`DXApplicationRecord` 来自 ObjC bridge；展示层不重定义它们。
- 所有方法和属性仅限主线程。父协调器拥有 Scene 生命周期、逻辑 frame、异步代号、键盘通知、系统上下文许可和真实输入焦点；展示层仅传回意图。`onFocus` 不是已确认焦点通知。
- 真实 bridge `hostView` 直接挂入 pane；不创建替代 App 画面。`detach` 只移除自己仍拥有的子视图并恢复自己改动的 view 布局属性；不会把宿主重新塞回过期系统父视图，也不会释放 Scene。
- 圆角采用独立构造的平滑、曲率连续 Bézier mask，同一路径用于绘制与命中，而非用圆形命中近似 UIKit 私有 continuous path。宿主绕过普通 CALayer mask 的情况须由系统适配层另行验证。
- 输入专注模式保留 split 目标布局、隐藏另一 pane 的内容但不销毁宿主；实际焦点交接和系统键盘不由 UI 伪造。
- overlay始终非key，窗格外透传。应用选择器为临时模态列表，采用本地化字母索引；没有会抢走远端Scene输入所有权的键盘搜索框。
- edge 默认右下角，只有小条命中；刻意向上滑动结束后才触发。parent 必须在锁屏/切换器/控制中心/焦点不可靠时隐藏窗口或撤销上下文许可。公开 UIKit 无法把已被小条接收的失败触摸流重新投递给下面的窗口；不宣称能重放系统手势。

## 验证状态

当前环境无`swift`可执行文件，亦无Apple UIKit SDK；没有运行iOS编译、XCTest、设备连接、安装或CI。已写入直接调用生产代码的UIKit XCTest源码与运行说明，尚未执行；静态检查仅作为源码检查，不作为功能通过证据。

## 2026-11-02 集成修正（优先于上文初稿的搜索键窗描述）

父协调器确认：native bridge 会拒绝外部/Scene 焦点所有权变化，本地 picker 搜索把 overlay 设为 key 可能使 SpringBoard 抢到键盘并失效远端 lease。因此默认选择器改为**按真实应用记录排序的列表 + 本地化字母索引**，不显示键盘搜索字段；overlay 始终 `canBecomeKey == false`，移除搜索键窗租约。保留无键盘的程序化过滤入口用于可信调用方已有查询，不用本地 firstResponder 换取“搜索可用”。将来若增加键盘搜索，必须先由 parent 提供真实远端 lease/输入能力的显式握手，当前无此能力就不启用。

`setFrames`/mask 代码只控制 view 展示，不确认 bridge.apply、原生触摸或 Scene 生命周期；父协调器仍须先把真实 host 挂到 window，再 apply，并自行串行化系统命令。
