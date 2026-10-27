import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import UIKit
import CryptoKit

struct SyncAccount: Codable, Equatable { let id: String; let email: String }
struct CloudChanges { let mutations: [SyncMutation]; let fileIDs: Set<String>; let hasData: Bool }
@MainActor protocol DriveClient {
    var configured: Bool { get }
    func restore() async throws -> SyncAccount?
    func login() async throws -> SyncAccount
    func logout()
    func fetch(known: Set<String>) async throws -> CloudChanges
    func append(_ mutations: [SyncMutation]) async throws -> String
}
@MainActor final class GoogleDriveClient: DriveClient {
    static let scope = "https://www.googleapis.com/auth/drive.appdata"
    let session: URLSession
    private let tokenProvider: (() async throws -> String)?
    init(session: URLSession = .shared, tokenProvider: (() async throws -> String)? = nil) {
        self.session = session; self.tokenProvider = tokenProvider
    }
    var configured: Bool {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              id.hasSuffix(".apps.googleusercontent.com"), !id.contains("$") else { return false }
        let reversed = id.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(reversed) == true }
    }
    private func account(_ user: GIDGoogleUser) throws -> SyncAccount {
        guard let id = user.userID else { throw SyncFailure.signIn }
        guard user.grantedScopes?.contains(Self.scope) == true else { throw SyncFailure.permission }
        return SyncAccount(id: id, email: user.profile?.email ?? "Googleアカウント")
    }
    func restore() async throws -> SyncAccount? {
        guard configured, GIDSignIn.sharedInstance.hasPreviousSignIn() else { return nil }
        return try account(await GIDSignIn.sharedInstance.restorePreviousSignIn())
    }
    func login() async throws -> SyncAccount {
        guard configured else { throw SyncFailure.configuration }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow),
              var presenter = window.rootViewController else { throw SyncFailure.signIn }
        while let presented = presenter.presentedViewController { presenter = presented }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: [Self.scope])
        return try account(result.user)
    }
    func logout() { GIDSignIn.sharedInstance.signOut() }
    private func request(_ url: URL, method: String = "GET", body: Data? = nil, contentType: String? = nil) async throws -> Data {
        let token: String
        if let tokenProvider { token = try await tokenProvider() }
        else {
            guard let user = GIDSignIn.sharedInstance.currentUser else { throw SyncFailure.missingAccount }
            _ = try account(user)
            token = try await user.refreshTokensIfNeeded().accessToken.tokenString
        }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SyncFailure.network(0) }
        if response.statusCode == 401 { throw SyncFailure.signIn }
        if response.statusCode == 403,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let details = error["errors"] as? [[String: Any]],
           details.contains(where: { $0["reason"] as? String == "insufficientPermissions" }) {
            throw SyncFailure.permission
        }
        guard (200..<300).contains(response.statusCode) else { throw SyncFailure.network(response.statusCode) }
        guard data.count <= 8_000_000 else { throw SyncFailure.invalidData }
        return data
    }
    func fetch(known: Set<String>) async throws -> CloudChanges {
        struct File: Decodable { let id: String; let size: String? }
        struct Page: Decodable { let files: [File]; let nextPageToken: String? }
        var token: String?; var files: [File] = []
        repeat {
            var url = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            url.queryItems = [URLQueryItem(name: "spaces", value: "appDataFolder"),
                              URLQueryItem(name: "q", value: "appProperties has { key='yoteikan' and value='sync-v1' }"),
                              URLQueryItem(name: "fields", value: "nextPageToken,files(id,size)"), URLQueryItem(name: "pageSize", value: "1000")]
            if let token { url.queryItems?.append(URLQueryItem(name: "pageToken", value: token)) }
            let page = try SyncCodec.decode(Page.self, await request(url.url!))
            files += page.files; token = page.nextPageToken
            guard files.count <= 100_000 else { throw SyncFailure.invalidData }
        } while token != nil
        var mutations: [SyncMutation] = []
        for file in files where !known.contains(file.id) {
            guard let size = file.size.flatMap(Int.init), size <= 8_000_000 else { throw SyncFailure.invalidData }
            let data = try await request(URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)?alt=media")!)
            mutations += try SyncCodec.decode(SyncBatch.self, data).validated()
        }
        return CloudChanges(mutations: mutations, fileIDs: Set(files.map(\.id)), hasData: !files.isEmpty)
    }
    func append(_ mutations: [SyncMutation]) async throws -> String {
        let boundary = "yoteikan-" + UUID().uuidString
        let metadata: [String: Any] = ["name": "yoteikan-sync-v1-\(UUID().uuidString).json", "parents": ["appDataFolder"],
                                       "mimeType": "application/json", "appProperties": ["yoteikan": "sync-v1"]]
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body += try JSONSerialization.data(withJSONObject: metadata)
        body += Data("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8)
        let payload = SyncCodec.encode(SyncBatch(mutations: mutations))
        guard payload.count <= 8_000_000 else { throw SyncFailure.invalidData }
        body += payload
        body += Data("\r\n--\(boundary)--\r\n".utf8)
        struct Created: Decodable { let id: String }
        let data = try await request(URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id")!,
                                     method: "POST", body: body, contentType: "multipart/related; boundary=\(boundary)")
        return try SyncCodec.decode(Created.self, data).id
    }
}

