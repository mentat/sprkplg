import Foundation

/// Reads and writes the library as one JSON file.
///
/// Saves are atomic (write to a temporary file, then rename), so a crash mid-save leaves the
/// previous version. A file that cannot be read is moved aside, never overwritten, and a file
/// from a newer SparkPlug is refused, so no data is lost either way.
public struct TaskStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/io.sprkplg.SparkPlug/library.json` (named for the bundle id,
    /// so it never mixes with another app called SparkPlug).
    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("io.sprkplg.SparkPlug", isDirectory: true).appendingPathComponent("library.json")
    }

    public enum LoadResult: Equatable, Sendable {
        /// There was no file yet: a first launch.
        case fresh(Library)
        case loaded(Library)
        /// The file was unreadable; it was moved to `movedTo` and a fresh library started.
        case recovered(Library, movedTo: URL)

        public var library: Library {
            switch self {
            case .fresh(let l), .loaded(let l), .recovered(let l, _): return l
            }
        }
    }

    /// Loads the library. Throws `LibraryError.newerVersion` (leaving the file alone) when a newer
    /// SparkPlug wrote it; any other read or decode failure moves the file aside.
    public func load(now: Date = Date()) throws -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .fresh(.starter()) }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try TaskStore.decoder().decode(Library.self, from: data))
        } catch let error as LibraryError {
            throw error
        } catch {
            let stamp = TaskStore.stamp(now)
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
            try fm.moveItem(at: url, to: aside)
            return .recovered(.starter(), movedTo: aside)
        }
    }

    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try TaskStore.encoder().encode(library)
        try data.write(to: url, options: .atomic)
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}
