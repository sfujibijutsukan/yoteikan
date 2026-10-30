# スクリーンショット

iPhone 17eシミュレーター / iOS 27.0でXCTestを使って実際に操作し、2026年10月25〜27日に撮影しました。デモ表記付きの画面はサンプル計画、カレンダー画面はEventKitに登録した検証用予定です。

画面2・24〜27は10月26日のIssue #18〜#20対応後の画面です。未配置時間の非表示、予定上からのスクロール、毎日の個数と自動追加を確認しています。そのほかは10月25日の拡大率・操作列整理などの確認画面です。

画面28・30・31は10月26日の「1日一覧」です。空き時間を折りたたみ、予定の文字が読める高さを確保します。切り替えタブはありません。

## 折りたたんだ時間割の5分予定

<img src="31-folded-short-events.png" width="300" alt="空き時間を縮め、5分予定のタイトルを表示">

## 1日一覧ボタン

<img src="30-fullscreen-entry.png" width="300" alt="下部に1日一覧ボタン">

## 全画面の時間割

<img src="28-fullscreen-day-timeline.png" width="300" alt="1日の時間帯全体を表示する全画面の時間割">

## 1日の計画

<img src="01-day-planner.png" width="300" alt="1日の計画">

## プリセットから追加

<img src="02-presets.png" width="300" alt="プリセットから追加">

## 付箋の編集

<img src="03-sticky-editor.png" width="300" alt="付箋の編集">

## ドラッグ移動後の重なり

<img src="04-overlap-after-drag.png" width="300" alt="ドラッグ移動後の重なり">

## 60分から90分へ延長

<img src="05-resize-overlap.png" width="300" alt="60分から90分へ延長">

## 1日全体の表示

<img src="06-day-overview.png" width="300" alt="1日全体の表示">

## 表示するカレンダーの選択

<img src="07-calendar-settings.png" width="300" alt="表示するカレンダーの選択">

## EventKitで読み込んだ予定

<img src="08-real-calendar-events.png" width="300" alt="EventKitで読み込んだ予定">

## 移動つまみで開始時刻を変更

新規作成した60分の付箋を配置し、右上の移動つまみで30分前へ移動した画面です。所要時間とカレンダーの会議は維持されます。

<img src="09-start-time-drag.png" width="300" alt="右上の移動つまみで付箋の開始時刻を変更">

## スワイプで翌日へ移動

<img src="10-swipe-next-day.png" width="300" alt="左右スワイプで翌日の計画を表示">

## 付箋の色名を設定

「仕事」を「集中」へ変更して保存した画面です。

<img src="11-color-settings.png" width="300" alt="4色それぞれの名前を編集する画面">

## 名前付きの色選択

既存の付箋にも新しい色名が反映され、内容と選択中の色は保たれます。

<img src="12-named-color-picker.png" width="300" alt="付箋の編集画面で準備・集中・生活・休憩の色を選択">

[動作確認結果](../verification.md) / [READMEへ戻る](../../README.md)

## 色を追加・編集

<img src="13-custom-colors.png" width="300" alt="5色目の趣味を追加し、名前とカラーコードを設定">

## 追加した色を付箋で選択

<img src="14-expanded-color-picker.png" width="300" alt="5色を折り返して表示する色の選択画面">

## 5:00からの計画

5:00〜24:00の1日表示で、早朝の読書を05:00へ配置した画面です。Issue #5の変更後、2026年10月25日に撮影しました。

<img src="15-five-am-plan.png" width="300" alt="5時から24時の時間軸で早朝の読書を配置">

## 開始・終了時刻の設定

<img src="16-planning-hours-settings.png" width="300" alt="開始20時、終了22時を選んだ設定画面">

## 時間外の付箋を保持

<img src="17-custom-hours-and-outside-sticky.png" width="300" alt="時間帯を21時から22時に狭めても20時の付箋を時間外として保持">

## 縦画面の2ゾーン

<img src="18-two-zone-planner.png" width="300" alt="左に時間割、右に付箋を縦に並べる2ゾーン">

## 詳細メモの編集

<img src="19-detail-memo.png" width="300" alt="選んだ付箋の詳細メモを別画面で編集">

## 横画面の3ゾーン

