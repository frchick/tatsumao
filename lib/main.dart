import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'mypolyline_layer.dart'; // マップ上のカスタムポリライン
import 'package:latlong2/latlong.dart';
import 'package:positioned_tap_detector_2/positioned_tap_detector_2.dart'; // マップのタップ
import 'package:after_layout/after_layout.dart';  // 起動直後の build の後の処理

import 'package:flutter_localizations/flutter_localizations.dart';  // カレンダー日本語化

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';  // フォント
import 'mydragmarker.dart';   // マップ上のメンバーマーカー

import 'file_tree.dart';
import 'text_ballon_widget.dart';
import 'members.dart';
import 'tatsumas.dart';
import 'ok_cancel_dialog.dart';
import 'onoff_icon_button.dart';
import 'home_icon.dart';
import 'gps_log.dart';
import 'globals.dart';

//----------------------------------------------------------------------------
// グローバル変数

// 処理中インジケータ
enum ProgressIndicatorState {
  NoIndicate, // 表示されていない
  Showing,    // 表示中
  Stopping,   // 停止中(次のbuildで停止)
}
ProgressIndicatorState _progressIndicatorState = ProgressIndicatorState.NoIndicate;

//---------------------------------------------------------------------------
//---------------------------------------------------------------------------
// メンバーデータの同期(firebase realtime database)
FirebaseDatabase database = FirebaseDatabase.instance;

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

class MyApp extends StatelessWidget
{
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: MyCustomScrollBehavior(),
      debugShowCheckedModeBanner: false,  // appBar の"DEBUG"帯を非表示
      title: 'TatsumaO',
      home: MapView(),
      theme: ThemeData(
        textTheme: GoogleFonts.kosugiMaruTextTheme(Theme.of(context).textTheme)
      ),
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
    );
  }
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// メインの画面
class MapView extends StatefulWidget
{
  @override
  _MapViewState createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with AfterLayoutMixin<MapView>
{
  // 家アイコン
  late HomeIconWidget homeIconWidget;

  //----------------------------------------------------------------------------
  // 初期化
  @override
  void initState() {
    super.initState();

    // メンバーデータからマーカー配列を作成
    // メンバーは組み込みデータなのでデータベースからの読み込みはない
    createMemberMarkers();

    // 家アイコン作成
    homeIconWidget = HomeIconWidget();

    // データベースからもろもろ読み込んで初期状態をセットアップ
    initStateSub();
  }

  // 初期化(読み込み関連)
  Future initStateSub() async
  {
    // 初期状態で開くファイルパスを取得
    final String fullURL = Uri.decodeFull(Uri.base.toString());
    final int pi = fullURL.indexOf("?open=");
    late String openPath;
    if(0 < pi) openPath = fullURL.substring(pi + 6);
    else openPath = "/1";
    openPath = openPath.replaceAll("~", "/");
  
    print(">initStateSub() fullURL=${fullURL} openPath=${openPath}");

    // ファイルツリーのデータベースを初期化
    await initFileTree();
    // 初期状態で開くファイルの位置までカレントディレクトリを移動
    // 失敗していたら標準ファイル("/1")を開く
    bool res = await moveFullPathDir(openPath);
    if(!res){
      openPath = "/1";
      await moveFullPathDir(openPath);
    }
    // タツマデータをデータベースから取得
    await loadTatsumaFromDB();

    // 初期状態のファイルを読み込み
    await openFile(openPath);
    // GPSログを読み込み(遅延処理)
    gpsLog.downloadFromCloudStorage(openPath).then((res) async {
      if(res){
        await gpsLog.loadGPSLogTrimRangeFromDB(openPath);
      }
      gpsLog.makePolyLines();
      gpsLog.makeDogMarkers();
      gpsLog.redraw();
    });
  }

  //----------------------------------------------------------------------------
  // ファイルを読み込み、切り替え
  // 指定されたファイルがカレントディレクトリになければエラー
  Future<void> openFile(String fileUIDPath) async
  {
    // メンバーマーカーが非表示なら、表示に戻す。
    if(!isShowMemberMarker()){
      memberMarkerSizeSelector = 1;
      createMemberMarkers();
    }
    // GPSログが非表示なら、表示に戻す。(強制的に表示にする)
    gpsLog.showLogLine = true;
    
    // ファイルを開く準備
    // もし指定されたファイルが無ければ何もしない
    if(!setOpenedFileUIDPath(fileUIDPath)){
      return;
    }

    // メンバーデータをデータベースから取得
    await initMemberSync(fileUIDPath);
    // メンバーの位置へ地図を移動
    // 直前の地図が表示され続ける時間を短くするために、なるべく早めに
    moveMapToLocationOfMembers();

    // タツマのエリアフィルターを取得(表示/非表示)
    // それに応じてマーカー配列を作成
    await loadAreaFilterFromDB(fileUIDPath);
    updateTatsumaMarkers();

    // 編集ロックフラグを取得
    await loadLockEditingFromDB(fileUIDPath, onLockChange:onLockChangeByOther);
  
    // GPSログをクリア
    gpsLog.clear();
  
    // 一通りの処理が終わるので、処理中インジケータを消す
    if(_progressIndicatorState == ProgressIndicatorState.Showing){
      _progressIndicatorState = ProgressIndicatorState.Stopping;
    }
    // 再描画
    setState((){});
}

  //----------------------------------------------------------------------------
  // 終了処理
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

  //----------------------------------------------------------------------------
  // 編集ロック

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
    mainMapDragMarkerPluginOptions.draggable = !lockEditing;
    updateMapView();
  }

