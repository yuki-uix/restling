import Foundation
import PomodoroCore
import Darwin

/// Injectable storage keeps failure tests away from a person's actual backups.
@MainActor
protocol BackupRecoveryStoring: AnyObject {
    var latestURL: URL? { get }
    func save(_ backup: RestlingBackup) throws -> URL
    func loadLatest() throws -> RestlingBackup
    func saveSnapshot(_ snapshot: RecoverySnapshot) throws -> URL
    func loadSnapshot() throws -> RecoverySnapshot
}

extension BackupRecoveryStoring {
    func saveSnapshot(_ snapshot: RecoverySnapshot) throws -> URL {
        guard let backup = snapshot.backup else {
            throw ForestDataError.invalid("此安全副本存储不支持保留未能读取的原始存档，恢复已取消。")
        }
        return try save(backup)
    }

    func loadSnapshot() throws -> RecoverySnapshot {
        RecoverySnapshot(backup: try loadLatest())
    }
}

enum BackupFileIO {
    /// Read at most the format's limit, including when a file changes after it
    /// was selected. A malformed file cannot force an unbounded allocation.
    static func read(_ url: URL) throws -> Data {
        guard url.isFileURL, !url.path.contains("\0"),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ForestDataError.invalid("请选择普通备份文件，目录、符号链接或特殊设备不能导入。")
        }
        // A selected path can change after metadata was read. Nonblocking open
        // and fstat prevent a replacement FIFO from ever blocking this reader.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(descriptor)
            throw ForestDataError.invalid("所选路径不是可读取的普通备份文件。")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= RestlingBackup.maxDataSize {
            let count = min(65_536, RestlingBackup.maxDataSize + 1 - data.count)
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { return data }
            data.append(chunk)
        }
        throw ForestDataError.invalid("备份文件超过 20 MB，无法导入。")
    }
}

@MainActor
final class LocalBackupRecoveryStore: BackupRecoveryStoring {
    let directory: URL
    private let manager: FileManager
    private var pointerURL: URL { directory.appendingPathComponent("latest-recovery.json") }

    private struct Pointer: Codable {
        let version: Int
        let fileName: String
    }

    init(directory: URL? = nil, manager: FileManager = .default) {
        self.manager = manager
        self.directory = directory ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Restling", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    var latestURL: URL? {
        guard let values = try? pointerURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 4_096,
              let data = try? BackupFileIO.read(pointerURL),
              let pointer = try? JSONDecoder().decode(Pointer.self, from: data), pointer.version == 1,
              pointer.fileName == (pointer.fileName as NSString).lastPathComponent,
              pointer.fileName.hasPrefix("Restling-before-"), pointer.fileName.hasSuffix(".json") else { return nil }
        let url = directory.appendingPathComponent(pointer.fileName)
        guard let resource = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              resource.isRegularFile == true, resource.isSymbolicLink != true else { return nil }
        return url
    }

    /// Each restore gets a separate file. Earlier safety copies are retained;
    /// moving the latest pointer never overwrites the only prior good snapshot.
    func save(_ backup: RestlingBackup) throws -> URL {
        try saveSnapshot(RecoverySnapshot(backup: backup))
    }

    func saveSnapshot(_ snapshot: RecoverySnapshot) throws -> URL {
        let encoded = try snapshot.encoded()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let url = directory.appendingPathComponent("Restling-before-\(UUID().uuidString).json")
        try durableWrite(encoded, to: url)
        guard try BackupFileIO.read(url) == encoded else {
            throw ForestDataError.invalid("导入前的安全副本未能完整保存，恢复已取消。")
        }
        let pointer = try JSONEncoder().encode(Pointer(version: 1, fileName: url.lastPathComponent))
        try durableWrite(pointer, to: pointerURL)
        return url
    }

    func loadLatest() throws -> RestlingBackup {
        guard let backup = try loadSnapshot().backup else {
            throw ForestDataError.invalid("这是未能读取的原始存档安全副本，请使用本机撤回恢复入口。")
        }
        return backup
    }

    func loadSnapshot() throws -> RecoverySnapshot {
        guard let latestURL else { throw ForestDataError.invalid("没有找到可恢复的导入前安全副本。") }
        return try RecoverySnapshot.decode(BackupFileIO.read(latestURL))
    }

    private func durableWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }
}
