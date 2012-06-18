CloudForecast - server resource monitoring framework

WARNING: Alpha quality code

サーバ等のリソース監視をするためのツールです。
RRDToolの薄いラッパー、情報取得のためのフレームワークとして設計されています。
CloudForecastは、4つのプロセスによって動作します。

 - 巡回デーモン
 - グラフ閲覧 HTTPD
 - 情報取得Gearmanワーカー
 - RRDファイル更新Gearmanワーカー

小規模な監視では、Gearmanがなくても動作可能です。
動作イメージはdocsディレクトリ以下の cloudforecast.png になります

# 巡回デーモン 
$ ./cloudforecast_radar -r -c cloudforecast.yaml -l server_list.yaml
  - 起動すると5分ごとに巡回を行います
  - -r 再起動オプション。ライブラリや設定ファイルを更新すると自動で再起動します
  - -c 設定ファイル
  - -l サーバ一覧


# web server
$ ./cloudforecast_web -r -p 5000 -c cloudforecast.yaml -l server_list.yaml
  - グラフ閲覧 HTTPD
  - -p ポート httpdのport
  - -o | -host httpdがListenするIP。デフォルトはすべてのIP
  - --allow-from アクセス可能なクライアントIP/IPセグメント、複数指定可能 192.168.0.1 or 192.168.0.1/24
                 なにも指定しなければ アクセス制御はしない
  - --front-proxy リバースプロキシーを使っている場合に、そのIPアドレス/IPセグメント。複数指定可能

# 情報取得Gearmanワーカー
$ ./cf_fetcher_worker -r -c cloudforecast.yaml \
     -max-workers 2 -max-request-per-child 100 -max-exection-time 60 
  - gearmanでのリソース情報取得ワーカー
  - -max-worker preforkするワーカー数
  - -max-request-per-child 1ワーカープロセス処理回数。この回数を超えるとプロセスが新しく作り直される
  - -max-exection-time ワーカーの１回の取得作業でこれ以上の時間かかっている場合、そのワーカーを停止します

# RRDファイル更新Gearmanワーカー
$ ./cf_updater_worker -r -c cloudforecast.yaml \
     -max-workers 2 -max-request-per-child 100 -max-exection-time 60 
　- gearmanでのリソース情報をrrdファイルに書き込むワーカー

#環境変数
CF_DEBUG=1 をするとdebugログが出力されます

