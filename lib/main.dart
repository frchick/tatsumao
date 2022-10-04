import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:xml/xml.dart';
import 'firebase_options.dart';
import 'mydragmarker.dart';
import 'mydrag_target.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'file_tree.dart';
import 'text_ballon_widget.dart';

//----------------------------------------------------------------------------
// グローバル変数

// アイコンボタン共通のスタイル
final ButtonStyle _appIconButtonStyle = ElevatedButton.styleFrom(
  foregroundColor: Colors.orange.shade900,
  backgroundColor: Colors.transparent,
  shadowColor: Colors.transparent,
  fixedSize: Size(80,80),
);

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// タツマデータ
class TatsumaData {
  TatsumaData(
    this.pos,
    this.name,
    this.visible,
  );

  // 座標
  LatLng pos;
  // 名前
  String name;
  // 表示/非表示
  bool visible;
}

// タツマの適当な初期データ。
List<TatsumaData> tatsumas = [
  TatsumaData(LatLng(35.306227, 139.049396), "岩清水索道", true),
  TatsumaData(LatLng(35.307217, 139.051598), "岩清水中", true),
  TatsumaData(LatLng(35.306809, 139.052676), "岩清水下", true),
  TatsumaData(LatLng(35.306282, 139.047802), "岩清水", true),
  TatsumaData(LatLng(35.305798, 139.054232), "赤エル", true),
  TatsumaData(LatLng(35.30636, 139.05427), "裏赤エル", true),
  TatsumaData(LatLng(35.305804, 139.055972), "ストッパー", true),
  TatsumaData(LatLng(35.304213, 139.046478), "新トナカイ", true),
  TatsumaData(LatLng(35.305561, 139.045259), "トナカイ", true),
  TatsumaData(LatLng(35.302601, 139.04473), "ムロ岩の先", true),
  TatsumaData(LatLng(35.302488, 139.044131), "ムロ岩", true),
  TatsumaData(LatLng(35.301932, 139.043382), "スター", true),
  TatsumaData(LatLng(35.301166, 139.043601), "アメリカ", true),
  TatsumaData(LatLng(35.300012, 139.044023), "太平洋", true),
  TatsumaData(LatLng(35.30026, 139.046538), "メキシコ", true),
  TatsumaData(LatLng(35.29942, 139.04639), "沢の上", true),
];

// タツマのマーカー配列
List<Marker> tatsumaMarkers = [];

// 座標からタツマデータを参照
TatsumaData? searchTatsumaByPoint(LatLng point)
{
  // 同じ座標のタツマを探して返す。
  // 誤差0.0001度(約1[m])での一致判定。
  const double th = (0.0001 * 0.0001) + (0.0001 * 0.0001);
  TatsumaData? res = null;
  tatsumas.forEach((tatsuma){
    final double dx = point.latitude - tatsuma.pos.latitude;
    final double dy = point.longitude - tatsuma.pos.longitude;
    final double d = (dx * dx) + (dy * dy);
    if(d < th){
      res = tatsuma;
      return;
    }
  });

  return res;
}

// タツマをデータベースへ保存
void saveTatsumaToDB()
{
  // タツマデータをJSONの配列に変換
  List<Map<String, dynamic>> data = [];
  tatsumas.forEach((tatsuma){
    data.add({
      "name": tatsuma.name,
      "latitude": tatsuma.pos.latitude,
      "longitude": tatsuma.pos.longitude,
      "visible": tatsuma.visible,
    });
  });

  // データベースに上書き保存
  final DatabaseReference ref = database.ref("tatsumas");
  try { ref.set(data); } catch(e) {}
}

// データベースからタツマを読み込み
Future loadTatsumaFromDB() async
{
  // データベースから読み込み
  // List<TatsumaData> を配列として記録してある。
  final DatabaseReference ref = database.ref("tatsumas");
  final DataSnapshot snapshot = await ref.get();
  if(!snapshot.exists) return;
  List<dynamic> data;
  try {
    data = snapshot.value as List<dynamic>;
  }catch(e){
    return;
  }

  // タツマデータを更新
  tatsumas.clear();
  data.forEach((d){
    Map<String, dynamic> t;
    try {
      t = d as Map<String, dynamic>;
    }catch(e){
      return;
    }
    tatsumas.add(TatsumaData(
      /*pos:*/     LatLng(t["latitude"] as double, t["longitude"] as double),
      /*name:*/    t["name"] as String,
      /*visible:*/ t["visible"] as bool));
  });
}

