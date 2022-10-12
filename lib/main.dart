import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:tatsumao/onoff_icon_button.dart';
import 'firebase_options.dart';
import 'dart:async';
import 'package:flutter/services.dart';   // for クリップボード
import 'package:google_fonts/google_fonts.dart';  // フォント

import 'mydragmarker.dart';   // マップ上のマーカー
import 'mydrag_target.dart';  // メンバー一覧のマーカー

import 'file_tree.dart';
import 'text_ballon_widget.dart';
import 'members.dart';
import 'tatsumas.dart';
import 'ok_cancel_dialog.dart';

//----------------------------------------------------------------------------
// グローバル変数

// アイコンボタン共通のスタイル
final ButtonStyle _appIconButtonStyle = ElevatedButton.styleFrom(
  foregroundColor: Colors.orange.shade900,
  backgroundColor: Colors.transparent,
  shadowColor: Colors.transparent,
  fixedSize: Size(80,80),
);

//---------------------------------------------------------------------------
//---------------------------------------------------------------------------
// メンバーデータの同期(firebase realtime database)
FirebaseDatabase database = FirebaseDatabase.instance;

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 地図
late MapController mainMapController;

// 編集がロックされているか
bool lockEditing = false;

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

  // NOTE:
  // MapController._state.rebuildLayers() を呼び出せればスマートに再描画できるが、
  // _state がプライベートメンバーでアクセッサもないので断念。
}

