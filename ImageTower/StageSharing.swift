import CloudKit
import Foundation
import UIKit

/// 他の端末に渡す共有コード。読み間違えやすい文字（0/O, 1/I）を除いた8文字で、レコード名としてそのまま使う
enum StageShareCode {
    static let length = 8
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func generate() -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// 表示用に「ABCD-EFGH」の形にする
    static func formatted(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(length / 2))-\(code.suffix(length / 2))"
    }

    /// 入力されたコード、または共有メッセージ・リンクを丸ごと貼り付けたものからコードを取り出す
    static func normalize(_ input: String) -> String? {
        if let url = input.split(whereSeparator: \.isWhitespace).compactMap({ URL(string: String($0)) }).first(where: { code(from: $0) != nil }) {
            return code(from: url)
        }
        let candidate = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        if isValid(candidate) { return candidate }
        // 「コード：ABCD-EFGH」のように文章ごと貼り付けられた場合
        let pattern = #/[A-Z2-9]{4}-?[A-Z2-9]{4}/#
        if let match = input.uppercased().firstMatch(of: pattern) {
            let code = String(match.output).replacingOccurrences(of: "-", with: "")
            return isValid(code) ? code : nil
        }
        return nil
    }

    static func url(for code: String) -> URL {
        URL(string: "imagetower://stage/\(code)")!
    }

    /// `imagetower://stage/ABCDEFGH` からコードを取り出す
    static func code(from url: URL) -> String? {
        guard url.scheme == "imagetower", url.host == "stage",
              let code = url.pathComponents.last?.uppercased(),
              isValid(code) else { return nil }
        return code
    }

    private static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy(alphabet.contains)
    }
}

/// 共有コードから取得した、まだライブラリに追加していないステージ
struct ReceivedStage {
    let code: String
    let name: String
    let imageData: [Data]
    let images: [UIImage]
}

enum StageShareError: LocalizedError {
    case notSignedIn
    case network
    case notFound
    case invalidCode
    case unsupportedVersion
    case brokenData
    case notPlayable
    case failed
    case receiveFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            String(localized: "共有するにはiCloudへのサインインが必要です。設定アプリの一番上からApple アカウントでサインインしてください。")
        case .network:
            String(localized: "インターネットに接続できませんでした。通信環境を確認して、もう一度お試しください。")
        case .notFound:
            String(localized: "このコードのステージは見つかりませんでした。コードを確認してください。")
        case .invalidCode:
            String(localized: "コードは「ABCD-EFGH」のような8文字です。")
        case .unsupportedVersion:
            String(localized: "このステージを開くには、アプリを最新版にアップデートしてください。")
        case .brokenData:
            String(localized: "このステージのデータを読み込めませんでした。")
        case .notPlayable:
            String(localized: "共有できるのは素材が\(SubjectLibrary.minimumPlayableItems)個以上のステージです。")
        case .failed:
            String(localized: "共有できませんでした。時間をおいて、もう一度お試しください。")
        case .receiveFailed:
            String(localized: "受け取れませんでした。時間をおいて、もう一度お試しください。")
        }
    }
}

/// CloudKitの公開データベースでステージを受け渡す。
/// レコード名を共有コードにすることで、コードを知っている人だけが取得できる（一覧や検索はできない）
@MainActor
final class StageShareService {
    static let shared = StageShareService()

    private static let containerIdentifier = "iCloud.harumidiv.ImageTower"
    private static let recordType = "SharedStage"
    private static let formatVersion: Int64 = 1

    private lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private var database: CKDatabase { container.publicCloudDatabase }

    private init() {}

    /// ステージをアップロードして共有コードを返す。前回のコードがあれば同じコードの内容を最新にする
    func upload(name: String, imageURLs: [URL], existingCode: String?) async throws -> String {
        guard imageURLs.count >= SubjectLibrary.minimumPlayableItems else { throw StageShareError.notPlayable }
        do {
            guard try await container.accountStatus() == .available else { throw StageShareError.notSignedIn }
        } catch let error as StageShareError {
            throw error
        } catch {
            throw Self.mapped(error)
        }

        if let existingCode {
            do {
                try await save(code: existingCode, name: name, imageURLs: imageURLs, overwrite: true)
                return existingCode
            } catch let error as CKError where error.code == .permissionFailure || error.code == .serverRecordChanged {
                // 別のiCloudアカウントで共有したコードなど、上書きできない場合は新しいコードにする
            } catch {
                throw Self.mapped(error)
            }
        }

        // 万一コードが既存のものと重なったら、作り直して保存し直す
        for _ in 0..<3 {
            let code = StageShareCode.generate()
            do {
                try await save(code: code, name: name, imageURLs: imageURLs, overwrite: false)
                return code
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            } catch {
                throw Self.mapped(error)
            }
        }
        throw StageShareError.failed
    }

    func fetch(code: String) async throws -> ReceivedStage {
        let record: CKRecord
        do {
            record = try await database.record(for: CKRecord.ID(recordName: code))
        } catch {
            throw Self.mapped(error, fallback: .receiveFailed)
        }

        guard let version = record["version"] as? Int64, let count = record["itemCount"] as? Int64 else {
            throw StageShareError.brokenData
        }
        guard version <= Self.formatVersion else { throw StageShareError.unsupportedVersion }
        guard (SubjectLibrary.minimumPlayableItems...SubjectLibrary.maximumStageItems).contains(Int(count)) else {
            throw StageShareError.brokenData
        }

        var imageData: [Data] = []
        var images: [UIImage] = []
        for index in 0..<Int(count) {
            guard let url = (record["image\(index)"] as? CKAsset)?.fileURL,
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                throw StageShareError.brokenData
            }
            imageData.append(data)
            images.append(image)
        }

        return ReceivedStage(
            code: code,
            name: (record["name"] as? String) ?? String(localized: "もらったステージ"),
            imageData: imageData,
            images: images
        )
    }

    /// 共有をやめる。すでに受け取った端末のステージは消えない
    func delete(code: String) async throws {
        do {
            try await database.deleteRecord(withID: CKRecord.ID(recordName: code))
        } catch let error as CKError where error.code == .unknownItem {
            return
        } catch {
            throw Self.mapped(error)
        }
    }

    private func save(code: String, name: String, imageURLs: [URL], overwrite: Bool) async throws {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: code))
        record["version"] = Self.formatVersion
        record["name"] = name
        record["itemCount"] = Int64(imageURLs.count)
        for (index, url) in imageURLs.enumerated() {
            record["image\(index)"] = CKAsset(fileURL: url)
        }

        let (saveResults, _) = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: overwrite ? .allKeys : .ifServerRecordUnchanged,
            atomically: true
        )
        if case .failure(let error) = saveResults[record.recordID] {
            throw error
        }
    }

    private static func mapped(_ error: Error, fallback: StageShareError = .failed) -> Error {
        if error is StageShareError { return error }
        guard let error = error as? CKError else { return fallback }
        switch error.code {
        case .notAuthenticated:
            return StageShareError.notSignedIn
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return StageShareError.network
        case .unknownItem:
            return StageShareError.notFound
        case .partialFailure:
            if let first = error.partialErrorsByItemID?.values.first {
                return mapped(first, fallback: fallback)
            }
            return fallback
        default:
            return fallback
        }
    }
}
