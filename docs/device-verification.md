# Meelyze 実機検証ガイド

> **Status**: Accepted
> **対象**: 開発者個人のiPhoneでのDebugビルド起動確認
> **関連Issue**: #5

## 1. 目的

Simulatorでの確認だけでは、実機署名やDevice単体の再現性は保証できない。本書は、各開発者が自分のiPhoneへ`Meelyze`をビルド・インストールして初期画面を確認するための手順と、その際に発生しうるGit管理上の注意点をまとめる。

自動テスト（Simulator向けbuild/test）の手順は`task/TASK-005-simulator-verification.md`を参照。

## 2. 前提条件

- XcodeにApple IDが登録されていること（無料のPersonal Teamでも実機ビルド・インストールは可能）
  - 未登録の場合: Xcodeメニュー → `Settings` → `Accounts` → `+`でApple IDを追加
- iPhoneとMacをケーブル、またはWi-Fi経由のペアリングで接続できること
- 対象のiPhoneでDeveloper Modeを有効化できること（iOS 16以降）

## 3. 手順（Xcode GUI）

1. `Meelyze.xcodeproj`をXcodeで開く
2. iPhoneをMacに接続する
   - 初回接続時、iPhone側の「このコンピュータを信頼しますか？」に対して「信頼」→ パスコード入力
3. iPhoneでDeveloper Modeを有効化する（既に有効なら不要）
   - 「設定」→「プライバシーとセキュリティ」→ 最下部の「Developer Mode」をON
   - 確認ダイアログで「オンにする」→ iPhoneが再起動 → 再起動後の確認ダイアログでも「オンにする」
4. Teamを選択する
   - 左側ナビゲータで`Meelyze`プロジェクト → `TARGETS`の`Meelyze` → `Signing & Capabilities`タブ
   - `Automatically manage signing`がONであることを確認（既定でON）
   - `Team`ドロップダウンから自分のApple ID（Personal Team）または所属チームを選択
   - Provisioning Profileが自動生成される（すぐ反映されない場合は数秒待つか`Try Again`）
5. Xcode上部のデバイス選択メニューで、接続した自分のiPhoneを実行先として選ぶ
6. ▶（Run）ボタンを押す。ビルド→署名→インストール→自動起動まで実行される
7. 初回のみ、iPhone側で「信頼されていないデベロッパ」の警告が出ることがある
   - iPhoneの「設定」→「一般」→「VPNとデバイス管理」→ 該当のApple IDのプロファイルを選び「信頼」
8. アプリが起動し、初期画面に固定表示「Meelyze」が表示されることを確認する

## 4. コミット前に必ず確認すること

手順4でTeamを選択すると、**`Meelyze.xcodeproj/project.pbxproj`に個人のTeam ID（`DEVELOPMENT_TEAM`）が書き込まれる**。今回は、Development Teamをリポジトリへ固定しない方針に反するため、実機確認後は次を必ず実行してから通常の開発作業に戻ること。

```sh
# DEVELOPMENT_TEAM の差分だけであることを確認する
git diff Meelyze.xcodeproj/project.pbxproj

# 個人のTeam IDを元（空）に戻す
git checkout -- Meelyze.xcodeproj/project.pbxproj
```

このチェックを行わずに`git add -A`などで一括コミットしないこと。

## 5. CLIでの代替手順（project.pbxprojを一切変更しない方法）

コマンドラインからビルド設定を上書きすれば、プロジェクトファイル自体は変更されない。CLI操作に慣れている場合はこちらが安全。

```sh
# 接続中デバイスのUDIDを確認
xcrun devicectl list devices

# DEVELOPMENT_TEAM をこのビルドのみに上書きしてビルド（pbxprojは変更されない）
xcodebuild -project Meelyze.xcodeproj -scheme Meelyze \
  -destination 'platform=iOS,name=<自分のiPhone名>' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<自分のTeam ID> \
  build

# 生成された.appを実機へインストール
xcrun devicectl device install app --device <UDID> \
  ~/Library/Developer/Xcode/DerivedData/Meelyze-*/Build/Products/Debug-iphoneos/Meelyze.app

# アプリを起動
xcrun devicectl device process launch --device <UDID> com.meelyze.Meelyze
```

Team IDは[Apple Developerサイト](https://developer.apple.com/account)のMembershipページ、またはXcodeの`Signing & Capabilities`画面で確認できる。

## 6. トラブルシューティング

| 症状 | 対処 |
|---|---|
| Xcodeがデバイスを認識しない | iPhoneのロックを解除し、「このコンピュータを信頼しますか？」に「信頼」で応答する |
| Developer Modeのダイアログが出ない | 「設定」→「プライバシーとセキュリティ」を直接開き、`Developer Mode`の項目を確認する |
| `No profiles for 'com.meelyze.Meelyze' were found` 等の署名エラー | `Signing & Capabilities`でTeamを選び直す、または`-allowProvisioningUpdates`を付けて再実行する |
| 起動後に「信頼されていないデベロッパ」と表示される | 「設定」→「一般」→「VPNとデバイス管理」で対象のプロファイルを「信頼」する |
| 確認後、`git status`に`project.pbxproj`の差分が残っている | 本書4節の手順で`git checkout -- Meelyze.xcodeproj/project.pbxproj`を実行する |