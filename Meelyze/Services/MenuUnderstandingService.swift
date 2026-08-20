import Foundation

/// OCRで得たメニュー全体を、料理項目ごとの型安全な構造化データへ変換するProtocol。
/// ViewModelおよびこのファイル自体は`FoundationModels`をimportせず、具象実装
/// （例: `FoundationModelsMenuParser`）内へApple固有の型・処理を閉じ込める
/// （`docs/technology-selection.md`§4・§6）。
///
/// LLMの責務は自然言語理解と構造化に限定する。`availability()`が返す利用可否や
/// `analyze(_:)`が返す失敗は、Issue #17/#19が判断材料として使う事実情報であり、
/// アレルゲン・食事制限の三値へこのProtocol自身が変換することはない。
protocol MenuUnderstandingService: Sendable {
    /// 実行時点のApple Foundation Models利用可否を返す。長期間キャッシュされた値ではなく、
    /// 呼び出しごとに再評価された結果を返す実装を前提とする。
    func availability() async -> MenuUnderstandingAvailability

    /// メニュー全体の入力を解析し、複数の`ParsedMenuItem`と型付き失敗を含む結果を返す。
    ///
    /// 1件の失敗で成功済み項目を捨てず、`MenuUnderstandingResult`内で成功と失敗を共存させる。
    /// 空・重複source ID等、Foundation Modelsを呼ぶ前に検出できる入力不正はrequest-scopedな
    /// 失敗として返し、モデルを呼び出さない。
    func analyze(_ request: MenuUnderstandingRequest) async -> MenuUnderstandingResult
}
