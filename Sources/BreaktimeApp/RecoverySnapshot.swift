import Foundation
import PomodoroCore

/// Safety copies normally remain ordinary, portable Restling backups. If local
/// forest bytes cannot be decoded, preserve those exact bytes in a separate
/// envelope that only the local undo path can restore.
struct RecoverySnapshot: Equatable {
    let backup: RestlingBackup?
    let rawOriginal: Data?
    let settings: BackupSettings
    let createdAt: Date

    var isRawOriginal: Bool { rawOriginal != nil }

    init(backup: RestlingBackup) {
        self.backup = backup
        rawOriginal = nil
        settings = backup.settings
        createdAt = backup.createdAt
    }

    init(rawOriginal: Data, settings: BackupSettings, createdAt: Date = Date()) throws {
        backup = nil
        self.rawOriginal = rawOriginal
        self.settings = settings
        self.createdAt = createdAt
        try validate()
    }

    func validate() throws {
        try settings.validate()
        if let backup {
            guard rawOriginal == nil, settings == backup.settings, createdAt == backup.createdAt else {
                throw ForestDataError.invalid("安全副本内容不一致。")
            }
            try backup.validate()
            return
        }
        guard let rawOriginal, rawOriginal.count <= RestlingBackup.maxDataSize else {
            throw ForestDataError.invalid("原始存档缺失或超过安全副本的大小限制。")
        }
        let seconds = createdAt.timeIntervalSince1970
        guard seconds.isFinite, seconds >= -62_135_596_800, seconds < 253_402_300_800 else {
            throw ForestDataError.invalid("安全副本创建时间超出有效日期范围。")
        }
    }

    func encoded() throws -> Data {
        try validate()
        if let backup { return try backup.encoded() }
        let envelope = RawEnvelope(format: "restling-original-recovery", version: 1,
            rawOriginal: rawOriginal!, settings: settings, createdAt: createdAt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= RestlingBackup.maxDataSize else {
            throw ForestDataError.invalid("原始存档的安全副本超过 20 MB，恢复已取消。原件保持不变。")
        }
        return data
    }

    static func decode(_ data: Data) throws -> RecoverySnapshot {
        guard data.count <= RestlingBackup.maxDataSize else {
            throw ForestDataError.invalid("安全副本超过 20 MB，无法读取。")
        }
        do {
            let decoder = JSONDecoder()
            let header = try decoder.decode(Header.self, from: data)
            if header.format == "restling-backup" {
                return RecoverySnapshot(backup: try RestlingBackup.decode(data))
            }
            guard header.format == "restling-original-recovery" else {
                throw ForestDataError.invalid("这个文件不是 Restling 安全副本。")
            }
            let envelope = try decoder.decode(RawEnvelope.self, from: data)
            guard envelope.version == 1 else {
                throw ForestDataError.invalid("暂不支持这个原始存档安全副本版本。")
            }
            return try RecoverySnapshot(rawOriginal: envelope.rawOriginal, settings: envelope.settings,
                                        createdAt: envelope.createdAt)
        } catch let error as ForestDataError {
            throw error
        } catch {
            throw ForestDataError.invalid("安全副本不完整或内容已损坏，现有数据未更改。")
        }
    }

    private struct Header: Decodable { let format: String }
    private struct RawEnvelope: Codable {
        let format: String
        let version: Int
        let rawOriginal: Data
        let settings: BackupSettings
        let createdAt: Date
    }
}
