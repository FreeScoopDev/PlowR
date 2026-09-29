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

    private func verdict(_ url: URL, _ models: [any PersistentModel.Type]) -> StoreArchive.Verdict {
        StoreArchive.verdict(storeAt: url, model: NSManagedObjectModel.makeManagedObjectModel(for: models)) {
            (try? ModelContainer(for: Schema(models),
                                 configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))) != nil
        }
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

    // Every step of the launch opens, judges and archives one file. Only a signed
    // build shows where that is (the app-group container); CI is unsigned, so
    // this pins that the steps agree, not the folder.
    @Test func everyStepUsesTheSameStore() {
        let schema = Schema(PlowRApp.models)
        let local = PlowRApp.localConfiguration(for: schema).url
        #expect(PlowRApp.cloudConfiguration(for: schema).url == local)
        #expect(ModelConfiguration(schema: schema, cloudKitDatabase: .none).url == local)
        #expect(local.lastPathComponent == "default.store")
    }
}
