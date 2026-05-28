import Foundation
import AppKit

@MainActor
enum UpdateChecker {
    private static let repo = "sliday/caip"
    private static let lastCheckKey = "caip.lastUpdateCheckAt"
    private static let skippedKey = "caip.skippedVersion"
    private static let dailyInterval: TimeInterval = 60 * 60 * 24

    /// Background check on launch — only fires at most once per 24h.
    /// Silent when the app is up to date.
    static func scheduleLaunchCheck() {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        if now - last < dailyInterval { return }
        Task { await check(initiatedByUser: false) }
    }

    /// Manual check from the menubar. Always shows a Toast: either "up to date" or
    /// "update available".
    static func manualCheck() {
        Task { await check(initiatedByUser: true) }
    }

    private static func check(initiatedByUser: Bool) async {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        do {
            let release = try await fetchLatest()
            let latest = normalize(release.tag_name)
            let current = currentVersion()
            if isNewer(latest: latest, current: current) {
                if !initiatedByUser, UserDefaults.standard.string(forKey: skippedKey) == latest {
                    return // user previously skipped this version
                }
                presentAvailable(version: latest, releaseURL: release.html_url)
            } else if initiatedByUser {
                Toast.show(title: "caip is up to date",
                           body: "Running v\(current).",
                           icon: "checkmark.circle.fill",
                           tint: .green,
                           duration: 2.4)
            }
        } catch {
            if initiatedByUser {
                Toast.show(title: "Couldn't check for updates",
                           body: error.localizedDescription,
                           icon: "wifi.exclamationmark",
                           tint: .orange,
                           duration: 3.0)
            }
        }
    }

    private static func presentAvailable(version: String, releaseURL: URL) {
        let alert = NSAlert()
        alert.messageText = "caip v\(version) is available"
        alert.informativeText = "You are running v\(currentVersion()).\n\nDownload the new build, drag it to /Applications, and replace the existing copy."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(releaseURL)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(version, forKey: skippedKey)
        default:
            break
        }
    }

    // MARK: - Network

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
    }

    private static func fetchLatest() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("caip-update-check", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "caip.update", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub returned HTTP \(http.statusCode)"])
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: - Version comparison

    private static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private static func normalize(_ tag: String) -> String {
        var s = tag
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Semver-ish lexical compare. "0.2.10" > "0.2.9", "0.3.0" > "0.2.10", etc.
    private static func isNewer(latest: String, current: String) -> Bool {
        let l = latest.split(separator: ".").map { Int($0) ?? 0 }
        let c = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(l.count, c.count)
        for i in 0..<count {
            let li = i < l.count ? l[i] : 0
            let ci = i < c.count ? c[i] : 0
            if li > ci { return true }
            if li < ci { return false }
        }
        return false
    }
}
