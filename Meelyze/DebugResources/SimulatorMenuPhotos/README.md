# SimulatorMenuPhotos

iOS SimulatorにはカメラSessionがなく、`AVFoundationCameraService`は`CameraServiceError.deviceUnavailable`をthrowする。実機を使わずにSimulator上で実際の`VisionOCRService`（本物のVision OCR）の挙動を手動確認できるよう、このフォルダに置いたメニュー写真を撮影結果として代わりに使う。

## 使い方

1. `.jpg` `.jpeg` `.png` `.heic`のいずれかのメニュー写真をこのフォルダへコピーする
2. `xcodegen generate --spec project.yml`でプロジェクトを再生成する（フォルダ参照のため、画像を追加・削除しても以後の再生成は不要。フォルダ自体を初めて認識させる時、または`project.yml`を変更した時だけ再生成すればよい）
3. SimulatorでMeelyzeを起動し、S06（メニュー撮影）でシャッターをタップする。タップするたびにファイル名順でこのフォルダの画像を1枚ずつ順番に使う（最後まで行くと先頭へ戻る）

## 注意

- ここに置いた画像は`SimulatorCameraService`（`Meelyze/Services/SimulatorCameraService.swift`）経由でのみ使われ、`#if targetEnvironment(simulator)`で実機ビルドからは除外される
- OCR自体はスタブに差し替えず、実際の`VisionOCRService`で処理する。OCR結果を固定値で確認したい場合は`UITEST_OCR_STUB_MODE`環境変数（`Meelyze/Services/UITestScanStubs.swift`）を使う
- ここに置く画像は個人の実写真である可能性があるため、`.gitignore`で画像ファイル自体はコミット対象外にしている（このREADMEのみ追跡）
