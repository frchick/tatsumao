import 'dart:async';   // Stream使った再描画
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
// NOTE: flutter_map 2.0.0のplugin_api.dartは廃止
export 'package:flutter_map/src/misc/bounds.dart';
export 'package:flutter_map/src/misc/center_zoom.dart';
export 'package:flutter_map/src/map/controller/map_controller_impl.dart';
import 'package:location/location.dart';

class MyLocationMarkerLayer extends StatefulWidget{
  final GlobalKey<_MyLocationMarkerState> key = GlobalKey<_MyLocationMarkerState>();

  MyLocationMarkerLayer({Key? key, required this.mapController}) : super(key: key);

  // 地図へのアクセス
  final MapController mapController;

  @override
  _MyLocationMarkerState createState() => _MyLocationMarkerState();

  // GPS位置情報を表示するか
  bool? get isEnable => key.currentState?.enabled;

  // NOTE: GlobalKeyを用いたsteteの関数呼び出しは，一度画面に描画してからでないと実行できない
  // GPSを有効化
  Future<bool>? enable(BuildContext context) {
    return key.currentState?.enable(context);
  }

  // GPSを無効化
  void disable(){
    key.currentState?.disable();
  }

  // GPS位置情報を更新
  void updateLocation(LocationData location){
    key.currentState?.updateLocation(location);
  }

  // 地図の表示位置の変更
  void moveMap(MapController mapController, MapCamera camera){
    key.currentState?.moveMap(mapController, camera);
  }

  // GPS位置に地図を移動
  void moveMapToMyLocation(){
    key.currentState?.moveMapToMyLocation(); 
  }
}

class _MyLocationMarkerState extends State<MyLocationMarkerLayer>
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
  List<Polyline> _polylines = [];

  // 初期化
  @override void initState() {
    super.initState();
  }

  // Fluter_mapのレイヤーをかえす
  @override
  Widget build(BuildContext context){
    return Stack(
      children: [
        MarkerLayer(markers: _markers),
        PolylineLayer(polylines: _polylines)
      ],
    );
  }

  // GPSを有効化
  Future<bool> enable(BuildContext context) async
  {
    if(_enable) return true;

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

    //return true;
    return false;
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
    setState(() { });
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
        child: Transform.rotate(
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
      _updateLine(widget.mapController.camera.center);
    
      // 再描画
      setState(() { });
    }
  }

  // 地図の表示位置の変更
  void moveMap(MapController mapController, MapCamera camera)
  {
    // ラインの始点を画面中央に固定
    _updateLine(camera.center);
    // 再描画
    setState(() { });
  }

  // ライン表示の更新
  void _updateLine(LatLng center)
  {
    if(!_enable) return;

    // GPS位置マーカーが画面外なら、ラインを消す
    // NOTE: 非表示なら、始点終点をマーカー位置にする(距離表示のため)
    final myPos = LatLng(_myLocation.latitude!, _myLocation.longitude!);
    final bounds = widget.mapController.camera.visibleBounds;
    final showLine = (bounds != null)? !bounds.contains(myPos) : true;

    // マーカーと画面中心の距離を計算
    const distance = Distance();
    final D = distance(myPos, widget.mapController.camera.center);
    late String text;
    if(D < 1000){
      text = D.toStringAsFixed(0) + "m";
    }else{
      text = (D / 1000).toStringAsFixed(2) + "Km";
    }

    // 画面中央とGPS位置マーカーを結ぶラインを引く
    var line = Polyline(
      points: [
        (showLine? center: myPos),
        myPos,
      ],
      pattern: const StrokePattern.dotted(),
      strokeWidth: 4,
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
    widget.mapController.move(myPos, widget.mapController.camera.zoom);
  }
}
