# スクリーンショット

iPhone 17eシミュレーター / iOS 27.0でXCTestを使って実際に操作し、2026年10月25日に撮影しました。デモ表記付きの画面はサンプル計画、カレンダー画面はEventKitに登録した検証用予定です。

画面1〜20をゾーン構成の変更後に更新しました。画面18は縦2分割、画面19は詳細メモ、画面20は横3分割です。時間帯設定、移動つまみ、日付スワイプ、色の追加・編集・削除も含みます。

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
