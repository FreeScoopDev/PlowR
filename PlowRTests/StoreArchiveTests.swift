//
//  StoreArchiveTests.swift
//  PlowRTests
//

import CoreData
import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Three versions of a tiny model, to judge real stores with: a second that
/// migrates from the first (an added optional field), and a third that can't
/// (a field's type changed).
enum StoreV1 { @Model final class Item { var name: String = ""; init() {} } }
enum StoreV2 { @Model final class Item { var name: String = ""; var note: String?; init() {} } }
enum StoreV3 { @Model final class Item { var name: Int = 0; init() {} } }

/// Moving a database that can't be opened aside. It looked in the wrong folder
/// on a signed build, and moving a store aside for any failure would hide the
/// data behind an empty app, so only a store that can't be migrated is moved.
@MainActor
struct StoreArchiveTests {

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "StoreArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// A store made by `StoreV1`, with one record, closed again.
    private func v1Store(in dir: URL) throws -> URL {
        let url = dir.appending(path: "default.store")
        let container = try ModelContainer(for: StoreV1.Item.self,
                                           configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        container.mainContext.insert(StoreV1.Item())
        try container.mainContext.save()
        return url
    }

    /// A `StoreV1` store as iCloud sync leaves one: made with history tracking on.
    private func v1TrackedStore(in dir: URL) throws -> URL {
        let url = dir.appending(path: "default.store")
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: [StoreV1.Item.self]))
        let container = NSPersistentContainer(name: "Tracked", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        return url
    }

    private func verdict(_ url: URL, _ models: [any PersistentModel.Type]) -> StoreArchive.Verdict {
        StoreArchive.verdict(storeAt: url, model: NSManagedObjectModel.makeManagedObjectModel(for: models))
    }

