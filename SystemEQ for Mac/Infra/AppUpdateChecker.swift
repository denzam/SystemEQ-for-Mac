import Combine
import Foundation

@MainActor
final class AppUpdateChecker: ObservableObject {
    struct Release: Equatable {
        let version: String
        let url: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(currentVersion: String)
        case updateAvailable(currentVersion: String, release: Release)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    func checkForUpdates() async {
        let currentVersion = Self.currentVersion
        state = .checking

        guard let url = URL(string: AppConstants.URLs.projectLatestReleaseAPI) else {
            state = .failed(LocalizationManager.shared.localized(.appUpdateCheckFailed))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SystemEQ-for-Mac", forHTTPHeaderField: "User-Agent")

        do {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 20
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                state = .failed(LocalizationManager.shared.localized(.appUpdateCheckFailed))
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !release.draft, !release.prerelease else {
                state = .upToDate(currentVersion: currentVersion)
                return
            }

            let normalizedVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let appRelease = Release(version: normalizedVersion, url: release.htmlURL)
            if Self.isNewerVersion(normalizedVersion, than: currentVersion) {
                state = .updateAvailable(currentVersion: currentVersion, release: appRelease)
            } else {
                state = .upToDate(currentVersion: currentVersion)
            }
        } catch {
            state = .failed(LocalizationManager.shared.localized(.appUpdateCheckFailed))
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let candidateParts = versionParts(candidate)
        let currentParts = versionParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                Int(component.prefix { $0.isNumber }) ?? 0
            }
    }
}
