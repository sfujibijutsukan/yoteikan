// Regenerate the cross-language wire fixture:
// swift tools/web-sync-fixture.swift > web/test/swift-fixture.json
import Foundation
import CryptoKit
struct Mutation: Encodable { let key: String; let parents: [String]; let value: Data? }
struct Hours: Encodable { let start: Int; let end: Int }
struct Fixture: Encodable { let mutation: Mutation; let sha256: String }
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
let mutation = Mutation(key: "hours", parents: [], value: try encoder.encode(Hours(start: 300, end: 1440)))
let digest = SHA256.hash(data: try encoder.encode(mutation)).map { String(format: "%02x", $0) }.joined()
print(String(data: try encoder.encode(Fixture(mutation: mutation, sha256: digest)), encoding: .utf8)!)