@MainActor final class GoogleSyncStore: ObservableObject {
    @Published private(set) var account: SyncAccount?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var conflicts: [SyncConflict] = []
    @Published private(set) var pendingCount = 0
    @Published private(set) var needsInitialChoice = false
    @Published private(set) var cloudHasData = false
    let client: any DriveClient
    private let defaults: UserDefaults
    private weak var plans: PlanStore?
    private var replica = SyncReplica()
    private var loadedAccount: String?
    private var debounce: Task<Void, Never>?
    private var initialCloud: CloudChanges?
    private var retryRequested = false
    private var applying = false
    init(client: (any DriveClient)? = nil, defaults: UserDefaults = .standard) {
        self.client = client ?? GoogleDriveClient(); self.defaults = defaults
    }
    var configured: Bool { client.configured }
    private var owner: String? { defaults.string(forKey: "yoteikan.sync.owner") }
    private func storageKey(_ id: String) -> String { "yoteikan.sync." + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func persist() {
        guard let id = loadedAccount else { return }
        defaults.set(SyncCodec.encode(replica), forKey: storageKey(id))
        lastSync = replica.lastSync; conflicts = replica.conflicts; pendingCount = replica.pending.count
    }
    func attach(_ plans: PlanStore) async {
        guard self.plans == nil else { return }
        self.plans = plans
        if plans.demo {
            #if DEBUG && targetEnvironment(simulator)
            guard ProcessInfo.processInfo.arguments.contains("--sync-test") else { return }
            #else
            return
            #endif
        }
        do {
            if let account = try await client.restore() { activate(account); await sync() }
        } catch { message = "Googleに接続できませんでした。設定からログインし直すか、同期を再試行してください。" }
    }
    private func activate(_ account: SyncAccount) {
        self.account = account; loadedAccount = account.id
        replica = defaults.data(forKey: storageKey(account.id)).flatMap { try? SyncCodec.decode(SyncReplica.self, $0) } ?? SyncReplica()
        conflicts = replica.conflicts; lastSync = replica.lastSync; pendingCount = replica.pending.count
        needsInitialChoice = false; initialCloud = nil
    }
    func login() async {
        guard !busy else { return }
        busy = true; message = nil; debounce?.cancel()
        do { activate(try await client.login()) }
        catch {
            busy = false
            if (error as NSError).domain == kGIDSignInErrorDomain && (error as NSError).code == GIDSignInError.canceled.rawValue { return }
            message = (error as? SyncFailure)?.localizedDescription ?? "Googleログインを完了できませんでした。もう一度お試しください。"
            return
        }
        busy = false
        await sync()
    }
    func logout() {
        guard !busy else { return }
        debounce?.cancel(); debounce = nil
        client.logout(); account = nil; loadedAccount = nil
        replica = SyncReplica(); conflicts = []; lastSync = nil; pendingCount = 0; message = nil
        needsInitialChoice = false; initialCloud = nil
    }
    func observe(_ plan: SavedPlan) {
        guard !applying, let account, owner == account.id, replica.initialized else { return }
        replica.capture(plan); persist()
        schedule()
    }
    private func schedule() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }
    func sync() async {
        guard let account, let plans else { return }
        if busy { retryRequested = true; return }
        busy = true; message = nil
        defer {
            busy = false
            if retryRequested { retryRequested = false; schedule() }
        }
        do {
            if owner != account.id || !replica.initialized {
                let cloud = try await client.fetch(known: [])
                var checked = SyncReplica(); try checked.receive(cloud.mutations)
                initialCloud = cloud; cloudHasData = cloud.hasData; needsInitialChoice = true
                return
            }
            replica.capture(plans.plan); persist()
            let cloud = try await client.fetch(known: replica.downloaded)
            // Local edits may have occurred while the network request was pending.
            replica.capture(plans.plan)
            try replica.receive(cloud.mutations)
            replica.downloaded.formUnion(cloud.fileIDs)
            // If the app's Drive data was removed, republish the local journal.
            if !cloud.hasData { replica.uploaded = [] }
            try apply()
            persist()
            let pending = replica.pending
            if !pending.isEmpty {
                let file = try await client.append(pending)
                replica.uploaded.formUnion(pending.map(\.id)); replica.downloaded.insert(file)
            }
            replica.lastSync = Date(); persist()
            if !conflicts.isEmpty { message = "同じ項目に別々の変更があります。残す内容を選んでください。" }
        } catch {
            persist()
            message = (error as? SyncFailure)?.localizedDescription ?? "同期できませんでした。端末の変更は保存されています。通信環境を確認して再試行してください。"
        }
    }
    func start(useCloud: Bool) async {
        guard !busy, let account, let cloud = initialCloud, let plans else { return }
        do {
            // Preserve the complete local plan before explicitly switching data sets.
            defaults.set(SyncCodec.encode(plans.plan), forKey: "yoteikan.sync.beforeStart")
            var next = SyncReplica()
            if !useCloud { next.capture(plans.plan) }
            try next.receive(cloud.mutations)
            next.downloaded = cloud.fileIDs; next.uploaded = Set(cloud.mutations.map(\.id))
            next.initialized = true
            replica = next; defaults.set(account.id, forKey: "yoteikan.sync.owner")
            if useCloud {
                var empty = SavedPlan(); empty.stickies = []; empty.presets = []; empty.dailyPresetCounts = [:]
                let imported = try replica.materialize(keepingConflictsFrom: empty)
                replica.baseline = SyncCodec.atoms(imported)
                applying = true; plans.acceptSyncedPlan(imported); applying = false
            }
            needsInitialChoice = false; initialCloud = nil
            persist(); await sync()
        } catch { message = (error as? SyncFailure)?.localizedDescription ?? "同期を開始できませんでした。" }
    }
    private func apply() throws {
        guard let plans else { return }
        let merged = try replica.materialize(keepingConflictsFrom: plans.plan)
        replica.baseline = SyncCodec.atoms(merged)
        applying = true; plans.acceptSyncedPlan(merged); applying = false
    }
    func resolve(_ event: SyncMutation) async {
        guard !busy else { return }
        replica.resolve(event.key, value: event.value)
        do { try apply(); persist(); await sync() }
        catch { message = SyncFailure.invalidData.localizedDescription }
    }
    var hasBackup: Bool { defaults.data(forKey: "yoteikan.sync.beforeStart") != nil }
    func restoreBackup() {
        guard !busy, let data = defaults.data(forKey: "yoteikan.sync.beforeStart"), let backup = try? SyncCodec.decode(SavedPlan.self, data), let plans else { return }
        plans.acceptSyncedPlan(backup); observe(backup)
        message = "同期開始前の端末データを復元しました。"
    }
}