    @Test func aStoreThatMatchesTheModelIsLeftAlone() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(verdict(try v1Store(in: dir), [StoreV1.Item.self]) == .matchesModel)
    }

    // An iCloud-only failure: the store migrates with iCloud off, so it's kept.
    @Test func aStoreThatMigratesIsLeftAlone() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(verdict(try v1Store(in: dir), [StoreV2.Item.self]) == .opensWithoutICloud)
    }

    @Test func aStoreThatCannotBeMigratedIsTheOnlyOneMovedAside() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(verdict(try v1Store(in: dir), [StoreV3.Item.self]) == .cannotBeMigrated)
    }

    // Real stores were made with iCloud sync, which turns history tracking on.
    // Opened without it they'd be read-only and couldn't migrate, and so would
    // be archived by mistake.
    @Test func aStoreFromICloudSyncStillMigratesWithICloudOff() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(verdict(try v1TrackedStore(in: dir), [StoreV2.Item.self]) == .opensWithoutICloud)
    }

    @Test func aStoreFromICloudSyncThatCantMigrateIsTheOneMovedAside() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(verdict(try v1TrackedStore(in: dir), [StoreV3.Item.self]) == .cannotBeMigrated)
    }

    // The check migrates a store it can; the app must then still be able to
    // write to it.
    @Test func theCheckLeavesAMigratedStoreWritable() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try v1Store(in: dir)
        #expect(verdict(url, [StoreV2.Item.self]) == .opensWithoutICloud)
        let container = try ModelContainer(for: StoreV2.Item.self,
                                           configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        container.mainContext.insert(StoreV2.Item())
        try container.mainContext.save()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StoreV2.Item>()) == 2)
    }

    // Only Core Data's migration errors mean the model is the problem. A full
    // disk or a database fault anywhere in the chain means it isn't.
    @Test func onlyMigrationErrorsCount() {
        let cocoa = { (code: Int, under: NSError?) in
            NSError(domain: NSCocoaErrorDomain, code: code,
                    userInfo: under.map { [NSUnderlyingErrorKey: $0] } ?? [:])
        }
        let sqlite = NSError(domain: NSCocoaErrorDomain, code: NSMigrationError, userInfo: [NSSQLiteErrorDomain: 8])
        // What Core Data reported for a field whose type changed.
        #expect(StoreArchive.isMigrationFailure(cocoa(NSMigrationMissingMappingModelError, cocoa(NSInferredMappingModelError, nil))))
        #expect(StoreArchive.isMigrationFailure(cocoa(NSPersistentStoreIncompatibleVersionHashError, nil)))
        // What it reported for read-only files: the generic error, with an
        // SQLite error inside. The generic error alone isn't enough either.
        #expect(!StoreArchive.isMigrationFailure(cocoa(NSMigrationError, sqlite)))
        #expect(!StoreArchive.isMigrationFailure(cocoa(NSMigrationError, nil)))
        // A database fault or a file problem anywhere in the chain means the
        // model isn't the problem, whatever the error on top says.
        #expect(!StoreArchive.isMigrationFailure(cocoa(NSMigrationMissingMappingModelError, sqlite)))
        #expect(!StoreArchive.isMigrationFailure(cocoa(NSMigrationMissingMappingModelError, cocoa(NSFileWriteOutOfSpaceError, nil))))
        #expect(!StoreArchive.isMigrationFailure(cocoa(NSMigrationMissingMappingModelError, cocoa(NSSQLiteError, nil))))
        #expect(!StoreArchive.isMigrationFailure(NSError(domain: "other", code: NSMigrationMissingMappingModelError)))
    }

    // A store the check can't write to (its files are read-only) fails to
    // migrate for a reason that isn't the model: it stays where it is.
    @Test func aStoreThatCantBeWrittenIsLeftAlone() throws {
        let dir = try folder()
        let url = try v1Store(in: dir)
        let files = StoreArchive.parts(of: url).filter { exists($0) }
        for file in files { try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path) }
        defer {
            for file in files { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
            try? FileManager.default.removeItem(at: dir)
        }
        // Core Data reports this as a failed migration with an SQLite error in
        // it ("attempt to write a readonly database"), not as a model problem.
        #expect(verdict(url, [StoreV2.Item.self]) == .failedForAnotherReason(code: NSMigrationError))
    }

    @Test func aMissingStoreIsNotJudged() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(verdict(dir.appending(path: "default.store"), [StoreV1.Item.self]) == .missing)
    }

    // A locked phone just after a restart can't read the store yet: it must not
    // be moved aside for that.
    @Test func aStoreThatCantBeReadIsLeftAlone() throws {
        let dir = try folder()
        let url = try v1Store(in: dir)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(verdict(url, [StoreV3.Item.self]) == .unreadable)
    }

    // Wherever the store is: here, a folder standing in for the app-group container.
    @Test func everyPartOfTheStoreIsMovedAsideBesideIt() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appending(path: "default.store")
        for name in ["default.store", "default.store-wal", "default.store-shm", "unrelated.txt"] {
            try Data([1]).write(to: dir.appending(path: name))
        }
        let photos = dir.appending(path: ".default_SUPPORT/_EXTERNAL_DATA")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data([2]).write(to: photos.appending(path: "photo"))

        #expect(StoreArchive.archive(storeAt: store, stamp: 1_790_000_000))

        for name in ["default.store", "default.store-wal", "default.store-shm", ".default_SUPPORT"] {
            #expect(!exists(dir.appending(path: name)), "\(name) still there")
            #expect(exists(dir.appending(path: "\(name).1790000000.bak")), "\(name) not archived")
        }
        #expect(exists(dir.appending(path: ".default_SUPPORT.1790000000.bak/_EXTERNAL_DATA/photo")))
        #expect(exists(dir.appending(path: "unrelated.txt")))
    }

    // A part that won't move puts back the ones that did: a new database beside
    // an old log would be corrupt.
    @Test func aPartThatWontMovePutsTheOthersBack() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appending(path: "default.store")
        for name in ["default.store", "default.store-wal"] { try Data([1]).write(to: dir.appending(path: name)) }
        try Data([0]).write(to: dir.appending(path: "default.store-wal.7.bak"))    // in the way

        #expect(!StoreArchive.archive(storeAt: store, stamp: 7))
        #expect(exists(store))
        #expect(exists(dir.appending(path: "default.store-wal")))
        #expect(!exists(dir.appending(path: "default.store.7.bak")))
    }

    @Test func missingPartsAreSkipped() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appending(path: "default.store")
        try Data([1]).write(to: store)
        #expect(StoreArchive.archive(storeAt: store, stamp: 7))
        #expect(exists(dir.appending(path: "default.store.7.bak")))
    }

    // Every step of the launch opens, judges and archives one file: the local
    // configuration's. Only a signed build shows where that is (the app-group
    // container); CI is unsigned, so this pins that the steps agree, not the folder.
    @Test func everyStepUsesTheSameStore() {
        let schema = Schema(PlowRApp.models)
        let local = PlowRApp.localConfiguration(for: schema).url
        #expect(PlowRApp.cloudConfiguration(for: schema).url == local)
        #expect(local.lastPathComponent == "default.store")
    }
}
