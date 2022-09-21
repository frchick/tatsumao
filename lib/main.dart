import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'mydragmarker.dart';
import 'mydrag_target.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

//----------------------------------------------------------------------------
// グローバル変数


//----------------------------------------------------------------------------
// タ��タ
class TatsumaData {
  TatsumaData({
    required this.pos,
    required this.name
  });
  late LatLng pos;
  late String name;
}

List<TatsumaData> tatsumas = [
  TatsumaData(pos:LatLng(35.306227, 139.049396), name:"岩渰�索�),
  TatsumaData(pos:LatLng(35.307217, 139.051598), name:"岩渰�中"),
  TatsumaData(pos:LatLng(35.306809, 139.052676), name:"岩渰��),
  TatsumaData(pos:LatLng(35.306282, 139.047802), name:"岩渰�"),
  TatsumaData(pos:LatLng(35.305798, 139.054232), name:"赤エル"),
  TatsumaData(pos:LatLng(35.30636, 139.05427), name:"裏赤エル"),
  TatsumaData(pos:LatLng(35.305804, 139.055972), name:"ストッパ�"),
  TatsumaData(pos:LatLng(35.304213, 139.046478), name:"新トナカイ"),
  TatsumaData(pos:LatLng(35.305561, 139.045259), name:"トナカイ"),
  TatsumaData(pos:LatLng(35.302601, 139.04473), name:"�ロ岩の�),
  TatsumaData(pos:LatLng(35.302488, 139.044131), name:"�ロ岩"),
  TatsumaData(pos:LatLng(35.301932, 139.043382), name:"スター"),
  TatsumaData(pos:LatLng(35.301166, 139.043601), name:"アメリカ"),
  TatsumaData(pos:LatLng(35.300012, 139.044023), name:"太平�),
  TatsumaData(pos:LatLng(35.30026, 139.046538), name:"メキシコ"),
  TatsumaData(pos:LatLng(35.29942, 139.04639), name:"沢の�),
];

// タ�のマ�カー配�
List<Marker> tatsumaMarkers = [];

//----------------------------------------------------------------------------
// メンバ��タ
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
  Member(name:"マ�っち", iconPath:"assets/member_icon/000.png", pos:LatLng(35.302880, 139.05100), attended: true),
  Member(name:"パパっち", iconPath:"assets/member_icon/002.png", pos:LatLng(35.302880, 139.05200), attended: true),
  Member(name:"高桑さ�, iconPath:"assets/member_icon/006.png", pos:LatLng(35.302880, 139.05300), attended: true),
  Member(name:"今村さん", iconPath:"assets/member_icon/007.png", pos:LatLng(35.302880, 139.05400), attended: true),
  Member(name:"しゅぁ�も�", iconPath:"assets/member_icon/004.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"まなみさん", iconPath:"assets/member_icon/008.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"がんちも�", iconPath:"assets/member_icon/011.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"ガマさ�, iconPath:"assets/member_icon/005.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"たかち�, iconPath:"assets/member_icon/009.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"�藤さん", iconPath:"assets/member_icon/010.png", pos:LatLng(35.302880, 139.05500), attended: true),
  Member(name:"娘っち", iconPath:"assets/member_icon/001.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"りんたろー", iconPath:"assets/member_icon/003.png", pos:LatLng(35.302880, 139.05200)),
];

// メンバ�のマ�カー配�
// 出動してぁ�ぃ�ンバ�刂�すべて作�。表示/非表示を設定しておく�
List<MyDragMarker> memberMarkers = [];

//----------------------------------------------------------------------------
// メンバ��タの同期(firebase realtime database)
FirebaseDatabase database = FirebaseDatabase.instance;

class MemberStateSync
{
  MemberStateSync();

  Future init() async
  {
    final DatabaseReference ref = database.ref("members");
    final DataSnapshot snapshot = await ref.get();
    for(int i = 0; i < members.length; i++)
    {
      Member member = members[i];
      if (snapshot.hasChild("$i")) {
        // �タベ�スから初期値を取�直前�状�
        member.attended = snapshot.child("$i/attended").value as bool;
        member.pos = LatLng(
          snapshot.child("$i/latitude").value as double,
          snapshot.child("$i/longitude").value as double);
        print("DB: Member entry exists. $i");
      } else {
        // �タベ�スにエントリがなければ追�
        await ref.set({
          "$i/attended": member.attended,
          "$i/latitude": member.pos.latitude,
          "$i/longitude": member.pos.longitude,
        });
        print("DB: No member entry. $i");
      }    
    }
  }

  void update(int index) async
  {
    Member member = members[index];
    DatabaseReference ref = database.ref("member/$index");
    await ref.update({
      "index": index,
      "attended": member.attended,
      "latitude": member.pos.latitude,
      "longitude": member.pos.longitude,
    });
  }
}


//----------------------------------------------------------------------------
// 地図
late MapController mainMapController;

// 地図上�マ�カーの再描画
void updateMapView()
{
  // ここからは通常の方法で更新できな�で、MapController 経由で地図を微妙に動かして再描画を走らせる�
  // MyDragMarkerPlugin.createLayer() で作�した StreamBuilder が動作する�
  const double jitter = 1.0/4096.0;
  var center = mainMapController.center;
  var zoom = mainMapController.zoom;
  mainMapController!.move(center, zoom + jitter);
  mainMapController!.move(center, zoom);
}

// 地図上�マ�カーにスナッ�
LatLng snapToTatsuma(LatLng point)
{
  // 画面座標に変換してマ�カーとの距離を判�
  // マ�カーサイズ�6x16である前提
  var pixelPos0 = mainMapController.latLngToScreenPoint(point);
  num minDist = (18.0 * 18.0);
  tatsumas.forEach((tatsuma) {
    var pixelPos1 = mainMapController.latLngToScreenPoint(tatsuma.pos);
    if((pixelPos0 != null) && (pixelPos1 != null)){
      num dx = (pixelPos0.x - pixelPos1.x).abs();
      num dy = (pixelPos0.y - pixelPos1.y).abs();
      if ((dx < 16) && (dy < 16)) {
        num d = (dx * dx) + (dy * dy);
        if(d < minDist){
          minDist = d;
          point = tatsuma.pos;
        }
      }
    }
  });
  return point;
}

//----------------------------------------------------------------------------
// メンバ�マ�カーの拡張クラス
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
// 遻�フェードアウ�
class MyFadeOut extends StatefulWidget {
  final Widget child;
  
  // アニメーションの再生が終わったかのフラグ
  // Widget側のメンバ�は、インスタンスを作り直すごとにリセッ�される�
  // State側のメンバ�は、インスタンスが作り直されても永続する�
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
    // 1.5秒�アニメーション
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this);
    // 表示→フェードアウトとなるよぁ�、値を逻�
    _reverse = Tween<double>(begin: 1.0, end: 0.0).animate(_controller);
    // フェードアウトを遻�させ�
    _animation = CurvedAnimation(
      parent: _reverse,
      curve: Interval(0.0, 0.25, curve: Curves.easeIn),
    );
    // アニメーション終亙�に非表示
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
    // アニメーション開�
    // アニメーション終亾��更新では、当然アニメーションの開始�しな぀
    if(!widget._completed){
      _controller.forward(from: 0.0);
    }

    // アニメーションが終亁�てぁ�ら、Widgetを非表示にする�
    return Visibility(
      visible: !widget._completed,
      child: FadeTransition(opacity: _animation, child: widget.child));
  }
}

//----------------------------------------------------------------------------
// 家ボタン��ンバ�一覧メニュー
class HomeButtonWidget extends StatefulWidget {
  HomeButtonWidget({super.key});

  @override
  State<HomeButtonWidget> createState() => _HomeButtonWidgetState();
}

class _HomeButtonWidgetState extends State<HomeButtonWidget>
{
  late StateSetter _setModalState;

  // メンバ�一覧メニューからドラヂ�して出動�
  void onDragEndFunc(MyDraggableDetails details)
  {
    print("Draggable.onDragEnd: wasAccepted: ${details.wasAccepted}, velocity: ${details.velocity}, offset: ${details.offset}, data: ${details.data}");

    // ドラヂ�座標から�ーカーの緯度経度を計�
    // ドラヂ�座標�マ�カー左上なので、下矢印の位置にオフセッ�する�
    var px = details.offset.dx + 32;
    var py = details.offset.dy + 72;
    LatLng? point = mainMapController.pointToLatLng(CustomPoint(px, py));
    if(point == null) return;

    // タ�マ�カーにスナッ�
    point = snapToTatsuma(point);

    // メニュー領域の再描画
    if(_setModalState != null){
      _setModalState((){
        // �タとマップ上�ーカーを��表示状態に
        int index = details.data;
        members[index].attended = true;
        memberMarkers[index].visible = true;
        if(point != null){
          members[index].pos = point;
          memberMarkers[index].point = point;
        }
      });
    }

    // 地図上�マ�カーの再描画
    updateMapView();
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
      // 家アイコンとそ�スタイル
      child: ElevatedButton(
        child: Icon(Icons.home, size: 50),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.orange.shade900,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          fixedSize: Size(80,80),
        ),

        // 家ボタンタ�でメンバ�一覧メニューを開�
        onPressed: (){
          // メンバ�一覧メニューを開�
          showModalBottomSheet<void>(
            context: context,
            builder: (BuildContext context) {
              // メンバ�一覧メニューの構�再描画)
              return StatefulBuilder(
                builder: (context, StateSetter setModalState) {
                  _setModalState = setModalState;
                  // 出動してぁ�ぃ�ンバ�のアイコンを並べ�
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
      )
    );
  }
}

//----------------------------------------------------------------------------

void main() {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,    
  );

  // 地図コントローラを作�
  mainMapController = MapController();

  runApp(TestApp());
}

class TestApp extends StatefulWidget {
  @override
  _TestAppState createState() => _TestAppState();
}

class _TestAppState extends State<TestApp>
{
  // ポップア�メヂ�ージ
  late MyFadeOut popupMessage;
  
  // ウィンドウサイズを参照するためのキー
  GlobalKey scaffoldKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    // メンバ��タの初期値をデータベ�スから取�
    MemberStateSync().init().then((res){
      setState((){});
    });
  
    // タ��タからマ�カー配�を作�
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

    // メンバ��タからマ�カー配�を作�
    int memberIndex = 0;
    members.forEach((member) {
      // アイコンを読み込んでおく
      member.icon0 = Image.asset(member.iconPath, width:64, height:72);
      // マ�カーを作�
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

    // ポップア�メヂ�ージ
    popupMessage = MyFadeOut(child: Text(""));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        key: scaffoldKey,
        body: Center(
          child: Container(
            child: Stack(
              children: [
                // 地図
                FlutterMap(
                  options: MapOptions(
                    allowPanningOnScrollingParent: false,
                    interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
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

                // ポップア�メヂ�ージ
                Align(
                  alignment: Alignment(0.0, 0.0),
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
  // ドラヂ�終亙�の処�
  LatLng onDragEndFunc(DragEndDetails details, LatLng point, Offset offset, int index, MapState? mapState)
  {
    // 家アイコンに投げ込まれたら削除する
    // 画面右下にサイズ80x80で表示されてあ�前提
    final double width  = (scaffoldKey.currentContext?.size?.width ?? 0.0);
    final double height = (scaffoldKey.currentContext?.size?.height ?? 0.0);
    final bool dropToHouse = 
      (0.0 < (offset.dx - (width - 80))) &&
      (0.0 < (offset.dy - (height - 80)));
    if(dropToHouse){
        // メンバ�マ�カーを非表示にして再描画
        memberMarkers[index].visible = false;
        members[index].attended = false;
        updateMapView();

        // ポップア�メヂ�ージ
        String msg = members[index].name + " は家に帰っ�;
        showPopupMessage(msg);
        
        return point;
    }

    // タ�マ�カーにスナッ�
    point = snapToTatsuma(point);

    // メンバ��タを更新
    members[index].pos = point;

    print("End index $index, point $point");
    return point;
  }

  //---------------------------------------------------------------------------
  // ポップア�メヂ�ージの表示
  void showPopupMessage(String message)
  {
    // ポップア�メヂ�ージ
    setState((){
      popupMessage = MyFadeOut(
        child: Container(
          padding: EdgeInsets.fromLTRB(25, 5, 25, 10),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            message,
            style:TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade200,
            ),
            textScaleFactor: 1.25,
            textAlign: TextAlign.center,
          ),
        )
      );
    });
  }
}
