import 'dart:async';   // Stream使った再描画
import 'dart:html';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:location/location.dart';
import 'distance_circle_layer.dart';  // 二点間の距離の計算
import 'mypolyline_layer.dart'; // マップ上のカスタムポリライン

class MyLocationMarker
{
  // GPS位置情報へのアクセス
  Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription = null;
  // 座標更新時のコールバック
  Function(LocationData)? _onLocationChanged;
  set onLocationChanged(Function(LocationData) callback) => _onLocationChanged = callback;
  // GPS位置情報を表示するか
  bool _enable = false;
  bool get enabled => _enable;
  // UIの再描画
  var _updateMyLocationStream = StreamController<void>.broadcast();
  // 最新の座標
  var _myLocation = LocationData.fromMap({
    "latitude": 35.681236,
    "longitude": 139.767125,
    "heading": 0.0,
  });
  // NOTE: LocationData.heading が null の場合に備えて、直前の値を記録
  double _heading = 0.0;
  LocationData get location => _myLocation;
  // 地図上に表示するマーカー
  List<Marker> _markers = [];
  // 地図上に表示するライン
  List<MyPolyline> _polylines = [];
  // 地図へのアクセス
  final MapController _mapController;

  MyLocationMarker(this._mapController);

  // Flutter_map のレイヤーオプションを返す
  MarkerLayerOptions getLayerOptions()
  {
    return MarkerLayerOptions(
      markers: _markers,
      rebuild: _updateMyLocationStream.stream,  // 再描画のトリガー
      usePxCache: false,  // NOTE: 無効にしないと、rebuild で再描画されない
    );
  }

  // Flutter_map のレイヤーオプションを返す
  MyPolylineLayerOptions getLineLayerOptions()
  {
    return MyPolylineLayerOptions(
      polylines: _polylines,
      rebuild: _updateMyLocationStream.stream,  // 再描画のトリガー
    );
  }

  // GPSを有効化
  Future<bool> enable(BuildContext context) async
  {
    if(_enable) return true;

    // GPS機能の有無の確認
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        print('>GPSサービスが無効です');
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              content: Text("GPSサービスが無効です"),
            );
          },
        );
        return false;
      }
    }

    // GPSのパーミッションの確認
    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        print('>GPSのパーミッションが無効です');
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              content: Text("GPSのパーミッションが無効です"),
            );
          },
        );
        return false;
      }
    }

    // 有効化
    _enable = true;

    // GPS位置情報が変化したら、マーカー座標を更新
    _locationSubscription = _location.onLocationChanged.listen((LocationData locationData) {
      // 座標を更新
      updateLocation(locationData);
      // コールバックが設定されていれば実行
      if(_onLocationChanged != null){
        _onLocationChanged!(locationData);
      }
    });

    return true;
  }

  // GPSを無効化
  void disable()
  {
    if(!_enable) return;
    _enable = false; 

    // GPS位置情報の監視を解除
    _locationSubscription?.cancel();
    _locationSubscription = null;

    // マーカーとラインを非表示に
    _markers.clear();
    _polylines.clear();
    _updateMyLocationStream.sink.add(null);
  }

  // GPS位置情報を更新
  void updateLocation(LocationData location)
  {
    _myLocation = location;

    if(_enable){
      // マーカーを再作成。リストそのものは使いまわす。
      _heading = location.heading ?? _heading;
      var marker = Marker(
        point: LatLng(location.latitude!, location.longitude!),
        width: 36,
        height: 36,
        builder: (ctx) =>
          Transform.rotate(
            angle: (_heading * pi / 180),
            child: const Icon(Icons.navigation, size: 36, color: Colors.red),
          )
      );
      if(_markers.isEmpty){
        _markers.add(marker);
      }else{
        _markers[0] = marker;
      }

      // マーカーが画面外なら、地図の中心からのラインをひく
      _updateLine(_mapController.center);
    
      // 再描画
      _updateMyLocationStream.sink.add(null);
    }
  }

  // 地図の表示位置の変更
  void moveMap(MapController mapController, MapPosition position)
  {
    // ラインの始点を画面中央に固定
    _updateLine(position.center!);
    // 再描画
    _updateMyLocationStream.sink.add(null);
  }

  // ライン表示の更新
  void _updateLine(LatLng center)
  {
    if(!_enable) return;

    // GPS位置マーカーが画面外なら、ラインを消す
    // NOTE: 非表示なら、始点終点をマーカー位置にする(距離表示のため)
    final myPos = LatLng(_myLocation.latitude!, _myLocation.longitude!);
    final bounds = _mapController.bounds;
    final showLine = (bounds != null)? !bounds.contains(myPos) : true;

    // マーカーと画面中心の距離を計算
    final distance = calculateDistance(myPos, _mapController.center);
    late String text;
    if(distance < 1000){
      text = distance.toStringAsFixed(0) + "m";
    }else{
      text = (distance / 1000).toStringAsFixed(2) + "Km";
    }

    // 画面中央とGPS位置マーカーを結ぶラインを引く
    var line = MyPolyline(
      points: [
        (showLine? center: myPos),
        myPos,
      ],
      labelTexts: [ "", text ],
      labelTextOffset: const Offset(0, 16),
      labelTextAlign: TextAlign.center,
      labelTextStyle: const TextStyle(
        color: Colors.black,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
      strokeWidth: 4,
      isDotted: true,
      color: Colors.red,
    );
    if(_polylines.isEmpty){
      _polylines.add(line);
    }else{
      _polylines[0] = line;
    }
  }

  // GPS位置に地図を移動
  void moveMapToMyLocation()
  {
    if(!_enable) return;

    final myPos = LatLng(_myLocation.latitude!, _myLocation.longitude!);
    _mapController.move(myPos, _mapController.zoom);
  }
}