// GPXファイルからタツマを読み込む
Future readTatsumaFromGPX() async
{
  // .pgx ファイルを選択して開く
  final XTypeGroup typeGroup = XTypeGroup(
	  label: 'gpx',
	  extensions: ['gpx'],
  );
  final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return;

  // XMLパース
  final String fileContent = await file.readAsString();
  final XmlDocument gpxDoc = XmlDocument.parse(fileContent);

  final XmlElement? gpx = gpxDoc.getElement("gpx");
  if(gpx == null) return;

  // タツマを読み取り
  List<TatsumaData> newTatsumas = [];
  final Iterable<XmlElement> wpts = gpx.findAllElements("wpt");
  wpts.forEach((wpt){
    final String? lat = wpt.getAttribute("lat");
    final String? lon = wpt.getAttribute("lon");
    final XmlElement? name = wpt.getElement("name");
    if((lat != null) && (lon != null) && (name != null)){
      newTatsumas.add(TatsumaData(
        LatLng(double.parse(lat), double.parse(lon)),
        name.text,
        true));
    }
  });

  // タツマデータをマージ
  mergeTatsumas(newTatsumas);

  // タツマをデータベースへ保存
  saveTatsumaToDB();
}

// タツマデータをマージ
void mergeTatsumas(List<TatsumaData> newTatsumas)
{
  // 同じ座標のタツマは上書きしない。
  // 新しい座標のタツマのみを取り込む。
  final int numTatsumas = tatsumas.length;
  newTatsumas.forEach((newTatsuma){
    bool existed = false;
    for(int i = 0; i < numTatsumas; i++){
      if(newTatsuma.pos == tatsumas[i].pos){
        existed = true;
        break;
      }
    }
    if(!existed){
      tatsumas.add(newTatsuma);
    }
  });
}

// タツママーカーを更新
void updateTatsumaMarkers()
{
  // タツマデータからマーカー配列を作成
  tatsumaMarkers.clear();
  tatsumas.forEach((element) {
    if(element.visible){
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
    }
  });
}

//----------------------------------------------------------------------------
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
  Member(name:"長さん", iconPath:"assets/member_icon/012.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"望月さん", iconPath:"assets/member_icon/013.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"青池さん", iconPath:"assets/member_icon/014.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"田野倉さん", iconPath:"assets/member_icon/015.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"諸さん", iconPath:"assets/member_icon/016.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"ばったちゃん", iconPath:"assets/member_icon/017.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"あいちゃん", iconPath:"assets/member_icon/018.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"安達さん", iconPath:"assets/member_icon/019.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"友爺", iconPath:"assets/member_icon/020.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"矢崎さん", iconPath:"assets/member_icon/021.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"秋田さん", iconPath:"assets/member_icon/022.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"やまP", iconPath:"assets/member_icon/023.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"梅澤さん", iconPath:"assets/member_icon/024.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"マッスー", iconPath:"assets/member_icon/025.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"福島さん", iconPath:"assets/member_icon/026.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"池田さん", iconPath:"assets/member_icon/027.png", pos:LatLng(35.302880, 139.05500)),
  Member(name:"山口さん", iconPath:"assets/member_icon/028.png", pos:LatLng(35.302880, 139.05500)),

  Member(name:"娘っち", iconPath:"assets/member_icon/001.png", pos:LatLng(35.302880, 139.05200)),
  Member(name:"りんたろー", iconPath:"assets/member_icon/003.png", pos:LatLng(35.302880, 139.05200)),
];

// メンバーのマーカー配列
// 出動していないメンバー分もすべて作成。表示/非表示を設定しておく。
List<MyDragMarker> memberMarkers = [];

//---------------------------------------------------------------------------
// メンバーデータの同期(firebase realtime database)
FirebaseDatabase database = FirebaseDatabase.instance;

// このアプリケーションインスタンスを一意に識別するキー
final String _appInstKey = UniqueKey().toString();

// メンバーのアサインデータへのパス
String _assignPath = "";