struct GoogleSyncView: View {
    @EnvironmentObject private var sync: GoogleSyncStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingLogout = false
    @State private var confirmingBackup = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let account = sync.account {
                        Label(account.email, systemImage: "person.crop.circle").accessibilityIdentifier("googleAccount")
                        if let date = sync.lastSync { Text("最終同期 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).accessibilityIdentifier("googleLastSync") }
                        if sync.pendingCount > 0 { Text("未送信の変更 \(sync.pendingCount)件").font(.caption).accessibilityIdentifier("googlePending") }
                        Button("今すぐ同期") { Task { await sync.sync() } }.accessibilityIdentifier("googleSyncNow")
                        Button("Googleに再ログイン") { Task { await sync.login() } }
                        Button("ログアウト", role: .destructive) { confirmingLogout = true }.accessibilityIdentifier("googleLogout")
                    } else {
                        Text("Google Driveを使って、予定・付箋・メモ・プリセットを端末間で同期します。")
                        GoogleSignInButton { Task { await sync.login() } }.accessibilityLabel("Googleでログイン").accessibilityIdentifier("googleLogin")
                    }
                    if sync.busy { ProgressView("接続中…").accessibilityIdentifier("googleSyncBusy") }
                } header: { Text("Googleアカウント") } footer: {
                    Text("データはDriveのアプリ専用領域に保存します。カレンダーから読み込んだ予定、通知の許可、画面の表示設定は同期しません。ログアウトしても端末の予定は残ります。")
                }.disabled(sync.busy)
                if !sync.configured && sync.message == nil {
                    Section { Text("Googleログインの設定がまだ完了していません。開発者による接続設定が必要です。").accessibilityIdentifier("googleNotConfigured") }
                }
                if sync.needsInitialChoice {
                    Section {
                        if sync.cloudHasData {
                            Button("クラウドの予定を使う") { Task { await sync.start(useCloud: true) } }.accessibilityIdentifier("googleUseCloud")
                            Button("このiPhoneの予定も追加する") { Task { await sync.start(useCloud: false) } }.accessibilityIdentifier("googleUseLocal")
                        } else {
                            Button("このiPhoneの予定で同期を開始") { Task { await sync.start(useCloud: false) } }.accessibilityIdentifier("googleUseLocal")
                        }
                    } header: { Text("同期するデータを選ぶ") } footer: {
                        Text("選ぶまでは端末の予定をアップロードしません。同期開始前の端末データは復元用に保存します。")
                    }.disabled(sync.busy)
                }
                if let message = sync.message { Section { Text(message).accessibilityIdentifier("googleSyncMessage") } }
                ForEach(sync.conflicts) { conflict in
                    Section(conflict.title) {
                        ForEach(conflict.choices) { choice in
                            Button { Task { await sync.resolve(choice) } } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(SyncConflict.summary(choice)).foregroundStyle(ink)
                                    Text("この内容を使う").font(.caption).foregroundStyle(accent)
                                }
                            }.accessibilityIdentifier("googleResolve-" + choice.id)
                        }
                    }.disabled(sync.busy)
                }
                if sync.hasBackup {
                    Section { Button("同期開始前の端末データを復元") { confirmingBackup = true }.accessibilityIdentifier("googleRestoreBackup") }.disabled(sync.busy)
                }
            }.scrollContentBackground(.hidden).background(paper)
                .navigationTitle("アカウント・同期").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
                .confirmationDialog("ログアウトしますか？端末とDriveの予定は残ります。", isPresented: $confirmingLogout) {
                    Button("ログアウト", role: .destructive) { sync.logout() }
                }
                .confirmationDialog("現在の端末データを同期開始前の内容に戻します。同期中の場合は変更も同期されます。", isPresented: $confirmingBackup) {
                    Button("復元する", role: .destructive) { sync.restoreBackup() }
                }
        }
    }
}

