#!/usr/bin/env swift
import CryptoKit
import Foundation

struct InvalidFeed: Error {}
func require(_ condition: Bool) throws {
    if !condition { throw InvalidFeed() }
}
func decoded(_ value: String, count: Int) throws -> Data {
    guard let bytes = Data(base64Encoded: value), bytes.count == count,
          bytes.base64EncodedString() == value else { throw InvalidFeed() }
    return bytes
}
func verify(feed: Data, archive: Data, publicKey: String, url: String, build: String, version: String) throws {
    try require(!archive.isEmpty && feed.count < 1_000_000)
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: decoded(publicKey, count: 32))
    let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    guard let marker = feed.range(of: prefix, options: .backwards),
          let trailer = String(data: feed[marker.lowerBound...], encoding: .utf8) else { throw InvalidFeed() }
    let content = Data(feed[..<marker.lowerBound])
    let lines = trailer.components(separatedBy: "\n")
    try require(lines.count == 5)
    try require(lines[0] == "<!-- sparkle-signatures:" && lines[1].hasPrefix("edSignature: "))
    try require(lines[2] == "length: \(content.count)" && lines[3] == "-->" && lines[4].isEmpty)
    try require(content.range(of: prefix) == nil)
    let signature = try decoded(String(lines[1].dropFirst("edSignature: ".count)), count: 64)
    try require(key.isValidSignature(signature, for: content))
    guard let text = String(data: content, encoding: .utf8) else { throw InvalidFeed() }
    try require(text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil)
    let xml = try XMLDocument(data: content, options: [.nodeLoadExternalEntitiesNever])
    try require(xml.dtd == nil)
    try require(try xml.nodes(forXPath: "/rss/channel").count == 1)
    let items = try xml.nodes(forXPath: "/rss/channel/item")
    try require(items.count == 1)
    guard let item = items.first as? XMLElement else { throw InvalidFeed() }
    let namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    func elements(_ name: String) -> [XMLNode] {
        (item.children ?? []).filter { $0.kind == .element && $0.localName == name && $0.uri == namespace }
    }
    for (name, expected) in [("version", build), ("shortVersionString", version)] {
        let nodes = elements(name)
        try require(nodes.count == 1 && nodes[0].stringValue == expected)
    }
    try require(elements("deltas").isEmpty && elements("releaseNotesLink").isEmpty && elements("fullReleaseNotesLink").isEmpty)
    let enclosures = try item.nodes(forXPath: "./enclosure")
    try require(enclosures.count == 1)
    guard let enclosure = enclosures.first as? XMLElement,
          let encoded = enclosure.attribute(forLocalName: "edSignature", uri: namespace)?.stringValue else { throw InvalidFeed() }
    try require(enclosure.attribute(forName: "url")?.stringValue == url && url.hasPrefix("https://github.com/denzam/SystemEQ-for-Mac/releases/download/"))
    try require(enclosure.attribute(forName: "length")?.stringValue == String(archive.count))
    try require(key.isValidSignature(decoded(encoded, count: 64), for: archive))
}

do {
    let args = CommandLine.arguments
    guard args.count == 7 else { throw InvalidFeed() }
    try verify(feed: Data(contentsOf: URL(fileURLWithPath: args[1])),
               archive: Data(contentsOf: URL(fileURLWithPath: args[2])),
               publicKey: args[3], url: args[4], build: args[5], version: args[6])
    print("Signed update feed and archive verified")
} catch {
    fputs("Update feed validation failed\n", stderr)
    exit(1)
}