<img src="20-three-zone-planner.png" width="650" alt="左から時間割・詳細メモ・付箋の3ゾーン">

## 付箋領域を予定の詳細へ切り替え

<img src="21-switch-to-schedule-details.png" width="300" alt="時間割を見ながら右側で選択した予定の詳細とメモを表示">

## 5分の予定を8倍に拡大

8:00から5分の付箋3枚、続いてカレンダー形式の固定予定2件を表示しています。5分刻みの目盛りで、隣の予定と表示枠が重ならず確認できます。Debugシミュレーター専用の短時間予定サンプルです。

<img src="22-five-minute-zoom.png" width="300" alt="5分の予定を8倍に拡大し、5分刻みの目盛りで表示">

## 同じ5分の予定を1倍で表示

時間枠の高さを守り、小さく収まらない文字やつまみは省略しています。＋で必要な大きさに拡大できます。

<img src="23-five-minute-standard.png" width="300" alt="1倍でも短い予定の表示枠が隣の予定と重ならない">

## ピンチアウトで連続拡大

時間割の2本指の操作で、段階の間の倍率にも拡大できます。指の間の時間帯を基準に表示位置を保ち、予定の時刻・所要時間は維持します。

<img src="24-pinch-timeline.png" width="300" alt="時間割をピンチアウトして拡大した画面">

## 予定の上からスクロール

付箋と固定予定の上から上下にスワイプし、予定の時刻と所要時間を保持した画面です。

<img src="25-scroll-on-event.png" width="300" alt="予定の上からスクロールした時間割">

## 毎日の個数を設定

歯磨きを毎日2枚に設定しています。0枚で自動追加を停止できます。

<img src="26-daily-preset-count.png" width="300" alt="プリセットの毎日の個数を2枚に設定">

## 日付ごとに自動追加

歯磨き2枚・ごはん3枚を設定し、翌日の付箋置き場にも自動追加しています。標準プリセットも含めた枚数を右上に表示します。

<img src="27-daily-stickies.png" width="300" alt="翌日にも自動追加された付箋">

## 予定ごとの通知タイミング（Issue #17）

<img src="32-sticky-reminder.png" width="300" alt="付箋ごとに何分前に通知するか設定">

## 通知許可と予約件数（Issue #17）

<img src="33-reminder-settings.png" width="300" alt="通知の許可とOSに予約した通知件数">

## サイドバーの左右設定（Issue #23）

<img src="34-sidebar-position-settings.png" width="300" alt="サイドバーの位置を左・右で選択">

## 左サイドバー（Issue #23）

<img src="35-sidebar-left.png" width="300" alt="左に付箋、右に時間割を配置">

## 左サイドバーの横画面（Issue #23）

<img src="36-sidebar-left-landscape.png" width="640" alt="左から付箋・詳細メモ・時間割を表示">

画面1・32〜38は10月27日の設定・通知・サイドバーの検証画像です。画面1は設定入口統合時のビルドをシミュレーターで起動して撮影し、その他はUIテストに添付した画像です。最新のタブ構成は画面39〜41です。

## 設定を歯車に統合

2026年10月27日撮影。上部の時計・パレット・カレンダーを歯車から開く形にまとめています。

<img src="37-unified-settings.png" width="300" alt="時間帯・カレンダー・付箋・サイドバー・通知をまとめた設定">

## 設定から付箋を選んで編集

<img src="38-settings-sticky-list.png" width="300" alt="表示中の日の配置済み・未配置付箋を選んで編集">

## Liquid Glassの下部タブ（最新・10月27日）

旧下部操作バーと拡大率操作列を削除しました。「計画・1日表示・設定」をOS標準のタブで切り替えます。以下はサンプル計画をUIテストで操作した画面です。

<img src="39-glass-plan-tab.png" width="300" alt="操作列を削除し、Liquid Glassの下部タブを表示">

<img src="40-glass-day-tab.png" width="300" alt="1日表示タブで空き時間を縮めた時間割を表示">

<img src="41-glass-settings-tab.png" width="300" alt="設定タブに時間帯・付箋編集などを集約">

## 計画の長押しで詳細メモ（10月27日）

<img src="42-plan-long-press-memo.png" width="300" alt="計画ページで予定を長押ししてメモを表示">

## 1日表示の長押しで同じメモ

