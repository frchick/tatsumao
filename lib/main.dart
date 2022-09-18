import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';
import 'mydragmarker.dart';

//----------------------------------------------------------------------------
// タツマデータ
class TatsumaData {
  TatsumaData({
    required this.pos,
    required this.name
  });
  late LatLng pos;
  late String name;
}

List<TatsumaData> tatsumas = [
  TatsumaData(pos:LatLng(35.306227, 139.049396), name:"岩清水索道"),
  TatsumaData(pos:LatLng(35.307217, 139.051598), name:"岩清水中"),
  TatsumaData(pos:LatLng(35.306809, 139.052676), name:"岩清水下"),
  TatsumaData(pos:LatLng(35.306282, 139.047802), name:"岩清水"),
  TatsumaData(pos:LatLng(35.305798, 139.054232), name:"赤エル"),
  TatsumaData(pos:LatLng(35.30636, 139.05427), name:"裏赤エル"),
  TatsumaData(pos:LatLng(35.305804, 139.055972), name:"ストッパー"),
  TatsumaData(pos:LatLng(35.304213, 139.046478), name:"新トナカイ"),
  TatsumaData(pos:LatLng(35.305561, 139.045259), name:"トナカイ"),
  TatsumaData(pos:LatLng(35.302601, 139.04473), name:"ムロ岩の先"),
  TatsumaData(pos:LatLng(35.302488, 139.044131), name:"ムロ岩"),
  TatsumaData(pos:LatLng(35.301932, 139.043382), name:"スター"),
  TatsumaData(pos:LatLng(35.301166, 139.043601), name:"アメリカ"),
  TatsumaData(pos:LatLng(35.300012, 139.044023), name:"太平洋"),
  TatsumaData(pos:LatLng(35.30026, 139.046538), name:"メキシコ"),
  TatsumaData(pos:LatLng(35.29942, 139.04639), name:"沢の上"),
];

//----------------------------------------------------------------------------
// メンバーデータ
class Member {
  Member({
    required this.name,
    required this.iconPath,
    required this.pos
  });
  late String name;
  late String iconPath;
  late LatLng pos;
}

List<Member> members = [
  Member(name:"ママっち", iconPath:"assets/member_icon/000.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"パパっち", iconPath:"assets/member_icon/002.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"高桑さん", iconPath:"assets/member_icon/006.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"今村さん", iconPath:"assets/member_icon/007.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"しゅうちゃん", iconPath:"assets/member_icon/004.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"まなみさん", iconPath:"assets/member_icon/008.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"がんちゃん", iconPath:"assets/member_icon/011.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"ガマさん", iconPath:"assets/member_icon/005.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"たかちん", iconPath:"assets/member_icon/009.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"加藤さん", iconPath:"assets/member_icon/010.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"娘っち", iconPath:"assets/member_icon/001.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"りんたろー", iconPath:"assets/member_icon/003.png", pos:LatLng(35.302880, 139.05200)),
];


//----------------------------------------------------------------------------
// ドラッグ終了時の処理
LatLng onDragEndFunc(DragEndDetails details, LatLng point, MapState? mapState) {
  // タツママーカーにスナップ
  if (mapState != null) {
    var pixelPos0 = mapState.project(point);
    num minDist = (18.0 * 18.0);
    tatsumas.forEach((element) {
      var pixelPos1 = mapState.project(element.pos);
      num dx = (pixelPos0.x - pixelPos1.x).abs();
      num dy = (pixelPos0.y - pixelPos1.y).abs();
      if ((dx < 16) && (dy < 16)) {
        num d = (dx * dx) + (dy * dy);
        if(d < minDist){
          minDist = d;
          point = element.pos;
        }
      }
    });
    if(minDist < (18.0 * 18.0)){
      print("Snap!");
    }
  }
  print("End point $point");
  return point;
}

//----------------------------------------------------------------------------
// メンバーマーカーの拡張クラス
class MyDragMarker2 extends MyDragMarker {
  MyDragMarker2({
    required super.point,
    super.builder,
    super.feedbackBuilder,
    super.width = 64.0,
    super.height = 72.0,
    super.offset = const Offset(0.0, -36.0),
    super.feedbackOffset = const Offset(0.0, -36.0),
    super.onDragStart,
    super.onDragUpdate,
    super.onDragEnd = onDragEndFunc,
    super.onTap,
    super.onLongPress,
    super.updateMapNearEdge = false, // experimental
    super.nearEdgeRatio = 2.0,
    super.nearEdgeSpeed = 1.0,
    super.rotateMarker = false,
    AnchorPos? anchorPos,
  }) {
  }
}

//----------------------------------------------------------------------------

void main() {
  runApp(TestApp());
}

class TestApp extends StatefulWidget {
  @override
  _TestAppState createState() => _TestAppState();
}

class _TestAppState extends State<TestApp> {
  // タツマのマーカー配列
  List<Marker> tatsumaMarkers = [];

  // メンバーのマーカー配列
  List<MyDragMarker> memberMarkers = [];

  @override
  void initState() {
    super.initState();

    // タツマデータからマーカー配列を作成
    tatsumas.forEach((element) {
      tatsumaMarkers.add(Marker(
        point: element.pos,
        width: 100.0,
        height: 96.0,
        builder: (ctx) => Column(
          children: [
            Text(""),
            Image.asset("assets/misc/tatsu_pos_icon.png", width: 32, height: 32),
            Text(element.name, style:TextStyle(fontWeight: FontWeight.bold))
          ],
          mainAxisAlignment: MainAxisAlignment.center,
        )
      ));
    });

    // メンバーデータからマーカー配列を作成
    members.forEach((element) {
      memberMarkers.add(
        MyDragMarker2(
          point: element.pos,
          builder: (ctx) => Image.asset(element.iconPath),
        )
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Container(
            child: FlutterMap(
              options: MapOptions(
                allowPanningOnScrollingParent: false,
                plugins: [
                  MyDragMarkerPlugin(),
                ],
                center: LatLng(35.302894, 139.053848),
                zoom: 16,
                maxZoom: 18,
              ),
              nonRotatedLayers: [
                TileLayerOptions(
                  urlTemplate: "https://cyberjapandata.gsi.go.jp/xyz/hillshademap/{z}/{x}/{y}.png",
                ),
                TileLayerOptions(
                  urlTemplate: "https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png",
                  opacity: 0.64
                ),
                MarkerLayerOptions(
                  markers: tatsumaMarkers
                ),
                MyDragMarkerPluginOptions(
                  markers: memberMarkers,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}