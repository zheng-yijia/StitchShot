import Foundation

public enum AppConstants {
    public static let appGroupID = "group.com.example.stitchshot"
    public static let urlScheme = "stitchshot"

    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static var sharedContainerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.temporaryDirectory
    }

    public static var inboxDirectoryURL: URL {
        sharedContainerURL.appendingPathComponent("Inbox", isDirectory: true)
    }
}
