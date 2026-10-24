# アプリアイコン

<img src="../ios/Yoteikan/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="256" alt="深緑の時間割に3枚の付箋を並べた予定館のアイコン">

付箋を1枚ずつ組み替えて時間割を作るアプリを、深緑のボードと淡い緑・黄・桃色の付箋で表現しました。

- アプリ用画像：[AppIcon.png](../ios/Yoteikan/Assets.xcassets/AppIcon.appiconset/AppIcon.png)
- 仕様：1024 × 1024ピクセル、不透明PNG。角のマスクはiOSに任せます。
- 組み込み：Assets.xcassetsのAppIconを、Debug / Release共通で指定。
- 作成：2026年10月24日、組み込みimage_genツールを使用。生成画像をmacOSのsipsで1024ピクセルに縮小。Pythonは使用していません。

## 組み込み確認

iPhone 17e / iOS 27.0向けのDebugビルドに成功。アプリ内のInfo.plistがAppIconを参照し、ホーム画面用の小さいアイコン画像が生成されることを確認しました。シミュレーターへのインストールと起動も確認しています。ビルドログはローカルのartifacts/icon/build.logに保存しています。

## 作成時のプロンプト

~~~text
Use case: logo-brand. Asset type: production iPhone app icon for a Japanese timeboxing app called Yoteikan (予定館). Create one beautiful minimal icon, square 1024 x 1024, full bleed opaque warm ivory background (#F7F5ED). Subject: a bold, clearly readable forest green vertical daily planner board with three large pastel sticky-note blocks arranged as a staggered time schedule: sage green, warm golden cream, and soft peach, with a subtle folded corner on the foremost note. The notes should feel individually movable. A few simple negative-space time ticks along the left connect the concept to a timetable. Restrained Japanese stationery aesthetic, calm, premium, friendly, almost flat with very subtle paper depth. Strong silhouette and generous internal safe margin, centered balanced composition legible at 60 pixels. Use the app's forest green #3D6654 and warm pastel palette. No text, letters, numerals, clock hands, checkmarks, tiny details, gradients, photo, phone mockup, borders, watermark, or external drop shadow. Do not round the outer square canvas corners: iOS supplies its own mask. Deliver only the finished square icon artwork, no presentation sheet.
~~~

[READMEへ戻る](../README.md)
