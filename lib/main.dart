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
import 'password.dart';
import 'misc_marker.dart';
import 'responsiveAppBar.dart';
import 'freehand_drawing.dart';
import 'distance_circle_layer.dart';
import 'area_data.dart';
import 'globals.dart';
import 'area_filter_dialog.dart';
import 'mylocation_marker.dart';

//----------------------------------------------------------------------------
// グローバル変数

// 処理中インジケータ
enum ProgressIndicatorState {
  NoIndicate, // 表示されていない
  Showing,    // 表示中
  Stopping,   // 停止中(次のbuildで停止)
}
ProgressIndicatorState _progressIndicatorState = ProgressIndicatorState.NoIndicate;

// 初期化完了
bool _initializingApp = true;
// 初回の Map ビルド
bool _firstMapBuild = true;
// iOS版 Safari の謎クラッシュ対策
double _mapViewWidthRate = 0.5;


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

class _MapViewState extends State<MapView>
  with AfterLayoutMixin<MapView>
{
  // 家アイコン
  late HomeIconWidget homeIconWidget;
  
  // 手書き図へのアクセスキー
  final _freehandDrawingOnMapKey = GlobalKey<FreehandDrawingOnMapState>();

  // GPS位置情報へのアクセス
  late MyLocationMarker _myLocMarker;
  // GPS位置情報が無効か？無効なら、スイッチをONにさせない。
  bool _gpsLocationNotAvailable = false;

  //----------------------------------------------------------------------------
  // 初期化
  @override
  void initState()
  {
    super.initState();

    // 家アイコン作成
    homeIconWidget = HomeIconWidget();

    // その他の初期化
    miscMarkers.initialize();

    // 手書き図の初期化
    freehandDrawing = FreehandDrawing();
    freehandDrawing.setColor(Color.fromARGB(255,0,255,0));

    // データベースからもろもろ読み込んで初期状態をセットアップ
    // 非同期処理。完了したら _initializingApp = false にして再描画が呼ばれる。
    initStateSub();
  }

  // 初期化(読み込み関連)
  Future initStateSub() async
  {
    // メンバーデータをデータベースから取得
    await loadMembersListFromDB();
  
    // メンバーデータからマーカー配列を作成
    createMemberMarkers();

    // 初期状態で開くファイルパスを取得
    String openPath = "/1";
    final queryParams = Uri.base.queryParameters;
    if(queryParams.containsKey("open")){
      openPath = queryParams["open"]!;
      openPath = openPath.replaceAll("~", "/");
    }
    print(">initStateSub() fullURL=${Uri.base.toString()} openPath=${openPath}");

    // ファイルツリーのデータベースを初期化
    await initFileTree();
    // 初期状態で開くファイルの位置までカレントディレクトリを移動
    // 失敗していたら標準ファイル("/1")を開く
    bool res = await moveAbsUIDPathDir(openPath);
    if(!res){
      openPath = "/1";
      await moveAbsUIDPathDir(openPath);
    }
    // タツマデータをデータベースから取得
    await loadTatsumaFromDB();

    // 初期状態のファイルを読み込み
    await openFile(openPath);
    // 編集ロックに設定
    lockEditing = true;

    // 初期化完了(GPSログ除く)
    // 一通りの処理が終わるので、処理中インジケータを消す
    if(_progressIndicatorState == ProgressIndicatorState.Showing){
      Navigator.of(context).pop();
      _progressIndicatorState = ProgressIndicatorState.NoIndicate;
    }

    // パスワードチェック
    bool authenOk = false;
    do{
      authenOk = await askAndCheckPassword(
        context, "パスワード", startAppPasswordHash, startAppPasswordKey);
      // ハズレ
      if(!authenOk){
        showTextBallonMessage("ハズレ...", context: context);
        await Future.delayed(const Duration(seconds: 2));
      }
    }while(!authenOk);

    // 一瞬待って表示開始
    await Future.delayed(new Duration(milliseconds: 500));
    setState((){
      // 初期化完了フラグをセット
      _initializingApp = false;
      _mapViewWidthRate = 1;
    });
  }

  //----------------------------------------------------------------------------
  // ファイルを読み込み、切り替え
  // 指定されたファイルがカレントディレクトリになければエラー
  Future<void> openFile(String fileUIDPath) async
  {
    print("----------------------------------------");
    print(">openFile($fileUIDPath)");
  
    // メンバーマーカーの表示設定が非表示なら、表示に戻す。
    if(!isShowMemberMarker()){
      memberMarkerSizeSelector = 1;
      createMemberMarkers();
    }
    // GPSログの表示設定が非表示なら、表示に戻す。(強制的に表示にする)
    gpsLog.showLogLine = true;
    
    // 「現在のファイル」のパスを設定
    if(!setOpenedFileUIDPath(fileUIDPath)){
      return;
    }

    // GPSログをクリア
    gpsLog.clear();
    // 直前の汎用マーカーを閉じる
    miscMarkers.close();
    // 直前の手書き図を削除
    freehandDrawing.close();
  
    // メンバーの配置データをデータベースから取得
    String name = getOpenedFileName();
    await openMemberSync(fileUIDPath, name);

    // タツマのエリアフィルターを取得(表示/非表示)
    // それに応じてマーカー配列を作成
    await loadAreaFilterFromDB(fileUIDPath);
    updateTatsumaMarkers();

    // GPSログをクリア、デバイスIDと犬の対応を取得
    await gpsLog.loadDeviceID2DogFromDB(fileUIDPath);

    // 汎用マーカーを読み込み(非同期)
    miscMarkers.openSync(fileUIDPath);
  
    // 手書き図を読み込み(非同期)
    freehandDrawing.open(fileUIDPath);
  
    // GPSログを読み込み(非同期)
    final String gpsLogPath = await gpsLog.getReferencePath(fileUIDPath);
    final bool refLink = (gpsLogPath != fileUIDPath);
    gpsLog.downloadFromCloudStorage(gpsLogPath, refLink).then((res) async {
      if(res){
        await gpsLog.loadGPSLogTrimRangeFromDB(fileUIDPath);
        gpsLog.saveDeviceID2DogToDB(fileUIDPath);
      }
      gpsLog.makePolyLines();
      gpsLog.makeDogMarkers();
      gpsLog.redraw();
    });
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
    miscMarkers.releaseSync();
    _myLocMarker.disable();

    super.dispose();
  }

  //----------------------------------------------------------------------------
  // 編集ロック

  // AppBar-Action領域の、編集ロックボタン
  // コールバック内で自分自身のメソッドを呼び出すために、インスタンスをアクセス可能に定義する
  late OnOffIconButton _lockEditingButton;

  void onLockChangeSub(bool lock)
  {
    // ボタン押し込みによるON/OFF切り替えを取り込む
    lockEditing = lock;
    // ON/OFFボタンを再描画(ロック(編集不可)でOFF、ロック解除(編集可)でON)
    _lockEditingButton?.changeState(!lock);
    // マップ上のマーカーのドラッグ許可/禁止を更新
    mainMapDragMarkerPluginOptions.draggable = !lockEditing;
    miscMarkers.getMapLayerOptions().draggable = !lockEditing;
    // これを呼ばないと、変更後にちょっとだけマーカーを動かせてしまう？
    updateMapView();
    // 手書き図に編集ロック変更を通知
    _freehandDrawingOnMapKey.currentState?.setEditLock(lockEditing);
  }

  //----------------------------------------------------------------------------
  // 画面構築
  @override
  Widget build(BuildContext context)
  {
    print(">MapView.build() _initializingApp=${_initializingApp}");

    if(_initializingApp){
      // 初期化中
      return Scaffold(
        appBar: AppBar(
          title: Text("TatsumaO"),
        ),
        body: Container(
          child: Center(
            child: Text("初期化中...", textScaleFactor:2.0),
          ),
        ),
      );
    }else{
      // 初期化完了後
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
  var _responsiveAppBar = ResponsiveAppBar();

  AppBar makeAppBar(BuildContext context)
  {
    // 幅が狭ければ、文字を小さくする
    var screenSize = MediaQuery.of(context).size;
    final bool narrowWidth = (screenSize.width < 640);
  
    // AppBar-Action領域の、編集ロックボタン
    _lockEditingButton = OnOffIconButton(
      icon: const Icon(Icons.edit_square),
      iconOff: const Icon(Icons.edit_square),
      onSwitch: !lockEditing,
      onChange: (onoff) {
        // スイッチがONでロック解除(編集可)、OFFでロック(編集不可)
        lockEditingFunc(context, !onoff);
      },
    );

    // 右端の機能ボタン群
    List<Widget> actionsLine = [
      // 編集ロックボタン
      _lockEditingButton,
      // クリップボードへコピーボタン
      IconButton(
        icon: Icon(Icons.content_copy),
        onPressed:() {
          copyAssignToClipboard(context);
        },
      ),
      // ログ関連
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
        icon: const Icon(Icons.visibility),
        onPressed:() {
          areaIconFunc(context);
        },
      ),
    ];

    // 右側のタイトル
    List<Widget> titleLine = [
      // ファイル一覧ボタン
      IconButton(
        icon: Icon(Icons.folder),
        onPressed: () => fileIconFunc(context),
      ),
      // ファイルパス
      // 狭い画面なら文字小さく
      Text(
        getOpenedFilePath(),
        textScaleFactor: (narrowWidth? 0.8: null),
      ),
    ];

    // レスポンシブ対応 AppBar
    return _responsiveAppBar.makeAppBar(
      context,
      titleLine: titleLine,
      actionsLine: actionsLine,
      opacity: 0.4,
      automaticallyImplyLeading: false,
      setState: setState);
  }

  //----------------------------------------------------------------------------
  // ファイルアイコンタップしてファイル一覧画面に遷移
  void fileIconFunc(BuildContext context)
  {
    // アニメーション停止
    gpsLog.stopAnim();
    // BottomSheet を閉じる
    closeBottomSheet();
    // 手書きを無効化
    _freehandDrawingOnMapKey.currentState?.disableDrawing();

    // ファイル一覧画面に遷移して、ファイルの切り替え
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => FilesPage(
        onSelectFile: (uidPath) => onSelectFileToOpen(uidPath),
        onChangeState: (){
          // ファイル変更に至らない程度の変更があった場合には、AppBar を更新
          setState((){});
        },
      ))
    );
  }

  //----------------------------------------------------------------------------
  // ファイルを開く(切り替える)
  Future<void> onSelectFileToOpen(String uidPath) async
  {
    // 読み込み処理のうち、完了待を行うものが終わるまではクルクルを表示
    afterFirstLayout(context);
  
    // ファイルを読み込み
    // NOTE: 非同期読み込みの処理は、この後に実行される可能性あり
    await openFile(uidPath);

    // クルクルを消す    
    Navigator.of(context).pop();
    _progressIndicatorState = ProgressIndicatorState.NoIndicate;

    // 編集ロックに設定
    onLockChangeSub(true);

    // 再描画
    setState((){});

    // ファイル名をバルーン表示
    final String path = getOpenedFilePath();
    showTextBallonMessage(path);
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
    showAreaFilterDialog(context,
      title:"表示/非表示設定", showOptions:true, alignLeft:true)
      .then((bool? res)
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
    // ロック解除(編集可)にはパスワードが必要
    bool ok = true;
    if(lock == false){
      bool authenOk = await askAndCheckPassword(context,
        "編集ロックパスワード", lockEditingPasswordHash, lockEditingPasswordKey);
      // ハズレ
      if(!authenOk){
        showTextBallonMessage("ハズレ...");
        return;
      }

      // ロックを解除するときには確認を促す
      ok = await showOkCancelDialog(context,
        title: "編集ロックの解除",
        text: "注意：記録として保存してあるデータは変更しないで下さい。") ?? false;
    }
  
    if(ok){
      // ロック変更時の共通処理
      onLockChangeSub(lock);
    }
  }

  //----------------------------------------------------------------------------
  // メインの地図ビュー構築
  Widget makeAppBody(BuildContext context)
  {
    // 地図コントローラを作成
    // NOTE: これを initState() やグローバル変数での初期化に移動しないこと！
    // NOTE: インスタンスがあっても初回 build 以降でないと使用できず、内部 assert を引き起こすため。
    if(mainMapController == null){
      mainMapController = MapController();
      freehandDrawing.setMapController(mainMapController!);
      // GPS位置情報へのアクセスを初期化
      _myLocMarker = MyLocationMarker(mainMapController!);
    }
    // 距離サークルを作成
    if(distanceCircle == null){
      distanceCircle = DistanceCircleLayerOptions(
        stream: StreamController<void>.broadcast(),
        mapController: mainMapController!);
    }
  
    // マップ上のメンバーマーカーの作成オプション
    // TODO: MapOption への値の代入を、適切な位置に移動したい
    mainMapDragMarkerPluginOptions = MyDragMarkerPluginOptions(
      markers: memberMarkers,
      draggable: !lockEditing,
      visible: isShowMemberMarker(),
    );
    miscMarkers.getMapLayerOptions().draggable = !lockEditing;

    // 家アイコン更新
    HomeIconWidget.update();

    // 最初にロードしたフィルの初期位置にマップの表示位置を移動
    // 初回 build の後でないと mainMapController が使えないので…
    if(_firstMapBuild){
      _firstMapBuild = false;
      WidgetsBinding.instance.addPostFrameCallback((_){
        moveMapToLocationOfMembers();
      });
    }
  
    // iOS版 Safari の謎クラッシュ対策用の、MapView幅制御
    final Size screenSize = MediaQuery.of(context).size;
    final double mapViewWidth = screenSize.width * _mapViewWidthRate;
  
    return Center(
      child: SizedBox(
        width: mapViewWidth,
        height: screenSize.height,
        child: Stack(
          children: [
            // 地図
            FlutterMap(
              mapController: mainMapController,
              options: MapOptions(
                allowPanningOnScrollingParent: false,
                interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                plugins: [
                  DistanceCircleLayerPlugin(),
                  MyDragMarkerPlugin(),
                  MyPolylineLayerPlugin(),
                ],
                center: LatLng(35.309934, 139.076056),  // 丸太の森P
                zoom: 16,
                maxZoom: 18,
                onTap: (TapPosition tapPos, LatLng point) => tapOnMap(context, tapPos),
                // 表示位置の変更に合わせた処理
                onPositionChanged: (MapPosition position, bool hasGesture){
                  _myLocMarker.moveMap(mainMapController!, position);
                }                
              ),
              nonRotatedLayers: [
                // 高さ陰影図
                TileLayerOptions(
                  urlTemplate: "https://cyberjapandata.gsi.go.jp/xyz/hillshademap/{z}/{x}/{y}.png",
                  maxNativeZoom: 16,
                ),
                // 標準地図
                TileLayerOptions(
                  urlTemplate: "https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png",
                  opacity: 0.64
                ),
                // ポリゴン(禁猟区)
                PolygonLayerOptions(
                  polygons: areaData.makePolygons(),
                  polygonCulling: true,
                ),
                // 距離同心円
                distanceCircle!,
                // GPSログのライン
                MyPolylineLayerOptions(
                  polylines: gpsLog.makePolyLines(),
                  rebuild: gpsLog.reDrawStream,
                  polylineCulling: false,
                ),
                // 手書き図形レイヤー
                // NOTE: 各マーカーより上に持っていくと、図形があるときにドラッグできなくなる！？
                freehandDrawing.getFiguresLayerOptions(),
                // タツママーカー
                MarkerLayerOptions(
                  markers: tatsumaMarkers,
                  // NOTE: usePxCache=trueだと、非表示グレーマーカーで並び順が変わったときにバグる
                  usePxCache: false,
                ),
                // GPS現在位置のライン描画
                _myLocMarker.getLineLayerOptions(),
                // メンバーマーカー
                mainMapDragMarkerPluginOptions,
                // その他のマーカー
                miscMarkers.getMapLayerOptions(),
                // GPSログの犬マーカー
                MarkerLayerOptions(
                  markers: gpsLog.makeDogMarkers(),
                  rebuild: gpsLog.reDrawStream,
                  // NOTE: usePxCache=trueだと、ストリーム経由の再描画で位置が変わらない
                  usePxCache: false,
                ),
                // 手書きの今引いている最中のライン
                freehandDrawing.getCurrentStrokeLayerOptions(),
                // GPSの現在位置
                _myLocMarker.getLayerOptions(),
              ],
            ),

            // 家アイコン
            homeIconWidget,

            // 手書き図
            FreehandDrawingOnMap(key:_freehandDrawingOnMapKey),

            // GPSスイッチ
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                margin: const EdgeInsets.fromLTRB(5, 0, 0, 15),
                child: makeGpsLocationSW(context),
              ),
            ),
          ]
        ),
      ),
    );
  }

  Widget makeGpsLocationSW(BuildContext context)
  {
    return OnOffIconButton2(
      size: 55,
      icon: Icon(Icons.gps_fixed, size:40, color:Colors.orange.shade900),
      backgroundColor: Colors.white.withOpacity(0.70),
      offIcon: Icon(Icons.gps_off, size:40, color:Colors.grey.shade700),
      offBackgroundColor: Colors.grey.withOpacity(0.70),
      isOn: _myLocMarker.enabled,
      onChange: (bool onoff, OnOffIconButton2State state) {
        // GPS位置情報が無効なら、以降スイッチをONにさせない。
        if(_gpsLocationNotAvailable){
          return false;
        }
        if(onoff){
          _myLocMarker.enable(context).then((res){
            // GPSの初期化に失敗したら、スイッチをONにさせない。
            if(!res){
              state.changeState(false);
              _gpsLocationNotAvailable = true;
            }
          });
        }else{
          _myLocMarker.disable();
        }
        return onoff;
      },
    );
  }
}

//---------------------------------------------------------------------------
// マップをタップ
void tapOnMap(BuildContext context, TapPosition tapPos)
{
  // タツマをタップしたら、タツマ編集ダイアログ
  // 編集ロック中はできない
  if(lockEditing) return;
  int? index = searchTatsumaByScreenPos(
    mainMapController!, tapPos.global.dx, tapPos.global.dy);
  if(index != null){
    var tatsuma = tatsumas[index];
    showChangeTatsumaDialog(context, tatsuma).then((res){
      if(res != null){
        if(res.containsKey("delete")){
          // 削除
          deleteTatsuma(index);
          updateTatsumaMarkers();
          // データベース全体を更新
          saveAllTatsumasToDB();
        }else{
          // タツマデータに変更を反映
          tatsuma.name     = res["name"];
          tatsuma.visible  = res["visible"];
          tatsuma.areaBits = res["areaBits"];
          tatsuma.auxPoint = res["auxPoint"];
          updateTatsumaMarkers();
          // データベースに同期
          updateTatsumaToDB(index);
        }
        updateMapView();
      }
    });
  }        
}
