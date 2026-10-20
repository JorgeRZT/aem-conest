import Foundation
import SwiftUI

enum AppInfo {
    static let repo = "JorgeRZT/aem-conest"

    /// Version from Info.plist (CalVer, YYYY.MM.DD). Nil when running outside an app bundle.
    static var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

enum Version {
    /// Compares dot-separated numeric versions, e.g. "2026.10.21" > "2026.10.20".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

struct ReleaseInfo: Decodable {
    let tagName: String
    let htmlURL: URL

    var version: String { tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

enum UpdateService {
    /// Latest published (non-draft, non-prerelease) GitHub release, or nil if there is none yet.
    static func latestRelease() async throws -> ReleaseInfo? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(AppInfo.repo)/releases/latest")!)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AEM-Conest/\(AppInfo.version ?? "dev")", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }
}

enum UpdateAlert: Identifiable {
    case available(ReleaseInfo, current: String)
    case upToDate(String)
    case failed

    var id: String {
        switch self {
        case .available(let r, _): return "available-\(r.version)"
        case .upToDate: return "upToDate"
        case .failed: return "failed"
        }
    }

    var title: String {
        switch self {
        case .available: return "Update available"
        case .upToDate: return "You're up to date"
        case .failed: return "Could not check for updates"
        }
    }

    var message: String {
        switch self {
        case .available(let r, let current):
            return "Version \(r.version) is available (you are using \(current)).\n\nThe app is not signed, so macOS will ask for confirmation the first time you open the new version (right-click → Open)."
        case .upToDate(let v):
            return "AEM Conest \(v) is the latest version."
        case .failed:
            return "Check your internet connection and try again later."
        }
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var alert: UpdateAlert?

    /// Silent on launch: only an available update is shown; errors and "up to date" are ignored.
    func checkOnLaunch() async { await check(manual: false) }

    func check(manual: Bool) async {
        // Development builds (no app bundle version) never prompt.
        guard let current = AppInfo.version else { return }
        do {
            let latest = try await UpdateService.latestRelease()
            if let latest, Version.isNewer(latest.version, than: current) {
                alert = .available(latest, current: current)
            } else if manual {
                alert = .upToDate(current)
            }
        } catch {
            if manual { alert = .failed }
        }
    }
}
