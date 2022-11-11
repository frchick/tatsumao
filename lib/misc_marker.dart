import 'package:flutter/material.dart';
import 'dart:async';  // データベースの同期
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:firebase_database/firebase_database.dart';

import 'mydragmarker.dart';
import 'globals.dart';

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
// 汎用マーカーのデータ
class MiscMarker
{
  MiscMarker({ required this.position, this.iconType=0, this.memo="" });

  // 座標
  LatLng position;
  // アイコンタイプ
  int iconType;
  // メモ
  String memo;

  // データベースに保存する用のMapデータを取得
  Map<String, dynamic> toMapData()
  {
    return {
      "latitude": position.latitude,
      "longitude": position.longitude,
      "iconType": iconType,
      "memo": memo,
    };
  }

  // データベースに保存されたMapデータから読み込み
  bool fromMapData(Map<String,dynamic> map)
  {
    // 読み込みに失敗したら更新しない
    bool ok = true;
    late LatLng _position;
    late int _iconType;
    late String _memo;
    try {
      double latitude = map["latitude"] as double;
      double longitude = map["longitude"] as double;
      _position = LatLng(latitude, longitude);
      _iconType = map["iconType"] as int;
      _memo = map["memo"] as String;
    } catch(e) {
      ok = false;
    }
    if(ok){
      position = _position;
      iconType = _iconType;
      memo = _memo;
    }
    return ok;
  }

  // マップ上に表示する用のマーカーを作成
  MyDragMarker makeMapMarker(int index)
  {
    //!!!!
    print(">MiscMarker.makeMapMarker(${index})");

    return MyDragMarker(
      point: position,
      builder: (cnx) => _icons[iconType].image!,
      width: 64,
      height: 64,
      offset: Offset(0.0, 64/2),
      feedbackOffset: Offset(0.0, 64/2),
      index: index,
      onDragEnd: onMapMarkerDragEnd,
    );
  }

  LatLng onMapMarkerDragEnd(DragEndDetails detail, LatLng pos, Offset offset, int index, MapState? state)
  {
    //!!!!
    print(">MiscMarker.onMapMarkerDragEnd(${index})");

    position = pos;
    miscMarkers.sync();

    return pos;
  }
}

//-----------------------------------------------------------------------------
// 汎用マーカー
class MiscMarkers
{
  // 汎用マーカーのデータの配列
  List<MiscMarker> _markers = [];

  // リソースを読み込み
  void initialize()
  {
    _icons.forEach((icon){
      icon.image = Image.asset(icon.path);
    });
  }

  // マーカーを追加
  void addMarker(MiscMarker marker)
  {
    final int index = _markers.length;
    _markers.add(marker);
    _mapOption.markers.add(marker.makeMapMarker(index));
  }

  // クリア
  void clear()
  {
    _syncListener?.cancel();
    _syncListener = null;
    _markers.clear();
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

  //-----------------------------------------------------------------------------
  // 変更の同期
  
  // 現在開いているファイルのパス
  String _openedPath = "";

  // 変更通知を受け取るリスナー
  StreamSubscription<DatabaseEvent>? _syncListener;

  // 変更通知が initSync() による初期化によるものかを判定するフラグ
  bool _firstOnSyncAfterOpenFile = true;

  // 変更を送る
  void sync()
  {
    //!!!!
    print(">MiscMarkers.sync(${_openedPath})");

    // マーカー数が少ない想定なので、全マーカーを配列で一括で送る
    final String path = "assign" + _openedPath + "/misc_markers";
    final DatabaseReference ref = FirebaseDatabase.instance.ref(path);
    List<Map<String,dynamic>> data = [];
    _markers.forEach((marker){
      data.add(marker.toMapData());
    });
    ref.set({
      "sender_id": appInstKey,
      "markers": data,
    });
  }

  // 変更通知の受信を設定
  // ファイルを開いたタイミングで呼び出される
  void initSync(String openedPath)
  {
    //!!!!
    print(">MiscMarkers.initSync(${openedPath})");
  
    // 直前の変更通知リスナーを停止
    _syncListener?.cancel();
    _syncListener = null;

    _openedPath = openedPath;
    final String path = "assign" + _openedPath + "/misc_markers";
    final DatabaseReference ref = FirebaseDatabase.instance.ref(path);
    _firstOnSyncAfterOpenFile = true;
    _syncListener = ref.onValue.listen((DatabaseEvent event){
      _onSync(event);
    });
  }

  // 変更通知受けたときの処理
  void _onSync(DatabaseEvent event)
  {
    //!!!!
    print(">MiscMarkers._onSync(${event.snapshot.ref.path})");

    try {
      var data = event.snapshot.value as Map<String, dynamic>;
      // 自分自身からの変更通知ならば無視する
      // ただしファイルオープン直後は初期化のために読み込む
      if(_firstOnSyncAfterOpenFile){
        //!!!!
        print("> ... first sync.");
      }else{
        final String sender_id = data["sender_id"] as String;
        if(sender_id == appInstKey){
          //!!!!
          print("> ... from myself.");
          return;
        }
      }

      // 他のユーザーからの通知、もしくはファイルオープン時の初期化ならば、マーカーリストを構築
      _markers.clear();
      _mapOption.markers.clear();
      final List<dynamic> markers = data["markers"] as List<dynamic>;
      markers.forEach((data){
        var map = data as Map<String,dynamic>;
        var marker = MiscMarker(position:LatLng(0,0));
        bool ok = marker.fromMapData(map);
        if(ok){
          addMarker(marker);
        }
      });
    } catch(e) {
      //!!!!
      print("> ... Exception !");
    }
    // 再描画
    updateMapView();

    _firstOnSyncAfterOpenFile = false;
  }
}
