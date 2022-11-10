import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:firebase_database/firebase_database.dart';

import 'mydragmarker.dart';

//-----------------------------------------------------------------------------

MiscMarkers miscMarkers = MiscMarkers();

// アイコン
class _MiscMarkerIcon
{
  _MiscMarkerIcon({ required this.path });

  // パス
  final String path;
  // アイコン画像
  Image? image;
}
List<_MiscMarkerIcon> _icons = [
  _MiscMarkerIcon(path:"assets/misc/deer_icon0.png"),
];

//-----------------------------------------------------------------------------
// 汎用マーカー
class MiscMarkers
{
  // リソースを読み込み
  void initialize()
  {
    _icons.forEach((icon){
      icon.image = Image.asset(icon.path);
    });
  }

  // マーカーを追加
  void addMarker(LatLng pos)
  {
    _mapOption.markers.add(MyDragMarker(
      point: pos,
      builder: (cnx) => _icons[0].image!,
      width: 64,
      height: 64,
      offset: Offset(0.0, 64/2),
      feedbackOffset: Offset(0.0, 64/2),
      index: 0,
    ));
  }

  // クリア
  void clear()
  {
    _mapOption.markers.clear();
  }

  //-----------------------------------------------------------------------------
  // FlutterMap のマーカーリストを含むレイヤーデータを取得
  MyDragMarkerPluginOptions _mapOption = MyDragMarkerPluginOptions(
    markers: [],
  );

  MyDragMarkerPluginOptions getMapLayerOptions()
  {
    return _mapOption;
  }
}
