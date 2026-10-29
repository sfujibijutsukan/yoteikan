# AltServerで予定館の署名を自動更新する

iPhoneの **AltStore Classic** に予定館を登録し、Macの **AltServer** と組み合わせて署名を更新します。AltStore PALはこの手順の対象ではありません。Xcodeから直接インストールした予定館の署名は、AltServerを起動するだけでは自動更新されません。

## インストール用ファイルを作る

MacにXcodeとGoが必要です。リポジトリのルートで実行します。

```sh
go run tools/altstore/main.go -client-id 398026852680-2k46epbif9as9gflbrb4e8j8o1t7lldv.apps.googleusercontent.com
```

`artifacts/altstore/Yoteikan.ipa` を生成します。Release・iPhone実機用の未署名ビルドを `Payload/Yoteikan.app` に格納します。Apple Accountへのログイン・証明書の作成は行いません。署名は初回インストール時と更新時にAltStore / AltServerが行います。

`-client-id` は今回のGoogle CloudプロジェクトのiOS用IDです。省略するとリポジトリのGoogle設定を使用します。指定してもソースやローカル設定ファイルは書き換えません。バンドルIDは `org.sfuji.yoteikan` です。

既存のIPAは上書きしません。次回は別の名前を指定できます。

```sh
go run tools/altstore/main.go -output artifacts/altstore/Yoteikan-next.ipa \
  -client-id 398026852680-2k46epbif9as9gflbrb4e8j8o1t7lldv.apps.googleusercontent.com
```

## 初回設定

1. Macで公式のAltServerを起動し、メニューバーのアイコンから **Launch at Login** を有効にします。
2. iPhoneをUSB接続し、iPhone側でMacを信頼します。FinderでiPhoneを選び「Wi-Fi接続時にこのiPhoneを表示」を有効にして適用します。
3. AltServerの **Install AltStore** から対象のiPhoneを選び、本人がApple Accountの認証を完了します。既にAltStore Classicがある場合は不要です。
4. 必要に応じてiPhoneの設定から開発者を信頼し、デベロッパモードを有効にします。
5. IPAをAirDropなどでiPhoneの「ファイル」に保存します。AltStoreの **My Apps → ＋** でIPAを選びます。
6. インストール後、予定館を起動してデータ・カレンダー・通知・Googleログインと同期を確認します。

既存の予定館は、データを保護するため先にGoogle同期を完了してください。署名アカウントやインストール方法が変わると別アプリとして扱われたり、上書きできないことがあります。既存アプリは削除せず、移行後のデータ確認まで残します。AltStoreによる再署名でバンドルIDが変わった場合、Google OAuthのバンドルIDとの整合性も実機で確認が必要です。

## 自動更新

- AltStoreの **Settings → Background Refresh** を有効にします。iPhoneの「Appのバックグラウンド更新」も有効にします。
- MacはAltServerを起動し、iPhoneと同じWi-Fiに接続するかUSBで接続しておきます。Macがスリープ中・電源オフ・ネットワークから切断されている間は更新できない場合があります。
- 最初に **My Apps → Refresh All** を押し、予定館の期限が更新されることを確認してください。その後はバックグラウンド更新を利用します。
- AltStoreの **Add to Siri…** が利用できる場合、ショートカットの「すべてのAppを更新」を個人用オートメーションから定時実行することもできます。AltServerへの接続は引き続き必要です。

無料Apple Accountの署名は通常7日で期限が切れます。バックグラウンド処理の実行時刻はiOSが判断するため、自動更新は保証されません。My Appsで残り日数を確認し、必要ならRefresh Allで更新してください。無料アカウントには同時に有効にできるアプリ数などの制限もあります。

署名更新はインストール済みバージョンの有効期限を延長する操作です。新しいソースコードをビルドして更新する場合は、新しいIPAをAltStoreへ追加します。

## 確認範囲

IPA生成と端末での署名・インストール・再署名は別の確認です。実機でのRefresh All成功と期限更新を確認するまでは、自動署名設定が完了したとは扱いません。Apple Accountの認証情報はツールやリポジトリに保存しません。

公式手順：[AltServer](https://faq.altstore.io/altstore-classic/altserver) / [AltStoreの更新設定](https://faq.altstore.io/altstore-classic/your-altstore) / [接続トラブル](https://faq.altstore.io/altstore-classic/troubleshooting-guide)

今回の検証では、Release実機ビルド・IPAのZIP整合性・`Payload/Yoteikan.app` の格納・iPhoneOS対象・バンドルIDと指定したGoogleクライアントIDを確認しました。不正なクライアントIDの拒否と既存IPAの上書き防止も確認済みです。iPhoneのAltStoreへの登録、Refresh All、バックグラウンドでの期限更新は未確認です。
