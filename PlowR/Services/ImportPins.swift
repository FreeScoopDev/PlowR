import Foundation
import Observation
import SwiftData

/// Map pins for imported clients and properties, looked up in the background
/// one at a time: started by Import Clients right after an import, and again
/// at launch and whenever the app comes to the front, for the rest of a long
/// list. Apple's map limits how fast addresses can be looked up, so a long
/// list takes a while: about 30 a minute, slowing down when the map says
/// it's busy, and stopping until the app next comes to the front if it keeps
/// saying so. Nothing is kept but the pins and the marks: what's left is
/// found again from the store (`waiting`), so it carries on after a
/// relaunch. An address the map doesn't know is looked up once, never again
/// on its own (Joe's call: no time spent on it): its client or property is
/// marked (`addressNotFoundAt`, shown until it has a pin) for the business to
/// fix, and listed for this session (`notFound`). Only the signed-in business's
/// clients are looked up, and nothing at all after Delete Account or Remove
/// from This Device (`stop`) until the next import or launch.
@MainActor
@Observable
final class ImportPins {
    static let shared = ImportPins()

    /// An address the map didn't know.
    struct Missed: Equatable, Identifiable {
        var id: UUID
        var name: String
        var address: String
    }

    /// Looked up so far this session, and how many in all: they add up over
    /// runs, so a finished import still reads 300 of 300.
    private(set) var done = 0
    private(set) var total = 0
    private(set) var notFound: [Missed] = []
    private(set) var isRunning = false
    /// Stopped because the map kept refusing (no signal, or its limit):
    /// picks up when the app next comes to the front.
    private(set) var isWaiting = false

    /// Between lookups: 30 a minute, under Apple's limit of about 50, with
    /// room for the app's own (an address typed on a client's page).
    static let spacing: Duration = .seconds(2)
    /// After each refusal in a row; one more and it stops.
    static let backoff: [Duration] = [.seconds(30), .seconds(60), .seconds(120)]
    /// Saved every this many pins, so a stop loses little.
    static let saveEvery = 25

    private let lookUp: (String) async -> AddressPin.Lookup
    private let pause: (Duration) async -> Void
    private let now: () -> Date
    /// This session's misses (marked in the store too).
    private var missedIDs = Set<UUID>()
    /// Counted in `total` already, and done: `done` is how many of those
    /// are finished, so it never passes `total`.
    private var counted = Set<UUID>()
    private var finished = Set<UUID>()
    /// Asked to run while running (another import, or another business
    /// signed in): runs again after, for the latest one asked.
    private var runAgainFor: String?
    /// Delete Account or Remove from This Device: no lookups until an
    /// import asks (`startAfterImport`) or the app is launched again.
    private var halted = false
    /// The business this session's misses and counts are for.
    private var sessionOperatorID = ""
    private var stopped = false

    init(lookUp: @escaping (String) async -> AddressPin.Lookup = { await AddressPin.lookUp($0) },
         pause: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         now: @escaping () -> Date = { .now }) {
        self.lookUp = lookUp
        self.pause = pause
        self.now = now
    }

    /// A client or property awaiting its pin, by ID: fetched afresh each
    /// time it's used, since a run can last an hour and the record can be
    /// deleted meanwhile, here or on another device.
    enum Target: Equatable {
        case client(UUID)
        case property(UUID)

        var id: UUID {
            switch self {
            case let .client(id), let .property(id): id
            }
        }
    }

    /// What's still to pin of a target: nil if it's gone, pinned, or has no address.
    private struct Spot {
        var address: String
        var name: String
        var pin: (Double, Double) -> Void
        /// The map didn't know it: marked for the business, not tried again.
        var markNotFound: (Date) -> Void
    }

