# tatsumao

タツマ配置とGPSログ可視化のアプリ。

## GitHub リポジトリ

https://github.com/frchick/tatsumao

## flutterバージョン

> flutter --version
Flutter 3.13.9 • channel stable • https://github.com/flutter/flutter.git
Framework • revision d211f42860 (4 days ago) • 2023-10-25 13:42:25 -0700
Engine • revision 0545f8705d
Tools • Dart 3.1.5 • DevTools 2.25.0

## flutterバージョンの切り替え(fvmインストール済み)

> fvm use 3.13.9

## ローカルChromeでのデバッグ実行

> flutter run -d chrome

## ローカルChromeでのリリースビルド実行

> flutter build web --release --web-renderer canvaskit 
> git apply flutter_service_worker.patch
> cd build/web
> python -m http.server 8080

Chromeで開く.
http://localhost:8080/


## ビルドゴミの定期的な削除

"C:\Users\nag\AppData\Local\Temp"

## デプロイ

GitHub Actionでビルドされて、以下のURLでデプロイ。(Google Firebase Hosting)
https://tatsumao-976e2.web.app/

## Google Firebase

frchick.00@gmail.com
ノートPCの606、全部小文字。


## Firebase Storage から画像を読み込む。

Firebase Storage に対してクロスサイトオリジンを設定する。
https://qiita.com/chima91/items/0cd46b5965e087609ef5

+ gsutil をインストールする。
  https://cloud.google.com/storage/docs/gsutil_install?hl=ja#windows

+ "Google Cloud SDK Shell" で以下を実行
  >gsutil cors set cors.json gs://tatsumao-976e2.appspot.com

Google Cloud Storage と Firebase storage は、実は同一。
Cloud Storage からみたバケットのパス
  + gs://tatsumao-976e2.appspot.com

Cloud Storage からアクセスすると、より多くの設定が可能。
  + キャッシュ制御
    + https://cloud.google.com/storage/docs/metadata?hl=ja#cache-control
  + データを一般公開する(必須)
    + https://cloud.google.com/storage/docs/access-control/making-data-public?hl=ja#console


## Service Worker をカスタマイズして、地図タイルと Cloud Storage をキャッシュ

オリジナルのソース
/test/flutter_service_worker.js

※ローカルでリリースビルドして更新する。

書き換えて、以下でパッチファイルを作成
>git diff /test/flutter_service_worker.js > flutter_service_worker.patch