// 初期化
Future initMemberSync(String path) async
{
  print(">initMemberSync($path)");

  // 配置データのパス
  _assignPath = "assign" + path;
  final DatabaseReference ref = database.ref(_assignPath);
  final DataSnapshot snapshot = await ref.get();
  for(int index = 0; index < members.length; index++)
  {
    Member member = members[index];
    final String id = index.toString().padLeft(3, '0');

    if (snapshot.hasChild(id)) {
      // メンバーデータがデータベースにあれば、初期値として取得(直前の状態)
      member.attended = snapshot.child(id + "/attended").value as bool;
      member.pos = LatLng(
        snapshot.child(id + "/latitude").value as double,
        snapshot.child(id + "/longitude").value as double);
      // 地図上に表示されているメンバーマーカーの情報も変更
      memberMarkers[index].visible = member.attended;
      memberMarkers[index].point = member.pos;
    } else {
      // データベースにメンバーデータがなければ作成
      syncMemberState(index);
    }    
  }

  // 他の利用者からの変更通知を登録
  for(int index = 0; index < members.length; index++){
    final String id = index.toString().padLeft(3, '0');
    final DatabaseReference ref = database.ref(_assignPath + "/" + id);
    ref.onValue.listen((DatabaseEvent event){
      onChangeMemberState(index, event);
    });
  }
}

// メンバーマーカーの移動を他のユーザーへ同期
void syncMemberState(final int index) async
{
  final Member member = members[index];
  final String id = index.toString().padLeft(3, '0');

  DatabaseReference memberRef = database.ref(_assignPath + "/" + id);
  memberRef.update({
    "sender_id": _appInstKey,
    "attended": member.attended,
    "latitude": member.pos.latitude,
    "longitude": member.pos.longitude
  });
}

// 他の利用者からの同期通知による変更
void onChangeMemberState(final int index, DatabaseEvent event)
{
  final DataSnapshot snapshot = event.snapshot;

  // 自分が送った変更には(当然)反応しない。送信者IDと自分のIDを比較する。
  final String sender_id = snapshot.child("sender_id").value as String;
  final bool fromOther =
    (sender_id != _appInstKey) &&
    (event.type == DatabaseEventType.value);
  if(fromOther){
    print("onChangeMemberState(index:${index}) -> from other");
    // メンバーデータとマーカーのパラメータを、データベースの値に更新
    Member member = members[index];
    final bool attended = snapshot.child("attended").value as bool;
    final bool returnToHome = (member.attended && !attended);
    final bool joinToTeam = (!member.attended && attended);
    member.attended = attended;
    member.pos = LatLng(
      snapshot.child("latitude").value as double,
      snapshot.child("longitude").value as double);
    MyDragMarker memberMarker = memberMarkers[index];
    memberMarker.visible = member.attended;
    memberMarker.point = member.pos;

    // マーカーの再描画
    updateMapView();

    // 家に帰った/参加したポップアップメッセージ
    if(returnToHome){
      final String msg = members[index].name + " は家に帰った";
      showTextBallonMessage(msg);
    }
    else if(joinToTeam){
      final String msg = members[index].name + " が参加した";
      showTextBallonMessage(msg);
    }
  }
  else{
    print("onChangeMemberState(index:${index}) -> myself");
  }
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 地図
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
}

