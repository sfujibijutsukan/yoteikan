import XCTest
@testable import Yoteikan

@MainActor final class MemoryDrive: DriveClient {
    var configured = true
    var identity = SyncAccount(id: "account-a", email: "a@example.invalid")
    var files: [String: [String: [SyncMutation]]] = [:]
    var failFetch = false
    var failUpload = false
    var restored = false
    var onUpload: (() -> Void)?
    func restore() async throws -> SyncAccount? { restored ? identity : nil }
    func login() async throws -> SyncAccount { identity }
    func logout() { restored = false }
    func fetch(known: Set<String>) async throws -> CloudChanges {
        if failFetch { throw SyncFailure.network(503) }
        let own = files[identity.id] ?? [:]
        return CloudChanges(mutations: own.filter { !known.contains($0.key) }.flatMap(\.value), fileIDs: Set(own.keys), hasData: !own.isEmpty)
    }
    func append(_ mutations: [SyncMutation]) async throws -> String {
        if failUpload { throw SyncFailure.network(503) }
        onUpload?(); onUpload = nil
        let id = UUID().uuidString
        files[identity.id, default: [:]][id] = mutations
        return id
    }
}
@MainActor final class SyncTests: XCTestCase {
    var defaults: UserDefaults!
    var domain: String!
    override func setUp() { super.setUp(); domain = "sync.tests." + UUID().uuidString; defaults = UserDefaults(suiteName: domain)! }
    override func tearDown() { defaults.removePersistentDomain(forName: domain); super.tearDown() }
    func plan(_ title: String = "読書") -> SavedPlan {
        var plan = SavedPlan(); plan.presets = []
        plan.stickies = [Sticky(title: title, minutes: 30, memo: "元のメモ", day: "2026-10-27", start: 480)]
        return plan
    }
    func store(_ plan: SavedPlan, defaults: UserDefaults? = nil) -> PlanStore {
        let target = defaults ?? self.defaults!
        target.set(SyncCodec.encode(plan), forKey: "yoteikan.plan.v1")
        return PlanStore(defaults: target)
    }
    func connected(_ plan: SavedPlan, drive: MemoryDrive) async -> (PlanStore, GoogleSyncStore) {
        let plans = store(plan)
        let sync = GoogleSyncStore(client: drive, defaults: defaults)
        await sync.attach(plans); await sync.login(); await sync.start(useCloud: false)
        return (plans, sync)
    }
    func testAdoptingCloudCreatesTodaysDailyNotesOnce() async throws {
        let drive = MemoryDrive()
        var remotePlan = SavedPlan(); remotePlan.presets = [Preset(title: "毎日の読書", minutes: 30)]
        var remote = SyncReplica(); remote.capture(remotePlan); _ = try await drive.append(remote.pending)
        let plans = store(plan("端末の用事")); let sync = GoogleSyncStore(client: drive, defaults: defaults)
        await sync.attach(plans); await sync.login(); await sync.start(useCloud: true); await sync.sync()
        XCTAssertEqual(plans.today.count, 1)
        XCTAssertEqual(plans.today[0].title, "毎日の読書")
        let firstID = plans.today[0].id
        await sync.sync()
        XCTAssertEqual(plans.today.map(\.id), [firstID])
        sync.logout()
    }
    func testInitialLoginDoesNotUploadBeforeExplicitChoice() async {
        let drive = MemoryDrive(); let plans = store(plan())
        let sync = GoogleSyncStore(client: drive, defaults: defaults)
        await sync.attach(plans); await sync.login()
        XCTAssertTrue(sync.needsInitialChoice)
        XCTAssertTrue(drive.files.isEmpty)
        XCTAssertEqual(plans.today.count, 1)
        await sync.start(useCloud: false)
        XCTAssertFalse(sync.needsInitialChoice)
        XCTAssertNotNil(sync.lastSync)
        XCTAssertFalse(drive.files[drive.identity.id, default: [:]].isEmpty)
    }
    func testCloudAdoptionPreservesRecoverableLocalBackup() async throws {
        let drive = MemoryDrive()
        var remote = SyncReplica(); let remotePlan = plan("クラウドの読書"); remote.capture(remotePlan)
        _ = try await drive.append(remote.pending)
        let local = plan("端末だけの用事"); let plans = store(local)
        let sync = GoogleSyncStore(client: drive, defaults: defaults)
        await sync.attach(plans); await sync.login()
        XCTAssertTrue(sync.cloudHasData)
        XCTAssertEqual(plans.plan, local)
        await sync.start(useCloud: true)
        XCTAssertEqual(plans.plan.stickies, remotePlan.stickies)
        XCTAssertNil(plans.undo)
        sync.logout(); sync.restoreBackup()
        XCTAssertEqual(plans.plan, local)
    }
    func testIndependentOfflineChangesAndDeletesConvergeWithoutResurrection() throws {
        let original = plan()
        var a = SyncReplica(); a.capture(original)
        var b = a
        var edit = original; edit.stickies[0].memo = "端末Aで編集"
        a.capture(edit)
        var addition = original
        let added = Sticky(title: "運動", minutes: 20, day: "2026-10-27")
        addition.stickies.append(added); b.capture(addition)
        try a.receive(b.mutations); try b.receive(a.mutations)
        let merged = try a.materialize(keepingConflictsFrom: edit)
        XCTAssertEqual(merged, try b.materialize(keepingConflictsFrom: addition))
        XCTAssertEqual(merged.stickies.first { $0.id == original.stickies[0].id }?.memo, "端末Aで編集")
        XCTAssertTrue(merged.stickies.contains(added))
        var removed = merged; removed.stickies.removeAll { $0.id == added.id }
        a.baseline = SyncCodec.atoms(merged); a.capture(removed)
        try b.receive(a.mutations)
        XCTAssertFalse(try b.materialize(keepingConflictsFrom: merged).stickies.contains { $0.id == added.id })
    }
    func testConcurrentEditAndDeletionRequireExplicitResolution() throws {
        let original = plan()
        var a = SyncReplica(); a.capture(original)
        var b = a
        var deleted = original; deleted.stickies = []; a.capture(deleted)
        var changed = original; changed.stickies[0].title = "別端末の編集"; b.capture(changed)
        try a.receive(b.mutations)
        XCTAssertEqual(a.conflicts.count, 1)
        let conflict = try XCTUnwrap(a.conflicts.first)
        let removal = try XCTUnwrap(conflict.choices.first { $0.value == nil })
        a.resolve(removal.key, value: nil)
        try b.receive(a.mutations)
        XCTAssertTrue(b.conflicts.isEmpty)
        XCTAssertTrue(try b.materialize(keepingConflictsFrom: changed).stickies.isEmpty)
    }
    func testDuplicateUploadsAreIdempotentAndIdenticalGenesisDoesNotConflict() throws {
        let original = plan()
        var a = SyncReplica(); a.capture(original)
        var b = SyncReplica(); b.capture(original)
        try b.receive(a.mutations + a.mutations)
        XCTAssertEqual(a.mutations.count, b.mutations.count)
        XCTAssertTrue(b.conflicts.isEmpty)
        XCTAssertEqual(try b.materialize(keepingConflictsFrom: original), original)
    }
    func testNetworkAndUploadFailuresKeepPendingChangesForRetry() async {
        let drive = MemoryDrive(); let (plans, sync) = await connected(plan(), drive: drive)
        var item = plans.plan.stickies[0]; item.memo = "オフラインの編集"; plans.update(item); sync.observe(plans.plan)
        drive.failFetch = true; await sync.sync()
        XCTAssertNotNil(sync.message); XCTAssertEqual(plans.plan.stickies[0].memo, item.memo)
        drive.failFetch = false; drive.failUpload = true; await sync.sync()
        XCTAssertNotNil(sync.message)
        drive.failUpload = false; await sync.sync()
        XCTAssertNil(sync.message)
        let uploaded = drive.files[drive.identity.id, default: [:]].values.flatMap { $0 }
        XCTAssertTrue(uploaded.contains { $0.value == SyncCodec.encode(item) })
        sync.logout()
    }
    func testAccountSwitchDoesNotUploadPreviousAccountData() async {
        let drive = MemoryDrive(); let (plans, sync) = await connected(plan(), drive: drive)
        sync.logout()
        drive.identity = SyncAccount(id: "account-b", email: "b@example.invalid")
        await sync.login(); await sync.sync()
        XCTAssertTrue(sync.needsInitialChoice)
        XCTAssertNil(drive.files["account-b"])
        XCTAssertEqual(plans.plan.stickies[0].title, "読書")
    }
    func testEditsMadeWhileLoggedOutUploadOnReturningToSameAccount() async {
        let drive = MemoryDrive(); let (plans, sync) = await connected(plan(), drive: drive)
        sync.logout()
        var task = plans.plan.stickies[0]; task.memo = "ログアウト中の編集"; plans.update(task)
        await sync.login()
        XCTAssertFalse(sync.needsInitialChoice)
        XCTAssertNil(sync.message)
        XCTAssertTrue(drive.files[drive.identity.id, default: [:]].values.flatMap { $0 }.contains { $0.value == SyncCodec.encode(task) })
        sync.logout()
    }
    func testEditsDuringUploadRemainPendingAndReachNextSync() async {
        let drive = MemoryDrive(); let (plans, sync) = await connected(plan(), drive: drive)
        var item = plans.plan.stickies[0]; item.memo = "最初の編集"; plans.update(item); sync.observe(plans.plan)
        drive.onUpload = {
            var newer = item; newer.memo = "通信中の追加編集"; plans.update(newer); sync.observe(plans.plan)
        }
        await sync.sync(); await sync.sync()
        XCTAssertEqual(plans.plan.stickies[0].memo, "通信中の追加編集")
        XCTAssertTrue(drive.files[drive.identity.id, default: [:]].values.flatMap { $0 }.contains { event in
            event.value.flatMap { try? SyncCodec.decode(Sticky.self, $0) }?.memo == "通信中の追加編集"
        })
        sync.logout()
    }
    func testNewDailyPresetIDsMatchAcrossOfflineDevices() throws {
        var a = SavedPlan(); var b = a
        a.populateDailyPresets(for: "2026-10-27"); b.populateDailyPresets(for: "2026-10-27")
        XCTAssertEqual(a.stickies, b.stickies)
        var first = SyncReplica(); first.capture(a)
        var second = SyncReplica(); second.capture(b)
        try first.receive(second.mutations)
        XCTAssertTrue(first.conflicts.isEmpty)
        XCTAssertEqual(try first.materialize(keepingConflictsFrom: a).stickies.count, a.stickies.count)
    }
    func testMalformedOrUnknownSchemaCannotReplaceLocalData() throws {
        let original = plan(); var replica = SyncReplica(); replica.capture(original)
        let before = replica
        let bad = SyncMutation(key: "hours", parents: [], value: SyncCodec.encode(PlanningHours(start: 800, end: 200)))
        XCTAssertThrowsError(try replica.receive([bad]))
        XCTAssertEqual(replica.mutations, before.mutations)
        XCTAssertThrowsError(try SyncBatch(version: 9, mutations: []).validated())
    }
}

