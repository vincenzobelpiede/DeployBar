import Foundation

struct StatusIconOption: Identifiable, Hashable {
    let id: String           // SF Symbol name
    let label: String        // UI label
}

enum StatusIcon {
    static let defaultsKey = "statusIconName"
    static let changedNotification = Notification.Name("DeployBar.statusIconChanged")

    static let customAssetName = "MenuBarIcon"
    static let customAssetId = "deploybar.menuicon"

    static let options: [StatusIconOption] = [
        .init(id: customAssetId, label: "DeployBar"),
        .init(id: "paperplane.fill", label: "Paper Plane"),
        .init(id: "arrow.up.forward.app.fill", label: "App Launch"),
        .init(id: "shippingbox.fill", label: "Shipping Box"),
        .init(id: "bolt.fill", label: "Bolt"),
        .init(id: "square.and.arrow.up.fill", label: "Share Up"),
        .init(id: "externaldrive.fill.badge.plus", label: "External Drive"),
        .init(id: "iphone.and.arrow.forward", label: "iPhone Forward"),
        .init(id: "hammer.fill", label: "Hammer"),
        .init(id: "wrench.and.screwdriver.fill", label: "Wrench"),
        .init(id: "airplane", label: "Airplane")
    ]

    static var current: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? customAssetId
    }
}
