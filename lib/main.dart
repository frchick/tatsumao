import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';
import 'mydragmarker.dart';
import 'mydrag_target.dart';

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

// タツマのマーカー配列
List<Marker> tatsumaMarkers = [];

//----------------------------------------------------------------------------
// メンバーデータ
class Member {
  Member({
    required this.name,
    required this.iconPath,
    required this.pos,
    this.attended = false,
  });
  String name;
  String iconPath;
  LatLng pos;
  bool attended;
  late Image icon0;
}

List<Member> members = [
  Member(name:"ママっち", iconPath:"assets/member_icon/000.png", pos:LatLng(35.302880, 139.05100), attended: true),
  Member(name:"パパっち", iconPath:"assets/member_icon/002.png", pos:LatLng(35.302880, 139.05200), attended: true),
  Member(name:"高桑さん", iconPath:"assets/member_icon/006.png", pos:LatLng(35.302880, 139.05300), attended: true),
  Member(name:"今村さん", iconPath:"assets/member_icon/007.png", pos:LatLng(35.302880, 139.05400), attended: true),
  Member(name:"しゅうちゃん", iconPath:"assets/member_icon/004.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"まなみさん", iconPath:"assets/member_icon/008.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"がんちゃん", iconPath:"assets/member_icon/011.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"ガマさん", iconPath:"assets/member_icon/005.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"たかちん", iconPath:"assets/member_icon/009.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"加藤さん", iconPath:"assets/member_icon/010.png", pos:LatLng(35.302880, 139.05500), attended: true),
  Member(name:"娘っち", iconPath:"assets/member_icon/001.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"りんたろー", iconPath:"assets/member_icon/003.png", pos:LatLng(35.302880, 139.05200)),
];

// メンバーのマーカー配列
// 出動していないメンバー分もすべて作成。表示/非表示を設定しておく。
List<MyDragMarker> memberMarkers = [];

//----------------------------------------------------------------------------
// 地図
late MapController mainMapController;

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
// 家ボタン＆メンバー一覧メニュー
class HomeButtonWidget extends StatefulWidget {
  HomeButtonWidget({super.key});

  @override
  State<HomeButtonWidget> createState() => _HomeButtonWidgetState();
}

class _HomeButtonWidgetState extends State<HomeButtonWidget>
{
  late StateSetter _setModalState;

  // メンバー一覧メニューからドラッグして出動！
  void onDragEndFunc(MyDraggableDetails details)
  {
    print("Draggable.onDragEnd: wasAccepted: ${details.wasAccepted}, velocity: ${details.velocity}, offset: ${details.offset}, data: ${details.data}");

    // ドラッグ座標からマーカーの緯度経度を計算
    // ドラッグ座標はマーカー左上なので、下矢印の位置にオフセットする。
    var px = details.offset.dx + 32;
    var py = details.offset.dy + 72;
    LatLng? point = mainMapController.pointToLatLng(CustomPoint(px, py));

    // メニュー領域の再描画
    if(_setModalState != null){
      _setModalState((){
        // データとマップ上マーカーを出動/表示状態に
        int index = details.data;
        members[index].attended = true;
        memberMarkers[index].visible = true;
        if(point != null){
          members[index].pos = point;
          memberMarkers[index].point = point;
        }
      });
    }

    // 地図上のマーカーの再描画
    // ここからは通常の方法で更新できないので、MapController 経由で地図を微妙に動かして再描画を走らせる。
    // MyDragMarkerPlugin.createLayer() で作成した StreamBuilder が動作する。
    const double jitter = 1.0/4096.0;
    var center = mainMapController.center;
    var zoom = mainMapController.zoom;
    mainMapController!.move(center, zoom + jitter);
    mainMapController!.move(center, zoom);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context)
  {
    return Align(
      // 画面右下に配置
      alignment: Alignment(1.0, 1.0),
      // 家アイコンとそのスタイル
      child: ElevatedButton(
        child: Icon(Icons.home, size: 50),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.orange.shade900,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          fixedSize: Size(80,80),
        ),

        // 家ボタンタップでメンバー一覧メニューを開く
        onPressed: (){
          // メンバー一覧メニューを開く
          showModalBottomSheet<void>(
            context: context,
            builder: (BuildContext context) {
              // メンバー一覧メニューの構築(再描画)
              return StatefulBuilder(
                builder: (context, StateSetter setModalState) {
                  _setModalState = setModalState;
                  // 出動していないメンバーのアイコンを並べる
                  List<Widget> draggableIcons = [];
                  int index = 0;
                  members.forEach((member) {
                    if(!member.attended){
                      draggableIcons.add(
                        MyDraggable<int>(
                          data: index,
                          child: member.icon0,
                          feedback: member.icon0,
                          childWhenDragging: Container(
                            width: 64,
                            height: 72,
                          ),
                          onDragEnd: onDragEndFunc,
                        )
                      );
                    }
                    index++;
                  });
                  return Container(
                    height: 120,
                    color: Colors.brown.shade100,
                    child: Center(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children : draggableIcons,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
        
        // 家アイコンの上でメンバーマーカーをドロップしたら帰宅、のためのフラグ記録
        onHover: (value){
          hoverHouseIson = value;
        },
      )
    );
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

class _TestAppState extends State<TestApp>
{
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
    members.forEach((member) {
      // アイコンを読み込んでおく
      member.icon0 = Image.asset(member.iconPath, width:64, height:72);
      // マーカーを作成
      memberMarkers.add(
        MyDragMarker2(
          point: member.pos,
          builder: (ctx) => Image.asset(member.iconPath),
          index: memberIndex,
          onDragEnd: onDragEndFunc,
          visible: member.attended,
        )
      );
      memberIndex++;
    });

    // 地図コントローラを作成
    mainMapController = MapController();
  
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
                  mapController: mainMapController,
                ),

                // 家アイコン
                HomeButtonWidget(),

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

  //---------------------------------------------------------------------------
  // ドラッグ終了時の処理
  LatLng onDragEndFunc(DragEndDetails details, LatLng point, int index, MapState? mapState)
  {
    // 家アイコンに投げ込まれたら削除する
    if(hoverHouseIson){
        // メンバーマーカーを非表示にして再描画
        setState((){
          memberMarkers[index].visible = false;
          members[index].attended = false;

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
