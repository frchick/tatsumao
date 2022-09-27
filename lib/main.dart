import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import 'dart:async';
import 'package:flutter/services.dart';

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
    widget.appState.syncMemberState(index);
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
        style: _appIconButtonStyle,
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
                      draggableIcons.add(Align(
                        alignment: Alignment(0.0, -0.8),
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
                  return Container(
                    height: menuHeight,
                    color: Colors.brown.shade100,
                    child: Scrollbar(
                      thumbVisibility: true,
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
  // ポップアップメッセージ
  late MyFadeOut popupMessage;
  
  // ウィンドウサイズを参照するためのキー
  GlobalKey scaffoldKey = GlobalKey();

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
          onDragStart: onDragStartFunc,
          onDragUpdate: onDragUpdateFunc,
          onDragEnd: onDragEndFunc,
          visible: member.attended,
        )
      );
      memberIndex++;
    });

    // ポップアップメッセージ
    popupMessage = MyFadeOut(child: Text(""));

    // メンバーデータの初期値をデータベースから取得
    initMemberSync().then((res){
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

              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                // クリップボードへコピーボタン
                  ElevatedButton(
                    child: Icon(Icons.content_copy, size: 50),
                    style: _appIconButtonStyle,
                    onPressed: () {
                      copyAssignToClipboard();
                      showPopupMessage("配置をクリップボードへコピー");
                    },
                  ),
                  // ファイル一覧ボタン
                  ElevatedButton(
                    child: Icon(Icons.folder, size: 50),
                    style: _appIconButtonStyle,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => FilesPage())
                      );
                    }
                  )
                ]
              ),

              // ポップアップメッセージ
              Align(
                alignment: Alignment(0.0, 0.0),
                child: popupMessage
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
        showPopupMessage(msg);
        
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
  // メンバーデータの同期(firebase realtime database)
  FirebaseDatabase database = FirebaseDatabase.instance;

  // このアプリケーションインスタンスを一意に識別するキー
  final String appInstKey = UniqueKey().toString();

  // 初期化
  Future initMemberSync() async
  {
    final DatabaseReference ref = database.ref("members");
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
      final DatabaseReference ref = database.ref("members/" + id);
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

    DatabaseReference memberRef = database.ref("members/" + id);
    memberRef.update({
      "sender_id": appInstKey,
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
      (sender_id != appInstKey) &&
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
        String msg = members[index].name + " は家に帰った";
        showPopupMessage(msg);
      }
      else if(joinToTeam){
        String msg = members[index].name + " が参加した";
        showPopupMessage(msg);
      }
    }
    else{
      print("onChangeMemberState(index:${index}) -> myself");
    }
  }

  //---------------------------------------------------------------------------
  // ポップアップメッセージの表示
  void showPopupMessage(String message)
  {
    // ポップアップメッセージ
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

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// ファイル一覧画面
class FilesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            children: [
              Text('Sub1'),
              ElevatedButton(
                child: Icon(Icons.arrow_back, size: 50),
                onPressed: () {
                  Navigator.pop(context);
                }
              ),
            ]
          ),
        ),
      ),
    );
  }
}
