import Foundation

@main
struct PresetArchiveTests {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(errorDescription: message) }
    }

    static func reject(_ action: () throws -> Void) throws {
        do { try action() } catch is ProjectMPresetArchive.Failure { return }
        throw Failure(errorDescription: "Invalid preset archive was accepted")
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw Failure(errorDescription: "Fixture directory required") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("presets.zip")
        let sentinel = directory.appendingPathComponent("user-presets.milk")
        try Data("user data".utf8).write(to: sentinel)
        let info = [
            "ProjectMPresetCommit": String(repeating: "1", count: 40),
            "ProjectMPresetSHA256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        ]
        let archive = try ProjectMPresetArchive(infoDictionary: info)
        try require(archive.url.absoluteString.hasSuffix(String(repeating: "1", count: 40)), "Unpinned URL")
        try Data("abc".utf8).write(to: file)
        try archive.validate(file: file, statusCode: 200)
        for code in [0, 204, 206, 404, 500] {
            try reject { try archive.validate(file: file, statusCode: code) }
        }
        for metadata: [String: Any]? in [nil, [:], ["ProjectMPresetCommit": "master"], ["ProjectMPresetCommit": 1]] {
            try reject { _ = try ProjectMPresetArchive(infoDictionary: metadata) }
        }
        var newlineInfo = info
        newlineInfo["ProjectMPresetCommit"] = info["ProjectMPresetCommit"]! + "\n"
        try reject { _ = try ProjectMPresetArchive(infoDictionary: newlineInfo) }
        for content in [Data(), Data("corrupt".utf8)] {
            try content.write(to: file)
            try reject { try archive.validate(file: file, statusCode: 200) }
            try require(try Data(contentsOf: file) == content, "Archive was modified")
        }
        var largeInfo = info
        largeInfo["ProjectMPresetSHA256"] = "7e009ea4ef882e385b3c0bcbbfa8d009bb0a633bdd764415c09182ee0e75da73"
        let largeArchive = try ProjectMPresetArchive(infoDictionary: largeInfo)
        try Data(repeating: 97, count: 131073).write(to: file)
        try largeArchive.validate(file: file, statusCode: 200)
        try reject { try archive.validate(file: directory.appendingPathComponent("missing.zip"), statusCode: 200) }
        try require(try Data(contentsOf: sentinel) == Data("user data".utf8), "User presets were modified")
        print("Preset archive validation: tests passed")
    }
}
