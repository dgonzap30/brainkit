import Foundation

/// The deploy-time record deploy-phone.sh stamps into each app bundle as
/// `LodestarProvisioning.plist` (E9 §1a). `provisionedAt` is an ISO-8601 string in the plist
/// (PlistBuddy-friendly), decode fails (nil) on any missing/mistyped required field so a
/// half-stamped bundle behaves exactly like an unprovisioned one.
public struct ProvisioningRecord: Equatable, Sendable {
    public let schemaVersion: Int
    public let brainHost: String
    public let brainHostFallback: String?
    public let newsroomBFFHost: String?
    public let frontDoorToken: String
    public let ingestToken: String?
    public let provisionedAt: Date

    public init?(plistData: Data) {
        guard let raw = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
              let dict = raw as? [String: Any],
              let schemaVersion = dict["schemaVersion"] as? Int,
              let brainHost = dict["brainHost"] as? String, !brainHost.isEmpty,
              let frontDoorToken = dict["frontDoorToken"] as? String, !frontDoorToken.isEmpty,
              let provisionedAtRaw = dict["provisionedAt"] as? String,
              let provisionedAt = ISO8601DateFormatter().date(from: provisionedAtRaw)
        else { return nil }
        self.schemaVersion = schemaVersion
        self.brainHost = brainHost
        self.brainHostFallback = dict["brainHostFallback"] as? String
        self.newsroomBFFHost = dict["newsroomBFFHost"] as? String
        self.frontDoorToken = frontDoorToken
        self.ingestToken = dict["ingestToken"] as? String
        self.provisionedAt = provisionedAt
    }

    /// The stamped record in an installed bundle, nil when the build never went through
    /// deploy-phone (spec §4: unprovisioned builds behave exactly like today).
    public static func fromBundle(_ bundle: Bundle = .main) -> ProvisioningRecord? {
        guard let url = bundle.url(forResource: "LodestarProvisioning", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ProvisioningRecord(plistData: data)
    }
}