  //----------------------------------------------------------------------------
  // 画面構築
  @override
  Widget build(BuildContext context)
  {
    // 処理中インジケータを消す
    if(_progressIndicatorState == ProgressIndicatorState.Stopping){
      Navigator.of(context).pop();
      _progressIndicatorState = ProgressIndicatorState.NoIndicate;
    }

    final AppBar appBar = makeAppBar(context);
    final Widget appBody = makeAppBody(context);

    return Scaffold(
      key: appScaffoldKey,
      extendBodyBehindAppBar: true,
      // アプリケーションバー
      appBar: appBar,
      // メインとなる地図画面
      body: appBody,
    );
  }

  //----------------------------------------------------------------------------
  // 初回の build の後の処理(処理中インジケータの表示)
  @override
  void afterFirstLayout(BuildContext context)
  {
    // 全画面プログレスダイアログ 
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      pageBuilder: (BuildContext context, Animation animation, Animation secondaryAnimation)
      {
        return Center(
          child: CircularProgressIndicator(),
        );
      }
    );
    _progressIndicatorState = ProgressIndicatorState.Showing;
  }

  //----------------------------------------------------------------------------
  // アプリケーションバー構築

  // ファイルパスと機能アイコンが重なっているか判定して、2行構成切り替え
  GlobalKey _filePathKey = GlobalKey();
  GlobalKey _actionButtonKey = GlobalKey();
  bool _appBar2LineLayout = false;

  AppBar makeAppBar(BuildContext context)
  {
    // ウィンドウリサイズで再構築を走らせるためのおまじない
    // 幅が狭ければ、微調整を入れる
    var screenSize = MediaQuery.of(context).size;
    final bool narrowWidth = (screenSize.width < 640);
  
    // AppBar-Action領域の、編集ロックボタン
    _lockEditingButton = OnOffIconButton(
      icon: const Icon(Icons.lock),
      iconOff: const Icon(Icons.lock_open),
      onSwitch: lockEditing,
      onChange: (lock) {
        lockEditingFunc(context, lock);
      },
    );

    // 右端の機能ボタン群
    Widget actions = Padding(
      padding: EdgeInsets.only(top:(_appBar2LineLayout? 30: 0)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // ダミー
          Container(key: _actionButtonKey, width:0, height:1),
          // 編集ロックボタン
          _lockEditingButton,
          // クリップボードへコピーボタン
          IconButton(
            icon: Icon(Icons.content_copy),
            onPressed:() {
              copyAssignToClipboard(context);
            },
          ),
          // GPSログの読み込み
          IconButton(
            icon: const Icon(Icons.timeline),
            onPressed:() {
              showGPSLogPopupMenu(context);
            },
          ),
          // タツマの編集と読み込み
          IconButton(
            icon: const Icon(Icons.map),
            onPressed:() {
              tatsumaIconFunc(context);
            },
          ),
          // エリアフィルター
          IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed:() {
              areaIconFunc(context);
            },
          ),
        ],
      ),
    );

    // 画面横幅が狭い場合は、AppBar上のファイルパスとアクションボタンを二行レイアウトにする
    // いわゆるレスポンシブデザイン！？
    Widget appBarContents = Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // ファイル一覧ボタン
            IconButton(
              icon: Icon(Icons.folder),
              onPressed: () => fileIconFunc(context),
            ),
            // ファイルパス
            Text(
              getOpenedFilePath(),
              key:_filePathKey,
              textScaleFactor: (narrowWidth? 0.8: null),  // 狭い画面なら文字小さく
            ),
          ],
        ),
        // 機能ボタン群
        actions,
      ]
    );
    final double? height = _appBar2LineLayout? 80: null;

    // ファイルパスとアイコンが重なっているか判定して、1行/2行構成を切り替える
    WidgetsBinding.instance.addPostFrameCallback((_){
      if((_filePathKey.currentContext != null) &&
        (_actionButtonKey.currentContext != null)){
        final RenderBox box0 = _filePathKey.currentContext!.findRenderObject() as RenderBox;
        final RenderBox box1 = _actionButtonKey.currentContext!.findRenderObject() as RenderBox;
        final double textRight = box0.localToGlobal(Offset.zero).dx + box0.size.width;
        final double buttonsLeft = box1.localToGlobal(Offset.zero).dx;
        final bool overlap = (buttonsLeft < textRight);
        if(_appBar2LineLayout != overlap){
          setState((){ _appBar2LineLayout = overlap; });
        }
      }
    });

    return AppBar(
      // アプリケーションバーは半透明
      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.4),
      elevation: 0,
      toolbarHeight: height,
      automaticallyImplyLeading: false,
      titleSpacing: (narrowWidth? 0: null), // 狭い画面なら左右パディングなし
      title: appBarContents,
    );
  }

  //----------------------------------------------------------------------------
  // ファイルアイコンタップしてファイル一覧画面に遷移
  void fileIconFunc(BuildContext context)
  {
    // アニメーション停止
    gpsLog.stopAnim();
    // BottomSheet を閉じる
    closeBottomSheet();
    // ファイル一覧画面に遷移して、ファイルの切り替え
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => FilesPage(
        onSelectFile: (uidPath) async {
          // ファイルを読み込み
          await openFile(uidPath);
          // ファイル名をバルーン表示
          String path = getOpenedFilePath();
          showTextBallonMessage(path);
          // GPSログを読み込み(遅延処理)
          gpsLog.downloadFromCloudStorage(uidPath).then((res) async {
            if(res){
              await gpsLog.loadGPSLogTrimRangeFromDB(uidPath);
            }
            gpsLog.makePolyLines();
            gpsLog.makeDogMarkers();
            gpsLog.redraw();
          });
        },
        onChangeState: (){
          // ファイル変更に至らない程度の変更があった場合には、AppBar を更新
          setState((){});
        },
      ))
    );
  }

  //----------------------------------------------------------------------------
  // タツマアイコンタップしてタツマ一覧画面に遷移
  void tatsumaIconFunc(BuildContext context)
  {
    Navigator.of(context).push(
      MaterialPageRoute<bool?>(
        builder: (context) => TatsumasPage()
      )
    ).then((changeTatsuma){
      // タツマに変更があれば…
      if(changeTatsuma ?? false){
        // タツママーカーを再描画
        updateTatsumaMarkers();
        updateMapView();
      }
    });
  }

  //----------------------------------------------------------------------------
  // エリアアイコンタップしてエリアフィルターダイアログに遷移
  void areaIconFunc(BuildContext context)
  {
    showAreaFilter(context, showMapDrawOptions:true).then((bool? res)
    {
      if(res ?? false){
        // タツママーカーを再描画
        updateTatsumaMarkers();
        updateMapView();
        // エリアフィルターの設定をデータベースへ保存
        saveAreaFilterToDB(getOpenedFileUIDPath());
      }
    });
  }

  //----------------------------------------------------------------------------
  // 編集ロックボタンのタップ
  void lockEditingFunc(BuildContext context, bool lock) async
  {
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
      saveLockEditingToDB(getOpenedFileUIDPath());
    }
  }

  //----------------------------------------------------------------------------
  // メインの地図ビュー構築
  Widget makeAppBody(BuildContext context)
  {
    // マップ上のメンバーマーカーの作成オプション
    mainMapDragMarkerPluginOptions = MyDragMarkerPluginOptions(
      markers: memberMarkers,
      draggable: !lockEditing,
      visible: isShowMemberMarker(),
    );
  
    // 家アイコン更新
    HomeIconWidget.update();

    return Center(
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
                  MyPolylineLayerPlugin(),
                ],
                center: LatLng(35.309934, 139.076056),  // 丸太の森P
                zoom: 16,
                maxZoom: 18,
                onTap: (TapPosition tapPos, LatLng point)
                {
                  // タツマをタップしたら、タツマ編集ダイアログ
                  int? index = searchTatsumaByScreenPos(
                    mainMapController, tapPos.global.dx, tapPos.global.dy);
                  if(index != null){
                    var tatsuma = tatsumas[index];
                    showChangeTatsumaDialog(context, tatsuma).then((res){
                      if(res != null){
                        // タツマデータに反映
                        tatsuma.name     = res["name"] as String;
                        tatsuma.visible  = res["visible"] as bool;
                        tatsuma.areaBits = res["areaBits"] as int;
                        updateTatsumaMarkers();
                        // データベースに同期
                        updateTatsumaToDB(index);
                      }
                    });
                  }        
                },
              ),
              nonRotatedLayers: [
                // 高さ陰影図
                TileLayerOptions(
                  urlTemplate: "https://cyberjapandata.gsi.go.jp/xyz/hillshademap/{z}/{x}/{y}.png",
                ),
                // 標準地図
                TileLayerOptions(
                  urlTemplate: "https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png",
                  opacity: 0.64
                ),
                // GPSログのライン
                MyPolylineLayerOptions(
                  polylines: gpsLog.makePolyLines(),
                  rebuild: gpsLog.reDrawStream,
                  polylineCulling: false,
                ),
                // タツママーカー
                MarkerLayerOptions(
                  markers: tatsumaMarkers,
                  // NOTE: usePxCache=trueだと、非表示グレーマーカーで並び順が変わったときにバグる
                  usePxCache: false,
                ),
                // メンバーマーカー
                mainMapDragMarkerPluginOptions,
                // GPSログの犬マーカー
                MarkerLayerOptions(
                  markers: gpsLog.makeDogMarkers(),
                  rebuild: gpsLog.reDrawStream,
                  // NOTE: usePxCache=trueだと、ストリーム経由の再描画で位置が変わらない
                  usePxCache: false,
                ),
              ],
              mapController: mainMapController,
            ),

            // 家アイコン
            homeIconWidget,

            // ポップアップメッセージ
            Align(
              alignment: Alignment(0.0, 0.0),
              child: TextBallonWidget(),
            ),
          ]
        ),
      ),
    );
  }
}

//---------------------------------------------------------------------------
// 編集ロックの設定をデータベースへ保存
void saveLockEditingToDB(String uidPath)
{
  final String dbPath = "assign" + uidPath + "/lockEditing";
  final DatabaseReference ref = database.ref(dbPath);
  ref.set(lockEditing);
}

//---------------------------------------------------------------------------
// 現在のデータベース変更通知のリスナー
StreamSubscription<DatabaseEvent>? _lockEditingListener;

//---------------------------------------------------------------------------
// 編集ロックの設定をデータベースから読み込み
Future loadLockEditingFromDB(String uidPath, { Function(bool)? onLockChange }) async
{
  final String dbPath = "assign" + uidPath + "/lockEditing";
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
