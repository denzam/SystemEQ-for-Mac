import CryptoKit
import Foundation

struct ProjectMPresetArchive {
    enum Failure: LocalizedError {
        case invalidMetadata
        case invalidResponse
        case unreadableArchive
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .invalidMetadata: "Invalid pinned preset archive metadata"
            case .invalidResponse: "Preset archive response is not HTTP 200"
            case .unreadableArchive: "Preset archive cannot be read"
            case .checksumMismatch: "Preset archive SHA256 does not match the pinned version"
            }
        }
    }

    let url: URL
    let sha256: String

    init(infoDictionary: [String: Any]?) throws {
        guard let commit = infoDictionary?["ProjectMPresetCommit"] as? String,
              commit.count == 40,
              commit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              let digest = infoDictionary?["ProjectMPresetSHA256"] as? String,
              digest.count == 64,
              digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              let url =
              URL(string: "https://codeload.github.com/projectM-visualizer/presets-cream-of-the-crop/zip/\(commit)")
        else { throw Failure.invalidMetadata }
        self.url = url
        sha256 = digest
    }

    func validate(file: URL, statusCode: Int) throws {
        guard statusCode == 200 else { throw Failure.invalidResponse }
        guard let stream = InputStream(url: file) else { throw Failure.unreadableArchive }
        stream.open()
        defer { stream.close() }
        var hash = SHA256()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = stream.read(&buffer, maxLength: 65536)
            guard count >= 0 else { throw Failure.unreadableArchive }
            if count == 0 { break }
            hash.update(data: Data(buffer.prefix(count)))
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw Failure.checksumMismatch }
    }
}
