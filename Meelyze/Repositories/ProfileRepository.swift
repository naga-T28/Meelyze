import Foundation

/// `UserProfile`の保存・復元を担うProtocol。ViewModelはこのProtocol経由でのみ永続化にアクセスし、
/// SwiftDataを直接importしない。
protocol ProfileRepository {
    /// 保存済みの単一プロファイルを返す。未保存の場合は`nil`を返す。
    func currentProfile() throws -> UserProfile?

    /// プロファイルを保存する。MVPは単一プロファイルのみを前提とし、既存レコードがあれば置き換える。
    func save(_ profile: UserProfile) throws
}
