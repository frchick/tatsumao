import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'text_ballon_widget.dart';
import 'globals.dart';

//----------------------------------------------------------------------------
// 表示している領域をズームを切り替えながら表示してキャッシュ
void cacheMapTiles(BuildContext context)
{
  cacheMapTilesSub(context);
}

Future<void> cacheMapTilesSub(BuildContext context) async
{
  final zoom = mainMapController!.camera.zoom;
  final center = mainMapController!.camera.center;
  final bounds = mainMapController!.camera.visibleBounds;
  final w = bounds.west;
  final e = bounds.east;
  final n = bounds.north;
  final s = bounds.south;
  print(">cacheMapTiles(): zoom=$zoom, W=$w, E=$e, N=$n, S=$s");

  // 画面幅から、プログレスバー(ダイアログコンテンツ)の幅を計算
  // NOTE: AlertDialog は content の左右にデフォルトで24pxのパディング
  // NOTE: ダイアログの外側は、デフォルトで40pxのマージン(_defaultInsetPadding)
  const sidePadding = 24 + 40;
  final double contentWidth = min(400, (getScreenWidth() - (2 * sidePadding)));

  // プログレスバーをもつ進捗表示ダイアログ
  // 描画更新用
  final updateStream = StreamController<bool>();
  // 進捗表示用
  double progress = 0.0;
  int currentLevel = 0;
  int currentTotalStep = 0;
  int currentStep = 0;
  // キャンセルフラグ
  bool cancelFlag = false;
  // 進捗ダイアログを表示
  final dialogKey = GlobalKey();
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        key: dialogKey,
        title: const Text('地図キャッシュ処理中'),
        content: Container(
          width: contentWidth,
          child: StreamBuilder<bool>(
            stream: updateStream.stream,
            builder: (context, snapshot) {
              final infoText =
                "Zoom:$currentLevel Step:($currentStep/$currentTotalStep)";
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SizedBox( // プログレスバーは明示的にサイズを指定する必要あり
                        width: (contentWidth - 40),
                        child: LinearProgressIndicator(value: progress)
                      ),
                      Text('${(progress * 100).toInt()}%'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(infoText),
                ]
              );
            },
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              cancelFlag = true;
            },
            child: const Text('キャンセル'),
          ),
        ],
      );
    },
  );

  // スクロールの総量を計算しておく(プログレスバーのために)
  int z = zoom.floor();
  int d = 1;
  int totalStep = 0;
  for(; z <= 18; z++){
    totalStep += (d+1)*(d+1);
    d = d * 2;
  }
  // ズームしながら、表示している範囲全体をスクロールしてキャッシュする
  z = zoom.floor();
  d = 1;
  int step = 0;
  outerloop: for(; z <= 18; z++){
    // ダイアログに表示する詳細パラメータを設定
    currentLevel = z;
    currentTotalStep = (d+1)*(d+1);
    currentStep = 0;

    // 表示している範囲全体をスクロール
    for(int y = 0; y <= d; y++){
      final lat = n + (s - n) * y / d;
      for(int x = 0; x <= d; x++){
        final lng = w + (e - w) * x / d;
        // 表示位置を移動してキャッシュ
        mainMapController!.move(LatLng(lat, lng), z as double);

        // 進捗表示
        step++;
        currentStep++;
        progress = (step as double) / (totalStep as double);
        updateStream.sink.add(true);

        // 読み込みを待つ
        await Future.delayed(const Duration(milliseconds: 1000));
        // キャンセルで抜ける
        if(cancelFlag){
          break outerloop;
        }
      }
    }
    // 次のズームレベルへ
    // マップタイルは半分のサイズになるので、スクロールのステップも半分の距離にする
    d = d * 2;
  }

  // 完了したら元の位置に戻す
  mainMapController!.move(center, zoom);

  // ダイアログを閉じる
  if(!cancelFlag){
    Navigator.of(dialogKey.currentContext!).pop();
  }

  // 完了メッセージを表示
  showTextBallonMessage(
    cancelFlag? "キャンセル": "完了",
    context: context);
}