extension GoogleSyncStore {
    static func forLaunch() -> GoogleSyncStore {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--sync-test") {
            let defaults = UserDefaults(suiteName: "yoteikan.sync.ui-fixture")!
            defaults.removePersistentDomain(forName: "yoteikan.sync.ui-fixture")
            return GoogleSyncStore(client: PreviewDriveClient(), defaults: defaults)
        }
        if ProcessInfo.processInfo.environment["YOTEIKAN_UI_TEST"] == "1" ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil {
            return GoogleSyncStore(client: UnconfiguredTestDriveClient())
        }
        #endif
        return GoogleSyncStore()
    }
}
#if DEBUG && targetEnvironment(simulator)
private final class UnconfiguredTestDriveClient: DriveClient {
    let configured = false
    func restore() async throws -> SyncAccount? { nil }
    func login() async throws -> SyncAccount { throw SyncFailure.configuration }
    func logout() {}
    func fetch(known: Set<String>) async throws -> CloudChanges { throw SyncFailure.missingAccount }
    func append(_ mutations: [SyncMutation]) async throws -> String { throw SyncFailure.missingAccount }
}
private final class PreviewDriveClient: DriveClient {
    let configured = true
    private var files: [String: [SyncMutation]] = [:]
    private var reads = 0
    func restore() async throws -> SyncAccount? { nil }
    func login() async throws -> SyncAccount { SyncAccount(id: "ui-test-account", email: "動作確認用：demo@example.invalid") }
    func logout() {}
    func fetch(known: Set<String>) async throws -> CloudChanges {
        reads += 1
        if ProcessInfo.processInfo.arguments.contains("--sync-error-test"), reads == 2 { throw SyncFailure.network(503) }
        return CloudChanges(mutations: files.filter { !known.contains($0.key) }.flatMap(\.value), fileIDs: Set(files.keys), hasData: !files.isEmpty)
    }
    func append(_ mutations: [SyncMutation]) async throws -> String { let id = UUID().uuidString; files[id] = mutations; return id }
}
#endif