final class DriveURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@MainActor final class DriveTransportTests: XCTestCase {
    func client() -> GoogleDriveClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DriveURLProtocol.self]
        return GoogleDriveClient(session: URLSession(configuration: config), tokenProvider: { "unit-test-token" })
    }
    override func tearDown() { DriveURLProtocol.handler = nil; super.tearDown() }
    func testListsAllPagesAndSkipsAlreadyDownloadedFiles() async throws {
        let event = SyncMutation(key: "hours", parents: [], value: SyncCodec.encode(PlanningHours()))
        let batch = SyncCodec.encode(SyncBatch(mutations: [event]))
        var requests: [URLRequest] = []
        DriveURLProtocol.handler = { request in
            requests.append(request)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
            let url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if query["alt"] == "media" { return (200, batch) }
            XCTAssertEqual(query["spaces"], "appDataFolder")
            if query["pageToken"] == "page-2" { return (200, Data("{\"files\":[{\"id\":\"new\",\"size\":\"100\"}]}".utf8)) }
            return (200, Data("{\"nextPageToken\":\"page-2\",\"files\":[{\"id\":\"known\",\"size\":\"100\"}]}".utf8))
        }
        let changes = try await client().fetch(known: ["known"])
        XCTAssertEqual(changes.fileIDs, ["known", "new"])
        XCTAssertEqual(changes.mutations, [event]); XCTAssertEqual(requests.count, 3)
    }
    func testWritesImmutableBatchOnlyToAppDataFolder() async throws {
        DriveURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url!.absoluteString.contains("uploadType=multipart"))
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096); var all = Data()
                while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; all.append(bytes, count: count) }
                body = all
            }
            let content = String(data: body ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(content.contains("appDataFolder")); XCTAssertTrue(content.contains("sync-v1"))
            XCTAssertFalse(content.contains("client_secret"))
            return (200, Data("{\"id\":\"new-file\"}".utf8))
        }
        let id = try await client().append([SyncMutation(key: "hours", parents: [], value: SyncCodec.encode(PlanningHours()))])
        XCTAssertEqual(id, "new-file")
    }
    func testQuotaFailureDoesNotAskForUnnecessaryLogin() async {
        DriveURLProtocol.handler = { _ in (403, Data("{\"error\":{\"errors\":[{\"reason\":\"userRateLimitExceeded\"}]}}".utf8)) }
        do { _ = try await client().fetch(known: []); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error.localizedDescription, SyncFailure.network(403).localizedDescription) }
    }
    func testRevokedTokenProducesReauthenticationMessage() async {
        DriveURLProtocol.handler = { _ in (401, Data()) }
        do { _ = try await client().fetch(known: []); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error.localizedDescription, SyncFailure.signIn.localizedDescription) }
    }
    func testMalformedRemoteBatchFailsWithoutReturningPartialChanges() async {
        DriveURLProtocol.handler = { request in
            if request.url!.query?.contains("alt=media") == true { return (200, Data("{\"version\":99,\"mutations\":[]}".utf8)) }
            return (200, Data("{\"files\":[{\"id\":\"bad\",\"size\":\"100\"}]}".utf8))
        }
        do { _ = try await client().fetch(known: []); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error.localizedDescription, SyncFailure.version.localizedDescription) }
    }
}
