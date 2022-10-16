import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';
import 'package:positioned_tap_detector_2/positioned_tap_detector_2.dart'; // マップのタップ

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:tatsumao/onoff_icon_button.dart';
import 'firebase_options.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';  // フォント
import 'mydragmarker.dart';   // マップ上のマーカー
import 'mydrag_target.dart';  // メンバー一覧のマーカー

import 'file_tree.dart';
import 'text_ballon_widget.dart';
import 'members.dart';
import 'tatsumas.dart';
import 'ok_cancel_dialog.dart';
import 'globals.dart';

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

// 編集がロックされているか
bool lockEditing = false;

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

  //----------------------------------------------------------------------------
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
        onLongPress: (){
          // 編集ロックならサブメニュー出さない
          if(lockEditing) return;
          showPopupMenu(context);
        },
      )
    );
  }

  //----------------------------------------------------------------------------
  // 家アイコン長押しのポップアップメニュー
  void showPopupMenu(BuildContext context)
  {
    final double x = context.size!.width;
    final double y = context.size!.height - 150;
    
    // Note: アイコンカラーは ListTile のデフォルトカラー合わせ
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
    await initMemberSync("/default_data");
    // ファイルに紐づくパラメータをデータベースから取得
    await loadAreaFilterFromDB("/default_data");
    await loadLockEditingFromDB("/default_data", onLockChange:onLockChangeByOther);
    // タツマデータをデータベースから取得
    await loadTatsumaFromDB();
  }

  @override
  void dispose()
  {
    // データベースからの変更通知などをリセット
    // NOTE: これが呼ばれるのはページ全体が終わるときなので不要な気もするが・・・
    // NOTE: VSCode からのリスタートで、以前の通知が残っているような挙動があるので対策。
    // NOTE: でも期待通り動いているかは怪しい・・・
    releaseMemberSync();
    releaseTatsumasSync();
    _lockEditingListener?.cancel();
    _lockEditingListener = null;

    super.dispose();
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
      key: appScaffoldKey,
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
                      await initMemberSync(path);
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
              showAreaFilter(context, showMapDrawOptions:true).then((bool? res){
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
                  onTap: (TapPosition tapPos, LatLng point){
                    // タツマをタップしたら、タツマ編集ダイアログ
                    int? index = searchTatsumaByScreenPos(
                      mainMapController, tapPos.global.dx, tapPos.global.dy);
                    if(index != null){
                      var tatsuma = tatsumas[index];
                      showChangeTatsumaDialog(context, tatsuma).then((res){
                        if(res != null){
                          setState((){
                            tatsuma.name     = res["name"] as String;
                            tatsuma.visible  = res["visible"] as bool;
                            tatsuma.areaBits = res["areaBits"] as int;
                            updateTatsumaMarkers();
                          });
                          // データベースに同期
                          updateTatsumaToDB(index);
                        }
                      });
                    }        
                  },
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
                    markers: tatsumaMarkers,
                    // NOTE: usePxCache=trueだと、非表示グレーマーカーで並び順が変わったときにバグる
                    usePxCache: false,
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
