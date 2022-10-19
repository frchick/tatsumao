import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

//----------------------------------------------------------------------------
// 地図関連

// 地図のコントローラ
late MapController mainMapController;

// 地図上のマーカーの再描画
void updateMapView()
{
  if(mainMapController == null) return;

  // ここからは通常の方法で更新できないので、MapController 経由で地図を微妙に動かして再描画を走らせる。
  // MyDragMarkerPlugin.createLayer() で作成した StreamBuilder が動作する。
  const double jitter = 1.0/4096.0;
  var center = mainMapController.center;
  var zoom = mainMapController.zoom;
  mainMapController.move(center, zoom + jitter);
  mainMapController.move(center, zoom);

  // NOTE:
  // MapController._state.rebuildLayers() を呼び出せればスマートに再描画できるが、
  // _state がプライベートメンバーでアクセッサもないので断念。
}

// 編集がロックされているか
bool lockEditing = false;

//----------------------------------------------------------------------------
// 画面サイズ関連

// ウィンドウサイズを参照するためのキー
GlobalKey appScaffoldKey = GlobalKey();

// 画面サイズの取得(幅)
double getScreenWidth()
{
  return (appScaffoldKey.currentContext?.size?.width ?? 0.0);
}
// 画面サイズの取得(高さ)
double getScreenHeight()
{
  return (appScaffoldKey.currentContext?.size?.height ?? 0.0);
}
