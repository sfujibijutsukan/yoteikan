# 開発・検証手順

## 必要な環境

- macOS、iOS 17以降をビルドできるXcode、インストール済みのiPhoneシミュレーター。
- Go：スクリーンショット出力ツールを使う場合のみ。標準ライブラリ以外の依存なし。

外部パッケージ・アカウント設定・サーバーは不要です。プロジェクトはios/Yoteikan.xcodeproj、共有スキームはYoteikan。

## ビルド・実行

Xcodeでプロジェクトを開き、YoteikanスキームとiPhoneを選んで実行する。実機ではSigning & Capabilitiesで自分のDevelopment Teamを設定する。

CLIで利用可能なシミュレーターを確認する。

```sh
xcrun simctl list devices available
```

以下のdevice_idに表示された端末IDを指定する。検証ではiPhone 17e / iOS 27.0を使用した。実行前に、Xcodeまたはsimctlで対象のシミュレーターを起動しておく。

```sh
device_id="ここにシミュレーターの端末ID"
mkdir -p artifacts
xcodebuild -project ios/Yoteikan.xcodeproj -scheme Yoteikan \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath artifacts/build \
  build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES

xcrun simctl install "$device_id" \
  artifacts/build/Build/Products/Debug-iphonesimulator/Yoteikan.app
xcrun simctl launch "$device_id" org.sfuji.yoteikan
```

## テスト

ユニットテストは保存・Undo・日付ごとの分離・プリセットの独立性・境界・スナップ・重なりを確認する。UIテストは配置、移動、伸縮、未配置への戻し、再起動後の復元、プリセットの追加作成、カレンダー読み込みと選択を実際の操作で確認する。Issue #1の回帰テストでは、新規付箋をドラッグで配置した直後に、余白の長押しと右上の移動つまみの両方から開始時刻を変更する。移動後の所要時間保持、Undo、再起動後の保存も確認する。Issue #2では同じ操作テストを使用し、プリセットは行内の追加枚数、カレンダーは実際の選択スイッチで状態を確認する。

```sh
result_path="artifacts/Check-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project ios/Yoteikan.xcodeproj -scheme Yoteikan \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath artifacts/build \
  -resultBundlePath "$result_path" \
  -parallel-testing-enabled NO \
  test CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES
```

UIテストは付箋の保存データを初期化し、カレンダー連携テストでは検証用カレンダーを作成する。アプリを日常利用している端末とは分けたシミュレーターで実行する。カレンダー権限が未許可なら、システムの許可画面も操作する。

Issue #3のUIテストは、日付欄とタイムラインの余白から前日・翌日へ移動し、元の日へ戻ったときに付箋の時刻と所要時間が保持されることを確認する。時間割と付箋ゾーンのスクロールで日付が変わらないことも確認する。

Issue #4では、ユニットテストで旧データの読み込み、色名の保存・Undo、付箋とプリセットの保持、欠けた名前の補完を確認する。UIテストでは「仕事」を「集中」へ変更し、既存付箋の色選択への反映、再起動後の復元、新規プリセットとその付箋への適用を確認する。

## スクリーンショット出力

ゾーン構成のUIテストは、右の付箋から左の時間割へのドラッグと、右へ戻す操作を確認する。縦画面ではメモの別画面を開いて保存・再起動を確認し、横画面では時間割・詳細メモ・付箋の順に横並びになることを確認する。回転後は描画が落ち着いてから撮影し、横画面ではアプリ領域の切り抜きによる欠けを避けるためXCUIScreenのスクリーンショットを使用する。

付箋・詳細の切り替えでは、見出しをワンタップして右の領域が切り替わり、メモの下書きが保持されることを確認する。付箋をタップして直接詳細を開き、編集・再配置した後、詳細の表示中に右へドラッグして未配置へ戻す操作も確認する。

Issue #5では、初期値の5:00〜24:00に加え、変更した時間帯での配置境界、保存・Undo、旧データの移行、長すぎる付箋の配置拒否、範囲内の空き時間計算を確認する。UIテストは20:00〜22:00に変更して保存・再起動・キャンセルを確認し、20:00の付箋を作成後に開始を21:00へ変更して「時間外」表示とUndoを確認する。

色の管理機能では、旧データの移行、色の追加・編集・削除、全日付・プリセットへの付け替え、Undo、最後の1色、入力検証と濃い色の文字色をユニットテストで確認する。UIテストは5色目を追加し、名前とRGBを編集、付箋とプリセットに使用後、「仕事」へ付け替えて削除し、再起動後にも反映されることを確認する。

```sh
go run ./tools/report/main.go "$result_path" docs/screenshots
go vet tools/report/main.go
```

Goツールがxcresulttoolを呼び、XCTestに添付された実際のスクリーンショットを連番付きPNGとして抽出し、index.htmlを生成する。部分的なテストを再実行した場合も、同じ出力先にある既存の連番PNGを一覧へ含める。

index.htmlはローカルのブラウザーで開く。GitHubでの閲覧には[スクリーンショット一覧](screenshots/README.md)を使用する。新しい画面を追加した場合は、このMarkdown一覧も更新する。

## 起動引数

| 引数 | 動作 |
|---|---|
| --demo | デモ表示付きのサンプル計画を読み込み、付箋・プリセットの変更は保存しない。通常起動の計画は保持 |
| --reset-test-data | 付箋・プリセットの保存データを初期化。カレンダーの選択は保持 |
| --calendar-test | Debugのシミュレーター限定で、許可後に検証用カレンダーと予定を準備 |
| --short-events-test | --demoと併用し、Debugのシミュレーター限定で8:00から5分の付箋3件・固定予定2件を連続表示。通常データは変更しない |

```sh
xcrun simctl launch --terminate-running-process \
  "$device_id" org.sfuji.yoteikan --demo
```

--calendar-testは「予定館・動作確認用」カレンダーに10:00と14:00の予定および終日予定を用意し、表示対象へ追加する。すでに当日の予定がある場合は重複作成しない。カレンダーへの書き込み処理は実機とReleaseビルドではコンパイル対象外。

## Git管理するもの

アプリのソース・テスト・Xcodeプロジェクト、Goツール、ドキュメント、確認用スクリーンショットを管理する。artifacts/、DerivedData、Xcodeの個人設定、Goのビルド出力は管理しない。

[動作確認結果](verification.md) / [READMEへ戻る](../README.md)

## ブランチとPR

新しい作業は最新の `origin/main` から `codex/` で始まるブランチを作成します。PRのマージ先は必ず `main` とし、機能ブランチ同士をマージ先にする運用は行いません。

## 保存先

バンドルIDは `org.sfuji.yoteikan` です。計画データは端末内に保存します。Googleログイン・Drive同期・Webからの参照や編集機能はありません。既存の端末内データは同じ保存形式・キーで引き続き読み込みます。
