import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'mydragmarker.dart';   // マップ上のメンバーマーカー
import 'distance_circle_layer.dart';

//----------------------------------------------------------------------------
// バージョン表示
const appVersion = "2.1.2";

//----------------------------------------------------------------------------
// 地図関連

// 地図のコントローラ
MapController? mainMapController;

// マップ上のメンバーマーカーの作成オプション
// ドラッグ許可/禁止を後から変更するために、インスタンスをアクセス可能に定義する
late MyDragMarkerPluginOptions mainMapDragMarkerPluginOptions;

// 地図上のマーカーの再描画
void updateMapView()
{
  if(mainMapController == null) return;

  // ここからは通常の方法で更新できないので、MapController 経由で地図を微妙に動かして再描画を走らせる。
  // MyDragMarkerPlugin.createLayer() で作成した StreamBuilder が動作する。
  const double jitter = 1.0/4096.0;
  var center = mainMapController!.center;
  var zoom = mainMapController!.zoom;
  mainMapController!.move(center, zoom + jitter);
  mainMapController!.move(center, zoom);

  // NOTE:
  // MapController._state.rebuildLayers() を呼び出せればスマートに再描画できるが、
  // _state がプライベートメンバーでアクセッサもないので断念。
}

// 編集がロックされているか
bool lockEditing = false;

// このアプリケーションインスタンスを一意に識別するキー
// マーカーのドラッグによる変更通知が、自分自身によるものか、他のユーザーからかを識別
final String appInstKey = UniqueKey().toString();

// 地図上の距離サークル
DistanceCircleLayerOptions? distanceCircle;

//----------------------------------------------------------------------------
// 画面サイズ関連

// ウィンドウサイズを参照するためのキー
final appScaffoldKey = GlobalKey<ScaffoldState>();

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

//----------------------------------------------------------------------------
// BottomSheet

PersistentBottomSheetController<void>? bottomSheetController;

// BottomSheet を閉じる
void closeBottomSheet()
{
  bottomSheetController?.close();
}

//----------------------------------------------------------------------------
// ポップアップメニューのヘルパー

PopupMenuItem<int> makePopupMenuItem(
  int value, String text, IconData icon,
  { bool enabled=true, Color iconColor=Colors.black45})
{
  return PopupMenuItem<int>(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, color:iconColor),
        const SizedBox(width: 5),
        Text(text),
      ]
    ),
    height: (kMinInteractiveDimension * 0.8),
  );
}

//----------------------------------------------------------------------------
// パスワード、ロック

const String startAppPasswordKey = "key";
const String startAppPasswordHash = "6992f4030e10ae944ed6a5691daa19ae"; // "910k"

const String lockEditingPasswordKey = "lockEditingKey";
const String lockEditingPasswordHash = "4f754d60f1497e9ebfd0b55ce6ef35b4"; // "musicstart"


//----------------------------------------------------------------------------
// 特殊

// 永谷専用モード
bool gNagMode = false;
int gNagModeCount = 0;