// 地図上のマーカーにスナップ
LatLng snapToTatsuma(LatLng point)
{
  // 画面座標に変換してマーカーとの距離を判定
  // マーカーサイズが16x16である前提
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
//----------------------------------------------------------------------------
// 家ボタン＆メンバー一覧メニュー
class HomeButtonWidget extends StatefulWidget
{
  HomeButtonWidget({
    super.key,
    required this.appState,
  });

  // アプリケーションインスタンスへの参照
  _MapViewState appState;

  @override
  State<HomeButtonWidget> createState() => _HomeButtonWidgetState();
}

class _HomeButtonWidgetState extends State<HomeButtonWidget>
{
  late StateSetter _setModalState;

  // メンバーメニュー領域の高さ
  static const double menuHeight = 120;

  // メンバー一覧メニューからドラッグして出動！
  void onDragEndFunc(MyDraggableDetails details)
  {
    print("Draggable.onDragEnd: wasAccepted: ${details.wasAccepted}, velocity: ${details.velocity}, offset: ${details.offset}, data: ${details.data}");

    // メンバー一覧メニューの外にドラッグされていなければ何もしない。
    // ドラッグ座標はマーカー左上なので、下矢印の位置にオフセットする。
    var px = details.offset.dx + 32;
    var py = details.offset.dy + 72;
    final double screenHeight = widget.appState.getScreenHeight();
    if((screenHeight - menuHeight) < py) return;
  
    // ドラッグ座標からマーカーの緯度経度を計算
    LatLng? point = mainMapController.pointToLatLng(CustomPoint(px, py));
    if(point == null) return;

    // タツママーカーにスナップ
    point = snapToTatsuma(point);

    // メニュー領域の再描画
    final int index = details.data;
    if(_setModalState != null){
      _setModalState((){
        // データとマップ上マーカーを出動/表示状態に
        members[index].attended = true;
        memberMarkers[index].visible = true;
        if(point != null){
          members[index].pos = point;
          memberMarkers[index].point = point;
        }
      });
    }

    // 地図上のマーカーの再描画
    updateMapView();

    // データベースに変更を通知
    syncMemberState(index);
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
      alignment: const Alignment(1.0, 1.0),
      // 家アイコンとそのスタイル
      child: ElevatedButton(
        child: const Icon(Icons.home, size: 50),
        style: _appIconButtonStyle,

        // 家ボタンタップでメンバー一覧メニューを開く
        onPressed: ()
        {
          // メンバー一覧メニューを開く
          showModalBottomSheet<void>(
            context: context,
            builder: (BuildContext context)
            {
              return StatefulBuilder(
                builder: (context, StateSetter setModalState)
                {
                  _setModalState = setModalState;

                  // 出動していないメンバーのアイコンを並べる
                  // NOTE: メンバーをドラッグで地図に配置した際、この StatefulBuilder.builder() で
                  // NOTE: 再描画を行う。そのためアイコンリストの構築はココに実装する必要がある。
                  List<Widget> draggableIcons = [];
                  int index = 0;
                  members.forEach((member)
                  {
                    if(!member.attended){
                      draggableIcons.add(Align(
                        alignment: const Alignment(0.0, -0.8),
                        child: MyDraggable<int>(
                          data: index,
                          child: member.icon0,
                          feedback: member.icon0,
                          childWhenDragging: Container(
                            width: 64,
                            height: 72,
                          ),
                          onDragEnd: onDragEndFunc,
                        )
                      ));
                    }
                    index++;
                  });
                  // 高さ120ドット、横スクロールのリストビュー
                  final ScrollController controller = ScrollController();
                  return Container(
                    height: menuHeight,
                    color: Colors.brown.shade100,
                    child: Scrollbar(
                      thumbVisibility: true,
                      controller: controller,
                      child: ListView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        children: draggableIcons,
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
//----------------------------------------------------------------------------
// アプリケーション

// PC WEB環境で、マウスドラッグによるWidgetのスクロールを有効にするおまじない。
class MyCustomScrollBehavior extends MaterialScrollBehavior {
  // Override behavior methods and getters like dragDevices
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

void main() async
{
  // Firebase を初期化
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,    
  );

  // 地図コントローラを作成
  mainMapController = MapController();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: MyCustomScrollBehavior(),
      title: 'TatsumaO',
      home: MapView(),
    );
  }
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 地図画面
class MapView extends StatefulWidget {
  @override
  _MapViewState createState() => _MapViewState();
}

class _MapViewState extends State<MapView>
{
  // ウィンドウサイズを参照するためのキー
  GlobalKey scaffoldKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    // データベースからタツマを読み込み
    loadTatsumaFromDB().then((_)
    {
      // タツマデータからマーカー配列を作成
      setState((){
        updateTatsumaMarkers();
      });
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
          onDragStart: onDragStartFunc,
          onDragUpdate: onDragUpdateFunc,
          onDragEnd: onDragEndFunc,
          visible: member.attended,
        )
      );
      memberIndex++;
    });

    // ファイルツリーのデータベースを初期化
    initFileTree();

    // メンバーデータの初期値をデータベースから取得
    initMemberSync("/default_data").then((res){
      setState((){});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              HomeButtonWidget(appState:this),

              // 機能ボタン
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // タツマの読み込み
                  ElevatedButton(
                    child: Icon(Icons.map, size: 50),
                    style: _appIconButtonStyle,
                    onPressed: () async {
                      await readTatsumaFromGPX();
                      // タツマデータからマーカー配列を作成
                      setState((){
                        updateTatsumaMarkers();
                      });
                    },
                  ),

                  // クリップボードへコピーボタン
                  ElevatedButton(
                    child: Icon(Icons.content_copy, size: 50),
                    style: _appIconButtonStyle,
                    onPressed: () {
                      copyAssignToClipboard();
                      showTextBallonMessage("配置をクリップボードへコピー");
                    },
                  ),

                  // ファイル一覧ボタン
                  ElevatedButton(
                    child: Icon(Icons.folder, size: 50),
                    style: _appIconButtonStyle,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => FilesPage(
                          onSelectFile: (path){
                            initMemberSync(path);
                            updateMapView();
                          }
                        ))
                      );
                    }
                  )
                ]
              ),

              // ポップアップメッセージ
              Align(
                alignment: Alignment(0.0, 0.0),
                child: TextBallonWidget(),
              ),
            ]
          ),
        ),
      ),
    );
  }

  // 画面サイズの取得(幅)
  double getScreenWidth()
  {
    return (scaffoldKey.currentContext?.size?.width ?? 0.0);
  }
  // 画面サイズの取得(高さ)
  double getScreenHeight()
  {
    return (scaffoldKey.currentContext?.size?.height ?? 0.0);
  }

  //---------------------------------------------------------------------------
  // メンバーマーカーのドラッグ

  // ドラッグ中、マーカー座標をデータベースに同期する実装
  void onDragStartFunc(DragStartDetails details, LatLng point, int index)
  {
    // ドラッグ中の連続同期のためのタイマーをスタート
    Timer.periodic(Duration(milliseconds: 500), (Timer timer){
      _draggingTimer = timer;
      // 直前に同期した座標から動いていたら変更を通知
      if(_lastDraggingPoiny != members[index].pos){
        _lastDraggingPoiny = members[index].pos;
        syncMemberState(index);
      }
    });
  }

  void onDragUpdateFunc(DragUpdateDetails detils, LatLng point, int index)
  {
    // メンバーデータを更新(ドラッグ中の連続同期のために)
    members[index].pos = point;
  }

  // 最後にデータベースに同期したドラッグ座標
  LatLng _lastDraggingPoiny = LatLng(0,0);
  // ドラッグ中の連続同期のためのタイマー
  Timer? _draggingTimer;

  // ドラッグ終了時の処理
  LatLng onDragEndFunc(DragEndDetails details, LatLng point, Offset offset, int index, MapState? mapState)
  {
    // ドラッグ中の連続同期のためのタイマーを停止
    if(_draggingTimer != null){
      _draggingTimer!.cancel();
      _draggingTimer = null;
    }

    // 家アイコンに投げ込まれたら削除する
    // 画面右下にサイズ80x80で表示されている前提
    final bool dropToHome = 
      (0.0 < (offset.dx - (getScreenWidth()  - 80))) &&
      (0.0 < (offset.dy - (getScreenHeight() - 80)));
    if(dropToHome){
        // メンバーマーカーを非表示にして再描画
        memberMarkers[index].visible = false;
        members[index].attended = false;
        updateMapView();

        // データベースに変更を通知
        syncMemberState(index);

        // ポップアップメッセージ
        String msg = members[index].name + " は家に帰った";
        showTextBallonMessage(msg);
        
        return point;
    }

    // タツママーカーにスナップ
    point = snapToTatsuma(point);

    // メンバーデータを更新
    members[index].pos = point;

    // データベースに変更を通知
    syncMemberState(index);

    print("End index $index, point $point");
    return point;
  }

  //---------------------------------------------------------------------------
  // タツマ配置をクリップボートへコピー
  void copyAssignToClipboard() async
  {
    String text = "";
    members.forEach((member){
      if(member.attended){
        TatsumaData? tatsuma = searchTatsumaByPoint(member.pos);
        String line;
        if(tatsuma != null){
          line = member.name + ": " + tatsuma.name;
        }
        else{
          // タツマに立っていない？
          line = member.name + ": ["
            + member.pos.latitude.toStringAsFixed(4) + ","
            + member.pos.longitude.toStringAsFixed(4) + "]";
        }
        text += line + "\n";
      }
    });
    print(text);

    final data = ClipboardData(text: text);
    await Clipboard.setData(data);    
  }
}
