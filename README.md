# Meelyze

訪日旅行者向け メニューアレルゲン推定アプリ（開発中）

## 概要

食物アレルギーや宗教・信条上の食事制限を持つ訪日旅行者が、日本語メニューをカメラで撮影するだけで、各料理に含まれる可能性のあるアレルゲン・制限食材を母語で確認できるアプリです。あわせて、店員へ確認するための翻訳支援機能を提供します。

本アプリは注文前の最終確認を補助するツールであり、摂食の安全を保証するものではありません。


## 技術スタック

- Swift / SwiftUI
- MVVM + Repository / Service
- AVFoundation / Apple Vision
- Apple Foundation Models（第一候補）/ llama.cpp（代替候補）
- SwiftData / JSON
- Apple Translation Framework
- Swift Testing / XCTest / XCUITest

LLMはメニューの自然言語理解と構造化に限定して利用し、最終的なアレルゲン・食事制限判定はDBとSwiftの決定論的なRule Engineで行います。詳細は[技術選定](docs/technology-selection.md)を参照してください。

## セットアップ

### 必要要件

- Xcode 26系（開発時点の確認バージョン: 26.4.1）
- iOS Deployment Target: iOS 26.0
- Simulatorで動作確認する場合は、Xcodeに対応するiOS Runtimeが導入されていること

### プロジェクトを開く

```sh
git clone https://github.com/naga-T28/Meelyze.git
cd Meelyze
open Meelyze.xcodeproj
```

`Meelyze.xcodeproj`はリポジトリ直下にコミット済みのため、`xcodegen`などの追加ツールを使わずそのまま開けます（`project.yml`はプロジェクト構成を変更する場合のXcodeGen向け定義ファイルです）。

### Simulatorで起動する

Xcodeで実行先をいずれかのiPhone Simulatorに設定し、▶（Run）ボタンで起動します。コマンドラインの場合は以下も利用できます。

```sh
xcodebuild -project Meelyze.xcodeproj -scheme Meelyze \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

xcodebuild -project Meelyze.xcodeproj -scheme Meelyze \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

初期画面に固定表示「Meelyze」が表示されれば起動成功です。

### 実機で起動する

App TargetはAutomatically manage signingを使用し、Development TeamはリポジトリへコミットせずGitで管理していません。各自のApple IDでTeamを選択してビルドしてください。手順とコミット時の注意点は[実機検証ガイド](docs/device-verification.md)を参照してください。

### 依存関係（Swift Package Manager）

現時点で外部Swift Packageは未導入です。依存を追加する場合はSwift Package Manager（Xcodeの`File > Add Package Dependencies...`）を使用し、CocoaPods/Carthageなど他のパッケージマネージャーは使用しません。

## ドキュメント

- [要件定義](docs/requirements.md)
- [技術選定](docs/technology-selection.md)
- [開発ルール](docs/development-guide.md)
- [実機検証ガイド](docs/device-verification.md)

## 開発体制

2名体制・アジャイル開発（1週間スプリント）。Issue/PRの運用は [.github/](.github/) を参照。