<img src="43-day-long-press-memo.png" width="300" alt="1日表示から保存済みの同じメモを確認">

## カレンダー予定のメモ

<img src="44-calendar-long-press-memo.png" width="300" alt="カレンダーの予定はメモを読み取り専用で表示">

## 紙らしい付箋（Issue #32）

<img src="45-sticky-paper-plan.png" width="300" alt="未配置と時間割の付箋に紙の陰影と折り返しを追加">

<img src="46-sticky-paper-day.png" width="300" alt="1日表示でも同じ紙の表現を使用">

## 長押し中だけ表示するメモのプレビュー（10月27日）

<img src="47-compact-plan-preview.png" width="300" alt="計画の付箋を押している間だけ小さなメモを表示">

<img src="48-compact-day-preview.png" width="300" alt="1日表示でも予定の近くに小さくメモを表示">

画面47・48はUIテストの長押し中にシミュレーターから直接撮影しました。指を離すとプレビューは消えます。画面42〜44は変更前の詳細シートです。

## 計画ページで空き時間を折りたたむ（Issue #34）

<img src="49-folded-planning.png" width="300" alt="付箋置き場を残したまま、計画の空き時間を折りたたむ">

<img src="50-folded-planning-short-notes.png" width="300" alt="5分の予定も文字が読める高さで重ならずに表示">

## 端末内保存の設定画面

<img src="58-local-settings.png" width="300" alt="アカウント・同期を削除した設定画面">

## 現在時刻とiPhoneウィジェット

<img src="59-now-planner.png" width="260" alt="起動時に現在時刻13時17分を表示する計画画面">
<img src="60-now-folded.png" width="260" alt="空き時間をたたんだ時間割の現在時刻線">
<img src="61-now-day.png" width="260" alt="1日表示の現在時刻線">
<img src="63-widget-home.png" width="260" alt="iPhoneシミュレーターのホーム画面に表示した予定館ウィジェット">

アプリの時刻線はテスト用の13:17、ホーム画面のウィジェットは実際のシミュレーター時刻に合わせたサンプルデータです。
[ウィジェットから今日の計画へ戻った画面](63-widget-open-today.png)。59〜62・64・66〜69はmain統合後に再撮影。
[小・中サイズの表示部品の検証画面](62-widget-layouts.png)は、拡張機能と共通のViewをアプリ内に表示したものです。実際のホーム画面とは区別しています。

## Issue #52〜#57

[1日表示の日付移動](64-overview-date-navigation.png) / [付箋のコピー](65-copy-sticky.png) / [計画上部のUndo](66-undo-plan.png)

<img src="67-font-settings.png" width="260" alt="文字サイズ150%の設定">
<img src="68-large-font-plan.png" width="260" alt="文字サイズに合わせて予定高さと時刻欄も広がった計画画面">
<img src="69-large-font-day.png" width="260" alt="文字サイズ150%の1日表示">

## ドラッグ中の時刻調整

<img src="70-precision-move.png" width="300" alt="開始時刻を5分刻みの拡大ルーラーで調整">
<img src="71-precision-resize.png" width="300" alt="終了時刻と所要時間を大きく表示して長さを調整">

実際のUIテストでドラッグを継続している間にシミュレーターから直接撮影しました。指を離すと表示が消えて確定します。

[文字150%での拡大表示](72-precision-large-text.png) / [横向きのコンパクト表示](73-precision-landscape.png)

## 現在時刻付近の時間割ウィジェット

<img src="74-widget-near-now-layouts.png" width="300" alt="小・中サイズの時間割ウィジェットの表示検証">
<img src="75-widget-near-now-home.png" width="300" alt="ホーム画面の実ウィジェットに現在時刻の線と前後の予定を表示">

74は拡張と同じViewを使う検証画面（08:00）、75は実際のホーム画面（シミュレーター時刻に合わせたサンプル予定）です。62・63は変更前の表示です。

## 多数の履歴がある状態での操作確認

<img src="76-performance-plan.png" width="300" alt="履歴1000件と当日41件のサンプルで移動・拡大・折りたたみを検証した画面">

2026年10月30日撮影。赤い現在時刻線はテスト用08:00。静止画による速度の比較ではなく、操作テスト後の表示確認です。
