# スクリーンショット

iPhone 17eシミュレーター / iOS 27.0でXCTestを使って実際に操作し、2026年10月25日に撮影しました。デモ表記付きの画面はサンプル計画、カレンダー画面はEventKitに登録した検証用予定です。

画面1・2・16・17・20・22・23は、アプリ名の見出しを外し、時間の横棒グラフに変更した確認画面です。そのほかは拡大率追加時の確認画面です。縦2分割・詳細メモ・横3分割・右側の詳細表示、時間帯設定、移動つまみ、日付スワイプ、色の追加・編集・削除を含みます。

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
