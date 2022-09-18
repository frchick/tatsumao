import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';
import 'mydragmarker.dart';

//----------------------------------------------------------------------------
// グローバル変数

// 家アイコンにマウスが乗っているか
bool hoverHouseIson = false;

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
    super.onDragEnd,
    super.onTap,
    super.onLongPress,
    super.updateMapNearEdge = false, // experimental
    super.nearEdgeRatio = 2.0,
    super.nearEdgeSpeed = 1.0,
    super.rotateMarker = false,
    AnchorPos? anchorPos,
    required super.index,
    super.visible = true,
  }) {
  }
}


//----------------------------------------------------------------------------
// 遅延フェードアウト
class MyFadeOut extends StatefulWidget {
  final Widget child;
  
  // アニメーションの再生が終わったかのフラグ
  // Widget側のメンバーは、インスタンスを作り直すごとにリセットされる。
  // State側のメンバーは、インスタンスが作り直されても永続する？
  bool _completed = false;

  MyFadeOut({
    required this.child,
  }){}

  @override
  _MyFadeOutState createState() => _MyFadeOutState();
}

class _MyFadeOutState extends State<MyFadeOut>
    with TickerProviderStateMixin
{
  late AnimationController _controller;
  late Animation<double> _reverse;
  late Animation<double> _animation;

  @override
  initState() {
    super.initState();
    // 1.5秒のアニメーション
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this);
    // 表示→フェードアウトとなるように、値を逆転
    _reverse = Tween<double>(begin: 1.0, end: 0.0).animate(_controller);
    // フェードアウトを遅延させる
    _animation = CurvedAnimation(
      parent: _reverse,
      curve: Interval(0.0, 0.25, curve: Curves.easeIn),
    );
    // アニメーション終了時に非表示
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          widget._completed = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // アニメーション開始
    // アニメーション終了後の更新では、当然アニメーションの開始はしない。
    if(!widget._completed){
      _controller.forward(from: 0.0);
    }

    // アニメーションが終了していたら、Widgetを非表示にする。
    return Visibility(
      visible: !widget._completed,
      child: FadeTransition(opacity: _animation, child: widget.child));
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

  // ポップアップメッセージ
  late MyFadeOut popupMessage;

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
    int memberIndex = 0;
    members.forEach((element) {
      memberMarkers.add(
        MyDragMarker2(
          point: element.pos,
          builder: (ctx) => Image.asset(element.iconPath),
          index: memberIndex,
          onDragEnd: onDragEndFunc,
        )
      );
      memberIndex++;
    });

    // ポップアップメッセージ
    popupMessage = MyFadeOut(child: Text(""));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Container(
            child: Stack(
              children: [
                // 地図
                FlutterMap(
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
                // 家アイコン
                Align(
                  alignment: Alignment(1.0, 1.0),
                    child: ElevatedButton(
                      child: Icon(Icons.home, size: 50),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.grey.shade800,
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        fixedSize: Size(80,80),
                      ),
                      onPressed: (){},
                      
                      // 家アイコンの上でメンバーマーカーをドロップしたら帰宅、のためのフラグ記録
                      onHover: (value){
                        hoverHouseIson = value;
                      }
                    )
                ),
                // ポップアップメッセージ
                Align(alignment:
                  Alignment(0.0, 0.0),
                  child: popupMessage
                ),
              ]
            ),
          ),
        ),
      ),
    );
  }

  // ドラッグ終了時の処理
  LatLng onDragEndFunc(DragEndDetails details, LatLng point, int index, MapState? mapState) {
    // 家アイコンに投げ込まれたら削除する
    if(hoverHouseIson){
        // メンバーマーカーを非表示にして再描画
        setState((){
          memberMarkers[index].visible = false;

          // ポップアップメッセージ
          String msg = members[index].name + " は家に帰った";
          popupMessage = MyFadeOut(
            child: Text(
              msg,
              style:TextStyle(fontWeight: FontWeight.bold),
              textScaleFactor: 1.5,
            )
          );
        });
        
        return point;
    }

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
    }
    // メンバーデータを更新
    members[index].pos = point;

    print("End index $index, point $point");
    return point;
  }
}