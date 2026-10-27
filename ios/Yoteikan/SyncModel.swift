import Foundation
import CryptoKit

// Immutable, content-addressed mutations make duplicate uploads harmless and
// avoid overwriting another device's concurrent Drive writes.
struct SyncMutation: Codable, Equatable, Identifiable {
    let key: String
    let parents: [String]
    let value: Data?
    var id: String { SHA256.hash(data: try! SyncCodec.encoder.encode(self)).map { String(format: "%02x", $0) }.joined() }
}
enum SyncCodec {
    static func dailyStickyID(preset: UUID, day: String, index: Int) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("yoteikan.daily.v1/\(preset.uuidString)/\(day)/\(index)".utf8)))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    static var encoder: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return encoder }
    static func encode<T: Encodable>(_ value: T) -> Data { try! encoder.encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T { try JSONDecoder().decode(type, from: data) }
    static func atoms(_ plan: SavedPlan) -> [String: Data] {
        var result = ["hours": encode(plan.hours), "colors": encode(plan.colors)]
        for item in plan.stickies { result["sticky/" + item.id.uuidString] = encode(item) }
        for item in plan.presets { result["preset/" + item.id.uuidString] = encode(item) }
        for (day, counts) in plan.dailyPresetCounts { result["daily/" + day] = encode(counts) }
        return result
    }
    static func validate(_ event: SyncMutation) throws {
        guard event.parents.count < 10_000, event.parents.allSatisfy({ $0.count == 64 }), event.key.count < 100 else { throw SyncFailure.invalidData }
        let parts = event.key.split(separator: "/").map(String.init)
        if event.key == "hours" {
            guard let value = event.value, try decode(PlanningHours.self, value).isValid else { throw SyncFailure.invalidData }
        } else if event.key == "colors" {
            guard let value = event.value else { throw SyncFailure.invalidData }
            let colors = try decode([StickyColor].self, value)
            guard !colors.isEmpty, colors.count <= 1000, Set(colors.map(\.id)).count == colors.count,
                  colors.allSatisfy({ StickyColor.validHex($0.hex) && !$0.name.isEmpty }) else { throw SyncFailure.invalidData }
        } else if parts.count == 2, parts[0] == "sticky", let id = UUID(uuidString: parts[1]) {
            if let value = event.value {
                let task = try decode(Sticky.self, value)
                guard task.id == id, (5...720).contains(task.minutes), task.day.count == 10,
                      task.start.map({ $0 >= 0 && $0 + task.minutes <= 1440 }) ?? true else { throw SyncFailure.invalidData }
            }
        } else if parts.count == 2, parts[0] == "preset", let id = UUID(uuidString: parts[1]) {
            if let value = event.value {
                let preset = try decode(Preset.self, value)
                guard preset.id == id, (5...720).contains(preset.minutes) else { throw SyncFailure.invalidData }
            }
        } else if parts.count == 2, parts[0] == "daily", parts[1].count == 10 {
            if let value = event.value {
                let counts = try decode([String: Int].self, value)
                guard counts.allSatisfy({ UUID(uuidString: $0.key) != nil && (0...20).contains($0.value) }) else { throw SyncFailure.invalidData }
            }
        } else { throw SyncFailure.invalidData }
    }
}
enum SyncFailure: LocalizedError {
    case configuration, signIn, permission, invalidData, version, network(Int), missingAccount
    var errorDescription: String? {
        switch self {
        case .configuration: return "Googleログインの設定がまだ完了していません。開発者向けの設定手順を確認してください。"
        case .signIn: return "Googleにログインし直してください。端末の予定は保持されています。"
        case .permission: return "同期用データへのアクセスを許可して、もう一度ログインしてください。"
        case .invalidData: return "同期データを読み込めませんでした。端末の予定は変更していません。"
        case .version: return "新しい形式の同期データです。アプリを更新してください。"
        case .network(let code): return "同期できませんでした（\(code)）。通信環境を確認して再試行してください。"
        case .missingAccount: return "Googleでログインして同期を開始してください。"
        }
    }
}
struct SyncBatch: Codable {
    var version = 1
    var mutations: [SyncMutation]
    func validated() throws -> [SyncMutation] {
        guard version == 1 else { throw SyncFailure.version }
        guard mutations.count <= 100_000 else { throw SyncFailure.invalidData }
        try mutations.forEach(SyncCodec.validate)
        return mutations
    }
}
struct SyncConflict: Identifiable {
    let id: String
    let choices: [SyncMutation]
    var title: String {
        if id == "hours" { return "計画の時間帯" }
        if id == "colors" { return "付箋の色・名前" }
        return id.hasPrefix("preset/") ? "プリセットの変更" : "付箋の変更"
    }
    static func summary(_ mutation: SyncMutation) -> String {
        guard let data = mutation.value else { return "削除する" }
        if let item = try? SyncCodec.decode(Sticky.self, data) {
            return "\(item.title)・\(item.day)・\(item.start.map(clockText) ?? "未配置")・\(item.minutes)分\n\(item.memo)"
        }
        if let item = try? SyncCodec.decode(Preset.self, data) { return "\(item.title)・\(item.minutes)分・毎日\(item.dailyCount)枚\n\(item.memo)" }
        if let hours = try? SyncCodec.decode(PlanningHours.self, data) { return hours.label }
        if let colors = try? SyncCodec.decode([StickyColor].self, data) { return colors.map { "\($0.name) #\($0.hex)" }.joined(separator: " / ") }
        return "別の端末からの変更"
    }
}
struct SyncReplica: Codable {
    var mutations: [SyncMutation] = []
    var uploaded = Set<String>()
    var downloaded = Set<String>()
    var baseline: [String: Data] = [:]
    var initialized = false
    var lastSync: Date?
    func heads(_ key: String) -> [SyncMutation] {
        let all = mutations.filter { $0.key == key }
        let parents = Set(all.flatMap(\.parents))
        return all.filter { !parents.contains($0.id) }.sorted { $0.id < $1.id }
    }
    var conflicts: [SyncConflict] {
        Set(mutations.map(\.key)).sorted().compactMap { key in
            let choices = heads(key)
            guard !key.hasPrefix("daily/"), choices.count > 1,
                  choices.dropFirst().contains(where: { $0.value != choices.first?.value }) else { return nil }
            return SyncConflict(id: key, choices: choices)
        }
    }
    mutating func receive(_ incoming: [SyncMutation]) throws {
        try incoming.forEach(SyncCodec.validate)
        var all = Dictionary(uniqueKeysWithValues: mutations.map { ($0.id, $0) })
        for item in incoming { all[item.id] = item }
        for item in all.values {
            for parent in item.parents {
                if let known = all[parent], known.key != item.key { throw SyncFailure.invalidData }
            }
        }
        mutations = all.values.sorted { $0.id < $1.id }
    }
    mutating func capture(_ plan: SavedPlan) {
        let values = SyncCodec.atoms(plan)
        for key in Set(values.keys).union(baseline.keys).sorted() where values[key] != baseline[key] {
            resolve(key, value: values[key])
        }
        baseline = values
    }
    mutating func resolve(_ key: String, value: Data?) {
        let event = SyncMutation(key: key, parents: heads(key).map(\.id).sorted(), value: value)
        if !mutations.contains(where: { $0.id == event.id }) { mutations.append(event) }
    }
    func materialize(keepingConflictsFrom local: SavedPlan) throws -> SavedPlan {
        var values = SyncCodec.atoms(local)
        let conflictKeys = Set(conflicts.map(\.id))
        for key in Set(mutations.map(\.key)) where !conflictKeys.contains(key) {
            let candidates = heads(key)
            if key.hasPrefix("daily/") {
                var maximum: [String: Int] = [:]
                for candidate in candidates {
                    if let data = candidate.value {
                        for (id, count) in try SyncCodec.decode([String: Int].self, data) { maximum[id] = max(maximum[id] ?? 0, count) }
                    }
                }
                values[key] = SyncCodec.encode(maximum)
            } else { values[key] = candidates.first?.value }
        }
        var result = SavedPlan()
        result.stickies = []; result.presets = []; result.dailyPresetCounts = [:]
        for key in values.keys.sorted() {
            let data = values[key]!
            if key == "hours" { result.hours = try SyncCodec.decode(PlanningHours.self, data) }
            else if key == "colors" { result.colors = try SyncCodec.decode([StickyColor].self, data) }
            else if key.hasPrefix("sticky/") { result.stickies.append(try SyncCodec.decode(Sticky.self, data)) }
            else if key.hasPrefix("preset/") { result.presets.append(try SyncCodec.decode(Preset.self, data)) }
            else if key.hasPrefix("daily/") { result.dailyPresetCounts[String(key.dropFirst(6))] = try SyncCodec.decode([String: Int].self, data) }
        }
        return result
    }
    var pending: [SyncMutation] { mutations.filter { !uploaded.contains($0.id) } }
}