    private func spot(_ target: Target, in context: ModelContext) -> Spot? {
        switch target {
        case let .client(id):
            guard let client = try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })).first,
                  !AddressPin.exists(latitude: client.latitude, longitude: client.longitude) else { return nil }
            return Spot(address: client.address, name: client.name, pin: { latitude, longitude in
                client.latitude = latitude
                client.longitude = longitude
                ClientStops.update(for: client)
            }, markNotFound: { client.addressNotFoundAt = $0 })
        case let .property(id):
            guard let property = try? context.fetch(FetchDescriptor<Property>(predicate: #Predicate { $0.id == id })).first,
                  !AddressPin.exists(latitude: property.latitude, longitude: property.longitude) else { return nil }
            let name = [property.client?.name, property.label].compactMap { $0 }.filter { !$0.isEmpty }
                .joined(separator: ", ")
            return Spot(address: property.address, name: name, pin: { latitude, longitude in
                property.latitude = latitude
                property.longitude = longitude
                if let owner = property.client { ClientStops.update(for: owner) }
            }, markNotFound: { property.addressNotFoundAt = $0 })
        }
    }

    /// What imports left without a pin, of `operatorID`'s: clients carrying
    /// an import's tag, and properties an import added. Those are known by
    /// their whole-second creation time (ClientImport.save); one made by
    /// hand has a fraction of a second, but the rare one that doesn't is
    /// only given the pin it lacks. Clients first, oldest first.
    static func waiting(in context: ModelContext, operatorID: String, skipping skipped: Set<UUID> = []) -> [Target] {
        let clients = (try? context.fetch(FetchDescriptor<Client>(
            predicate: #Predicate { $0.operatorID == operatorID && $0.latitude == 0 && $0.longitude == 0 },
            sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let properties = (try? context.fetch(FetchDescriptor<Property>(
            predicate: #Predicate { $0.operatorID == operatorID && $0.latitude == 0 && $0.longitude == 0 },
            sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        func hasAddress(_ address: String) -> Bool { !address.trimmingCharacters(in: .whitespaces).isEmpty }
        let fromClients = clients
            .filter { client in hasAddress(client.address) && !skipped.contains(client.id) && client.addressNotFoundAt == nil
                && client.tags.contains { ClientImport.isImportTag($0) } }
            .map { Target.client($0.id) }
        let fromProperties = properties
            .filter { property in
                hasAddress(property.address) && !skipped.contains(property.id) && property.addressNotFoundAt == nil
                    && ClientImport.isImportMoment(property.createdAt)
            }
            .map { Target.property($0.id) }
        return fromClients + fromProperties
    }

    /// Right after an import: looks up its pins, even after a `stop`.
    func startAfterImport(in context: ModelContext, operatorID: String) async {
        halted = false
        await run(in: context, operatorID: operatorID)
    }

    /// Looks up what's waiting, one at a time, until it's all done or the
    /// map keeps refusing. Asked while running (a second import), it runs
    /// again once this run ends, for what the first didn't know of. Nothing
    /// without a business signed in, or after `stop`.
    func run(in context: ModelContext, operatorID: String) async {
        guard !halted, !operatorID.isEmpty else { return }
        guard !isRunning else {
            runAgainFor = operatorID
            return
        }
        // Another business signed in: what's shown starts afresh.
        if operatorID != sessionOperatorID {
            forgetSession()
            sessionOperatorID = operatorID
        }
        isRunning = true
        isWaiting = false
        stopped = false
        runAgainFor = nil
        let targets = Self.waiting(in: context, operatorID: operatorID, skipping: missedIDs)
        let new = targets.filter { counted.insert($0.id).inserted }.count
        total += new
        var refusals = 0
        var index = 0
        var unsaved = 0
        while index < targets.count, !stopped, !Task.isCancelled {
            let target = targets[index]
            guard let before = spot(target, in: context), !before.address.isEmpty else {
                // Deleted, pinned, or its address cleared meanwhile.
                index += 1
                finish(target)
                continue
            }
            let address = before.address
            let result = await lookUp(address)
            guard !stopped else { break }
            // Fetched again: it may have been edited (its screen pins it) or
            // deleted while the map answered.
            let after = spot(target, in: context).flatMap { $0.address == address ? $0 : nil }
            switch result {
            case let .found(latitude, longitude):
                if let after {
                    after.pin(latitude, longitude)
                    unsaved += 1
                }
                refusals = 0
            case .failed(.notFound):
                if let after {
                    after.markNotFound(now())
                    unsaved += 1
                    missedIDs.insert(target.id)
                    notFound.append(Missed(id: target.id, name: after.name, address: address))
                }
                refusals = 0
            case .failed(.unreachable):
                if refusals < Self.backoff.count {
                    await pause(Self.backoff[refusals])
                    refusals += 1
                    continue
                }
                isWaiting = true
            }
            if isWaiting { break }
            index += 1
            finish(target)
            if unsaved >= Self.saveEvery {
                try? context.save()
                unsaved = 0
            }
            if index < targets.count { await pause(Self.spacing) }
        }
        if unsaved > 0, !stopped { try? context.save() }
        isRunning = false
        if let next = runAgainFor, !halted, !isWaiting {
            await run(in: context, operatorID: next)
        }
    }

    private func finish(_ target: Target) {
        finished.insert(target.id)
        done = finished.count
    }

    /// Stops a run in progress, without holding off the next: the business
    /// signed out, so its lookups, misses and counts end with it.
    func cancelRun() {
        if isRunning { stopped = true }
        runAgainFor = nil
        forgetSession()
    }

    /// Stops a run and forgets this session: Delete Account and Remove from
    /// This Device. Nothing more is looked up until an import or a launch.
    func stop() {
        stopped = true
        halted = true
        runAgainFor = nil
        forgetSession()
    }

    /// The misses and counts shown on the import screen.
    private func forgetSession() {
        notFound = []
        missedIDs = []
        counted = []
        finished = []
        done = 0
        total = 0
        isWaiting = false
    }
}
