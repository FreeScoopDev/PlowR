import Foundation
import OSLog
import SwiftUI

/// A made file (a PDF, a spreadsheet) written to the temporary folder to be
/// shared. It's shared only once it's written: a failed write used to open
/// the share sheet anyway, offering a file that wasn't there, or an older
/// copy left from before. On failure the screen says so in one line
/// (`shareFileAlert`) and it's logged.
enum ShareFile {
    enum Kind {
        case pdf, file

        var failureTitle: String {
            switch self {
            case .pdf: "Couldn't Make the PDF"
            case .file: "Couldn't Save the File"
            }
        }
    }

    /// What the alert says.
    struct Failure: Error, Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Writes `data` to `url` (protected), and returns the URL to share, or
    /// what to tell the user. `write` stands in for the disk in tests.
    static func write(_ data: Data, to url: URL, kind: Kind = .pdf,
                      using write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .completeFileProtection) })
        -> Result<URL, Failure> {
        do {
            try write(data, url)
            return .success(url)
        } catch {
            log.error("Couldn't write \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(failure(error, kind: kind))
        }
    }

    /// The alert for `error`: the kind's title, and the system's own words on
    /// one line.
    static func failure(_ error: Error, kind: Kind) -> Failure {
        let line = error.localizedDescription
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return Failure(title: kind.failureTitle, message: line)
    }

    private static let log = Logger(subsystem: "Scoops.PlowR", category: "ShareFile")
}

extension View {
    /// Says a file couldn't be written (`ShareFile.write`), once.
    func shareFileAlert(_ failure: Binding<ShareFile.Failure?>) -> some View {
        alert(failure.wrappedValue?.title ?? "", isPresented: Binding(
            get: { failure.wrappedValue != nil },
            set: { if !$0 { failure.wrappedValue = nil } }
        ), presenting: failure.wrappedValue) { _ in
            Button("OK", role: .cancel) { }
        } message: { failure in
            Text(failure.message)
        }
    }
}