// 地図上のマーカーにスナップ
LatLng snapToTatsuma(LatLng point)
{
  // 画面座標に変換してマーカーとの距離を判定
  // マーカーサイズが16x16である前提
  var pixelPos0 = mainMapController.latLngToScreenPoint(point);
  num minDist = (18.0 * 18.0);
  tatsumas.forEach((tatsuma) {
    // 非表示のタツマは除外
    if(!tatsuma.isVisible()) return;
 
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
// メンバー達の位置へマップを移動する
void moveMapToLocationOfMembers()
{
  // 参加しているメンバーの座標の範囲に、マップをフィットさせる
  List<LatLng> points = [];
  members.forEach((member){
    if(member.attended){
      points.add(member.pos);
    }
  });
  if(points.length == 0) return;
  var bounds = LatLngBounds.fromPoints(points);

  mainMapController.fitBounds(bounds,
    options: FitBoundsOptions(
      padding: EdgeInsets.all(64),
      maxZoom: 16));
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// メンバーマーカーの拡張クラス
class MyDragMarker2 extends MyDragMarker
{
  // 最後にデータベースに同期したドラッグ座標
  static LatLng _lastDraggingPoiny = LatLng(0,0);
  // ドラッグ中の連続同期のためのタイマー
  static Timer? _draggingTimer;

  MyDragMarker2({
    required super.point,
    super.builder,
    super.feedbackBuilder,
    super.width = 64.0,
    super.height = 72.0,
    super.offset = const Offset(0.0, -36.0),
    super.feedbackOffset = const Offset(0.0, -36.0),
    super.onLongPress,
    super.updateMapNearEdge = false, // experimental
    super.nearEdgeRatio = 2.0,
    super.nearEdgeSpeed = 1.0,
    super.rotateMarker = false,
    AnchorPos? anchorPos,
    required super.index,
    super.visible = true,
  })
  {
    super.onDragStart = onDragStartFunc;
    super.onDragUpdate = onDragUpdateFunc;
    super.onDragEnd = onDragEndFunc;
    super.onTap = onTapFunc;
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
  // タップしてメンバー名表示
  void onTapFunc(LatLng point, int index)
  {
    // ポップアップメッセージ
    showTextBallonMessage(members[index].name);
  }
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 家ボタン＆メンバー一覧メニュー
class HomeButtonWidget extends StatefulWidget
{
  HomeButtonWidget({
    super.key,
  });

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
    final double screenHeight = getScreenHeight();
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
                  // NOTE: 退会者はここに表示しないことで、新たにマップ上に配置できないようにする。
                  List<Widget> draggableIcons = [];
                  int index = 0;
                  members.forEach((member)
                  {
                    if(!member.attended && !member.withdrawals){
                      final String name = members[index].name;
                      draggableIcons.add(Align(
                        alignment: const Alignment(0.0, -0.8),
                        child: GestureDetector(
                          child: MyDraggable<int>(
                            data: index,
                            child: member.icon0,
                            feedback: member.icon0,
                            childWhenDragging: Container(
                              width: 64,
                              height: 72,
                            ),
                            onDragEnd: onDragEndFunc,
                            // 編集がロックされいたらドラッグによる出動を抑止
                            maxSimultaneousDrags: (lockEditing? 0: null),
                          ),
                          // タップして名前表示
                          onTap: (){
                            // ポップアップメッセージ
                            showTextBallonMessage(name);
                          }
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

        // 長押しでサブメニュー
        // Note: アイコンカラーは ListTile のデフォルトカラー合わせ
        onLongPress: (){
          // 編集ロックならサブメニュー出さない
          if(lockEditing) return;

          final double x = context.size!.width;
          final double y = context.size!.height - 150;
         
          showMenu(
            context: context,
            position: RelativeRect.fromLTRB(x, y, 0, 0),
            elevation: 8.0,
            items: [
              PopupMenuItem(
                value: 0,
                child: Row(
                  children: [
                    Icon(Icons.hotel, color: Colors.black45),
                    const SizedBox(width: 5),
                    const Text('全員家に帰る'),
                  ]
                ),
                height: (kMinInteractiveDimension * 0.8),
              ),
            ],
          ).then((value) {
            switch(value ?? -1){
            case 0:
              // 全員を家に帰す
              if(goEveryoneHome()){
                updateMapView();
              }
              break;
            }
          });
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
      theme: ThemeData(
        textTheme: GoogleFonts.kosugiMaruTextTheme(Theme.of(context).textTheme)
      ),
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

// ウィンドウサイズを参照するためのキー
GlobalKey _scaffoldKey = GlobalKey();

class _MapViewState extends State<MapView>
{

  @override
  void initState() {
    super.initState();

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
          visible: member.attended,
        )
      );
      memberIndex++;
    });

    // データベースからもろもろ読み込み
    initStateSub().then((_){
      // タツマデータからマーカー配列を作成
      setState((){
        updateTatsumaMarkers();
      });
      // マップの初期位置をメンバーたちの位置へ移動
      moveMapToLocationOfMembers();
    });

  }

  Future initStateSub() async
  {
    // ファイルツリーのデータベースを初期化
    await initFileTree();
    // メンバーデータの初期値をデータベースから取得
    await initMemberSync("/default_data", updateMapView);
    // ファイルに紐づくパラメータをデータベースから取得
    await loadAreaFilterFromDB("/default_data");
    await loadLockEditingFromDB("/default_data", onLockChange:onLockChangeByOther);
    // タツマデータをデータベースから取得
    await loadTatsumaFromDB();
  }

  // AppBar-Action領域の、編集ロックボタン
  // コールバック内で自分自身のメソッドを呼び出すために、インスタンスをアクセス可能に定義する
  late OnOffIconButton _lockEditingButton;

  // 編集ロックを他のユーザーが変更したときの通知ハンドラ
  void onLockChangeByOther(bool lock)
  {
    // ロック変更時の共通処理
    onLockChangeSub(lock);
    // ポップアップメッセージ
    showTextBallonMessage("他のユーザーが" + (lock? "ロック": "ロック解除"));
  }

  void onLockChangeSub(bool lock)
  {
    // ボタン押し込みによるON/OFF切り替えを取り込む
    lockEditing = lock;
    // ON/OFFボタンを再描画
    _lockEditingButton?.changeState(lock);
    // マップ上のマーカーのドラッグ許可/禁止を更新
    _myDragMarkerPluginOptions.draggable = !lockEditing;
    updateMapView();
  }

  // マップ上のメンバーマーカーの作成オプション
  // ドラッグ許可/禁止を後から変更するために、インスタンスをアクセス可能に定義する
  late MyDragMarkerPluginOptions _myDragMarkerPluginOptions;

  // 地図画面
  @override
  Widget build(BuildContext context)
  {
    // AppBar-Action領域の、編集ロックボタン
    _lockEditingButton = OnOffIconButton(
      icon: const Icon(Icons.lock),
      iconOff: const Icon(Icons.lock_open),
      onSwitch: lockEditing,
      onChange: (lock) async {
        // ロックを解除するときには確認を促す
        bool ok = true;
        if(lock == false){
          ok = await showOkCancelDialog(context,
            title: "編集ロックの解除",
            text: "注意：記録として保存してあるデータは変更しないで下さい。") ?? false;
        }
        if(ok){
          // ロック変更時の共通処理
          onLockChangeSub(lock);
          // データベース経由で他のユーザーに同期
          saveLockEditingToDB(getCurrentFilePath());
        }
      },
    );

    // マップ上のメンバーマーカーの作成オプション
    _myDragMarkerPluginOptions = MyDragMarkerPluginOptions(
      markers: memberMarkers,
      draggable: !lockEditing,
    );

    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
     
      // 半透明のアプリケーションバー
      appBar: AppBar(
        // ファイルパスとファイルアイコン
        title: Row(
          children: [
            // ファイル一覧ボタン
            IconButton(
              icon: Icon(Icons.folder),
              onPressed: () {
                // ファイル一覧画面に遷移して、ファイルの切り替え
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => FilesPage(
                    onSelectFile: (path) async {
                      await initMemberSync(path, updateMapView);
                      await loadAreaFilterFromDB(path);
                      await loadLockEditingFromDB(path, onLockChange:onLockChangeByOther);
                      // メンバーの位置へ地図を移動
                      moveMapToLocationOfMembers();
                      // appBarの再描画もしたいので…
                      setState((){
                        updateTatsumaMarkers();
                      });
                    }
                  ))
                );
              }
            ),
            Text(getCurrentFilePath()),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.4),
        elevation: 0,
        
        actions: [
          // 編集ロックボタン
          _lockEditingButton,

          // クリップボードへコピーボタン
          IconButton(
            icon: Icon(Icons.content_copy),
            onPressed: () {
              copyAssignToClipboard();
              showTextBallonMessage("配置をクリップボードへコピー");
            },
          ),

          // タツマの編集と読み込み
          IconButton(
            icon: const Icon(Icons.map),
            onPressed:() async {
              bool? changeTatsuma = await Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (context) => TatsumasPage()
                )
              );
              // タツマに変更があれば…
              if(changeTatsuma ?? false){
                // タツマをデータベースへ保存
                saveTatsumaToDB();
                // タツママーカーを再描画
                setState((){
                  updateTatsumaMarkers();
                });
              }
            },
          ),

          // エリアフィルター
          IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed:() {
              showAreaFilter(context).then((bool? res){
                if(res ?? false){
                  setState((){
                    updateTatsumaMarkers();
                  });
                  // エリアフィルターの設定をデータベースへ保存
                  saveAreaFilterToDB(getCurrentFilePath());
                }
              });
            },
          ),
        ],
      ),
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
                  center: LatLng(35.309934, 139.076056),  // 丸太の森P
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
                  _myDragMarkerPluginOptions,
                ],
                mapController: mainMapController,
              ),

              // 家アイコン
              HomeButtonWidget(),

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

// 画面サイズの取得(幅)
double getScreenWidth()
{
  return (_scaffoldKey.currentContext?.size?.width ?? 0.0);
}
// 画面サイズの取得(高さ)
double getScreenHeight()
{
  return (_scaffoldKey.currentContext?.size?.height ?? 0.0);
}

//---------------------------------------------------------------------------
// 編集ロックの設定をデータベースへ保存
void saveLockEditingToDB(String path)
{
  final String dbPath = "assign" + path + "/lockEditing";
  final DatabaseReference ref = database.ref(dbPath);
  ref.set(lockEditing);
}

//---------------------------------------------------------------------------
// 現在のデータベース変更通知のリスナー
StreamSubscription<DatabaseEvent>? _lockEditingListener;

//---------------------------------------------------------------------------
// 編集ロックの設定をデータベースから読み込み
Future loadLockEditingFromDB(String path, { Function(bool)? onLockChange }) async
{
  final String dbPath = "assign" + path + "/lockEditing";
  final DatabaseReference ref = database.ref(dbPath);
  final DataSnapshot snapshot = await ref.get();
  if(snapshot.exists){
    try {
      lockEditing = snapshot.value as bool;
    } catch(e) {}
  }else{
    // データベースに未登録なら初期値で作成する
    lockEditing = false;
    ref.set(lockEditing);
  }

  // 他のユーザーによるロック変更を受け取るリスナーを設定
  // 直前のリスナーは停止しておく
  _lockEditingListener?.cancel();
  _lockEditingListener = ref.onValue.listen((DatabaseEvent event){
    bool lock = lockEditing;
    try {
      lock = event.snapshot.value as bool;
    }
    catch(e){}

    // 変更があった場合のみコールバックを呼び出す
    if(lockEditing != lock){
      onLockChange?.call(lock);
    }
  });
}
