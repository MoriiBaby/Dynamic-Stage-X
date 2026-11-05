import Foundation

/// Presentation of bounded operational errors. The original error remains first even when
/// releasing the same session fails too. Only structural identifiers are displayed.
public enum DXFailurePolicy {
    public static func description(primary: Error?, cleanup: Error?) -> String? {
        guard primary != nil || cleanup != nil else { return nil }
        let first = primary.map { detail($0 as NSError) }
        let attached = (primary as NSError?)?.userInfo[NSUnderlyingErrorKey] as? NSError
        let recoveryError = cleanup ?? attached
        let recovery = recoveryError.map { detail($0 as NSError) }
        if let first = first, let recovery = recovery {
            if first == recovery { return "分屏失败：\(first)\n恢复未确认：同一错误仍存在。" }
            return "分屏失败：\(first)\n恢复同时遇到问题：\(recovery)"
        }
        if let first = first { return "分屏失败：\(first)" }
        return recovery.map { "恢复系统场景未确认：\($0)" }
    }

    private static func identifier(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.utf8.count <= 96,
              text.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_:.+-").contains($0)
              }) else { return nil }
        return text
    }

    public static func detail(_ error: NSError) -> String {
        let info = error.userInfo
        let stage = identifier(info["DXSceneStage"])
        let operation = identifier(info["DXSceneOperation"])
        let selector = identifier(info["DXSceneSelector"])
        let exception = identifier(info["DXSceneExceptionName"])
        let readiness = info["DXSceneReadiness"] as? [String: Any]
        let pending = (readiness?["pending"] as? [String] ?? []).compactMap { identifier($0) }.prefix(6)
        var labels = [operation, stage].compactMap { $0 }
        if !pending.isEmpty { labels.append("未就绪=" + pending.joined(separator: ",")) }
        if let selector = selector { labels.append(selector) }
        if let exception = exception { labels.append(exception) }
        let headline = String(error.localizedDescription.prefix(160))
        return labels.isEmpty ? headline : headline + " [" + labels.joined(separator: "; ") + "]"
    }
}
