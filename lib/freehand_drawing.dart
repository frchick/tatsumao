import 'dart:async';   // Stream使った再描画、Timer
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';  // DragStartBehavior
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'mypolyline_layer.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// 手書き図の実装
late FreehandDrawing freehandDrawing;

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// 手書き図の実装
class FreehandDrawing
{
  FreehandDrawing({
    required MapController mapController,
    required String appInstKey }) :
    _mapController = mapController,
    _appInstKey = appInstKey
  {
  }

  final MapController _mapController;

  // 図形のリスト
  Map<String, Figure> _figures = {};

  // 今引いているストロークを追加する図形
  // null の場合にはストローク完了時に新しく図形を作成
  Figure? _addStrokeFigure = null;

  // 描画した図形のポリラインの集合
  List<MyPolyline> _polylines = [];
  // 描画した図形の再描画
  var _redrawPolylineStream = StreamController<void>.broadcast();

  // 今引いている最中のストローク
  List<MyPolyline> _currentStroke = []; // 配列になっているが、実際には先頭要素のみ
  List<LatLng>? _currnetStrokeLatLng;
  List<Offset>? _currnetStrokePoints;
  // 今引いている最中のストロークの再描画
  var _redrawStrokeStream = StreamController<void>.broadcast();

  // カラー
  Color _color = Colors.orange.shade700;
  void setColor(Color color){ _color = color; }

  //---------------------------------------------------------------------------
  // FlutterMap のレイヤー(描画した図形)
  MyPolylineLayerOptions getFiguresLayerOptions()
  {
    return MyPolylineLayerOptions(
      polylines: _polylines,
      rebuild: _redrawPolylineStream.stream);
  }

  // FlutterMap のレイヤー(今引いている最中のストローク)
  MyPolylineLayerOptions getCurrentStrokeLayerOptions()
  {
    return MyPolylineLayerOptions(
      polylines: _currentStroke,
      rebuild: _redrawStrokeStream.stream);
  }

  // ストローク開始
  void onStrokeStart(Offset pt)
  {
    if(_currnetStrokeLatLng == null){
      final point = _mapController.pointToLatLng(CustomPoint(pt.dx, pt.dy));
      _currnetStrokePoints = [ pt ];
      _currnetStrokeLatLng = [ point! ];

      // 最後の図形にこのストロークを追加できるか？
      _addStrokeFigure = null;
      for(var figure in _figures.values){
        if(figure.state == FigureState.Open){
          if(figure.tryAddNewStroke()){
            _addStrokeFigure = figure;
            break;
          }
        }
      }
    }
  }

  // ストロークの継続
  void onStrokeUpdate(Offset pt)
  {
    if(_currnetStrokeLatLng != null){
      final point = _mapController.pointToLatLng(CustomPoint(pt.dx, pt.dy));
      _currnetStrokePoints!.add(pt);
      _currnetStrokeLatLng!.add(point!);

      var polyline = MyPolyline(
        points: _currnetStrokeLatLng!,
        color: _color,
        strokeWidth: 4.0,
        shouldRepaint: true);
      
      if(_currentStroke.isEmpty) _currentStroke.add(polyline);
      else _currentStroke[0] = polyline;
      _redrawStrokeStream.sink.add(null);
    }
  }

  // ストロークの完了
  void onStrokeEnd()
  {
    if(_currnetStrokeLatLng != null){
      // リダクションをかける
      List<Offset> pts = reducePolyline(_currnetStrokePoints!);
      //!!!!
      print("The stroke has ${_currnetStrokePoints!.length} -> ${pts.length} points.");

      // LatLng に変換し直してポリラインを作成
      List<LatLng> latlngs = [];
      pts.forEach((pt){
        final latlng = _mapController.pointToLatLng(CustomPoint(pt.dx, pt.dy));
        latlngs.add(latlng!);
      });
      var polyline = MyPolyline(
        points: latlngs,
        color: _color,
        strokeWidth: 4.0,
        shouldRepaint: true);
      _currnetStrokeLatLng = null;
      _currnetStrokePoints = null;

      // 最後の図形に追加するか、新規図形を作成するか
      if(_addStrokeFigure == null){
        var key = UniqueKey().toString();
        _addStrokeFigure = Figure(key:key, parent:this);
        _figures[key] = _addStrokeFigure!;
      }
      _addStrokeFigure!.addStroke(polyline);
      redraw();
    }
    _currentStroke.clear();
    _redrawStrokeStream.sink.add(null);
  }

  // 図形を削除
  void removeFigure(Figure figure)
  {
    final int N = _figures.length;

    _figures.remove(figure.key);
    if(_addStrokeFigure == figure){
      _addStrokeFigure = null;
    }
    //!!!!
    print(">Remove Figure!!!! ${N} -> ${_figures.length}");
  }

  // 再描画
  void redraw()
  {
    // 現在有効な全ての図形のポリラインを集めて再描画
    _polylines.clear();
    for(var figure in _figures.values)
    {
      _polylines.addAll(figure.polylines);
    }
    _redrawPolylineStream.sink.add(null);
  }

  //---------------------------------------------------------------------------
  // 他ユーザーとのリアルタイム同期
  DatabaseReference? _databaseRef;
  DatabaseReference? get databaseRef => _databaseRef;

  // 追加イベント
  StreamSubscription<DatabaseEvent>? _addListener;
  // 削除イベント
  StreamSubscription<DatabaseEvent>? _removeListener;

  // このアプリケーションインスタンスを一意に識別するキー
  // 手書きの変更通知が、自分自身によるものか、他のユーザーからかを識別
  late String _appInstKey;
  String get appInstKey => _appInstKey;

  //---------------------------------------------------------------------------
  // 配置ファイルを開く
  void open(String uidPath)
  {
    // データベースの参照ポイント
    final String dbPath = "assign" + uidPath + "/freehand_drawing";
    _databaseRef = FirebaseDatabase.instance.ref(dbPath);

    // 追加削除イベント
    _addListener?.cancel();
    _addListener = _databaseRef!.onChildAdded.listen((event){
      _onStrokeAdded(event);
    });
    _removeListener?.cancel();
    _removeListener = _databaseRef!.onChildRemoved.listen((event){
      _onStrokeRemoved(event);
    });
  }

  // 配置ファイルを閉じる
  void close()
  {
    // 追加削除イベントを閉じる
    _addListener?.cancel();
    _addListener = null;
    _removeListener?.cancel();
    _removeListener = null;
    // データベースへの参照をクリア
    _databaseRef = null;

    // まだ削除されていない図形をクリアして削除
    _figures.forEach((key, figure){
      figure.clear();
    });
    _figures.clear();
    _addStrokeFigure = null;
    _polylines.clear();

    // 今引いている最中のストロークをクリア
    _currentStroke.clear();
    _currnetStrokeLatLng = null;
    _currnetStrokePoints = null;
  }

  // 追加イベント
  void _onStrokeAdded(DatabaseEvent event)
  {
    //!!!!
    print(">FreehandDrawing._onStrokeAdded()");

    try {
      Map<String, dynamic> data = event.snapshot.value as Map<String, dynamic>;
      
      // 作成が古すぎるデータが来たら、それは多分異常終了で残っているゴミなので削除する
      final createdTime = DateTime.fromMillisecondsSinceEpoch(data["time"] as int);
      final Duration d = DateTime.now().difference(createdTime);
      if(10 < d.inSeconds){
        print(">FreehandDrawing._onStrokeAdded() Remove an old garbage data.");
        event.snapshot.ref.remove();
        return;
      }

      // 自分自身が追加した場合は無視
      if(data["senderId"] == _appInstKey){
        print(">FreehandDrawing._onStrokeAdded() from myself.");
        return;
      }

      // ポリラインを作成して登録
      MyPolyline? polyline = Figure.makePolyline(data);
      if(polyline == null){
        return;
      }

      // 先行するストロークで作成された図形か？
      // そうでなければ新規で作成する
      final String key = data["key"] as String;
      late Figure figure;
      if(_figures.containsKey(key)){
        figure = _figures[key]!;
      }else{
        figure = Figure(key:key, parent:this, remote:true);
        _figures[key] = figure;
      }
      figure.addStroke(polyline);

      // 再描画
      redraw();
      //!!!!
      print(">FreehandDrawing._onStrokeAdded() key:${key}");
    } catch(e) {
      //!!!!
      print(">FreehandDrawing._onStrokeAdded() failed!!!!");
    }
  }

  // 削除イベント
  void _onStrokeRemoved(DatabaseEvent event)
  {
    //!!!!
    print(">FreehandDrawing._onStrokeRemoved()");

    try {
      Map<String, dynamic> data = event.snapshot.value as Map<String, dynamic>;
      
      // 自分自身が追加した場合は無視
      if(data["senderId"] == _appInstKey){
        print(">FreehandDrawing._onStrokeRemoved() from myself.");
        return;
      }

      // フェードアウトさせて消す
      final String key = data["key"] as String;
      final bool contains = _figures.containsKey(key);
      if(contains){
        _figures[key]!.removeByRemote();
      }
      //!!!!
      print(">FreehandDrawing._onStrokeRemoved() key:${key} contains:${contains?'YES':'NO'}");
    } catch(e) {
      //!!!!
      print(">FreehandDrawing._onStrokeRemoved() failed!!!!");
    }
  }
}

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// 手書き図に含まれる、複数のストロークにより構成される、一塊の図形
class Figure
{
  Figure({
    required String key,
    required FreehandDrawing parent,
    bool remote = false }) :
    _key = key,
    _freehandDrawing = parent
  {
    //!!!!
    print(">new Figure(${key}, remote:${remote})");

    // 他のユーザーが作成したストロークの図形の場合
    if(remote){
      _state = FigureState.RemoteOpen;
    }
  }

  // 親
  late FreehandDrawing _freehandDrawing;

  // 状態
  FigureState _state = FigureState.Open;
  FigureState get state => _state;

  // 複数ユーザー間で図形を識別するキー
  final String _key;
  String get key => _key;

  // この図形に含まれるストローク
  List<MyPolyline> _polylines = [];
  List<MyPolyline> get polylines => _polylines;
  // この図形に含まれるストロークをデータベースに書き込んだ参照
  List<DatabaseReference> _polylineRefs = [];

  // 一塊の図形として連続したストロークと判定する時間のタイマー
  Timer? _openTimer;
  // この図形を表示する期間のタイマー
  Timer? _showTimer;
  // フェードアウトアニメーションのタイマー
  Timer? _fadeAnimTimer;
  // フェードアウトの透明度(0 - 255)
  int _opacity = 0;

  // 一塊の図形として連続したストロークと判定する時間
  var _openDuration = const Duration(milliseconds: 1500);
  // 図形を表示する時間
  var _showDuration = const Duration(milliseconds: 1500);

  // 次のストロークを追加可能か試す。
  // 可能ならその状態へ。出来ないなら false を返す。
  bool tryAddNewStroke()
  {
    //!!!!
    print(">tryAddNewStroke(${_state.toString()})");

    // Open状態でなければ追加できない
    if(_state != FigureState.Open) return false;

    // タイマーを停止
    _openTimer?.cancel();
    _openTimer = null;
    // 状態を切り替え
    print(">FigureState.Open => FigureState.WaitStroke");
    _state = FigureState.WaitStroke;

    return true;
  }

  // ストロークを追加
  bool addStroke(MyPolyline polyline)
  {
    //!!!!
    print(">addStroke(${_state.toString()})");

    // 図形の新規作成(Open/RemoteOpen)か、連続したストロークの追加(WaitStroke)のみ
    final bool removeByRemote = (_state == FigureState.RemoteOpen);
    final bool ok = (_state == FigureState.Open) ||
                    (_state == FigureState.WaitStroke) || 
                    removeByRemote;
    if(!ok) return false;

    // ストロークを追加
    _polylines.add(polyline);
    if(!removeByRemote){
      // 連続ストローク判定のタイマーを開始
      print(">${_state.toString()} => FigureState.Open");
      _state = FigureState.Open;
      _openTimer?.cancel();
      _openTimer = Timer(_openDuration, _onOpenTimer);

      // 他のユーザーへストローク追加を同期
      sentToDatabase(polyline);
    }

    return true;
  }

  // 連続ストローク判定のタイマーイベント
  void _onOpenTimer()
  {
    //!!!!
    print(">_onOpenTimer(${_state.toString()})");

    _openTimer = null;
    // 異常な状態遷移は無視
    if(_state != FigureState.Open) return;

    //!!!!
/*  _polylines.forEach((polyline){
      polyline.color = Color.fromARGB(255, 0, 0, 255);
    });
    _freehandDrawing.redraw();
*/
    // この図形を表示する期間のタイマーを開始
    print(">FigureState.Open => FigureState.Close");
    _state = FigureState.Close;
    _showTimer?.cancel();
    _showTimer = Timer(_showDuration, _onShowTimer);
  }

  // 表示期間完了のタイマーイベント
  void _onShowTimer()
  {
    //!!!!
    print(">_onShowTimer(${_state.toString()})");

    _showTimer = null;

    // 異常な状態遷移は無視
    final bool removeByRemote = (_state == FigureState.RemoteOpen);
    if((_state != FigureState.Close) && !removeByRemote){
      return;
    }

    // フェードアウトアニメーションを開始
    print(">${_state.toString()} => FigureState.FadeOut");
    _state = FigureState.FadeOut;
    _fadeAnimTimer?.cancel();
    _fadeAnimTimer = Timer.periodic(Duration(milliseconds: 125), _onFadeAnimTimer);
    _opacity = 255;

    // データベース上の図形も削除
    if(!removeByRemote){
      removeToDatabase();
    }
  }

  // フェードアウトアニメーション
  void _onFadeAnimTimer(Timer timer)
  {
    //!!!!
    print(">_onShowTimer(${_state.toString()})");

    // 異常な状態遷移は無視
    if(_state != FigureState.FadeOut) return;
    // フェードアウト
    _opacity -= 32;
    if(0 < _opacity){
      // 透明度を変更
      _polylines.forEach((polyline){
        polyline.color = polyline.color.withAlpha(_opacity);
      });
    }else{
      // 完全透明になったら削除
      _fadeAnimTimer?.cancel();
      _fadeAnimTimer = null;
      _freehandDrawing.removeFigure(this);
    }
    // アニメーションのための再描画
    _freehandDrawing.redraw();
  }

  // 内部状態をクリア
  void clear()
  {
    _openTimer?.cancel();
    _openTimer = null;
    _showTimer?.cancel();
    _showTimer = null;
    _fadeAnimTimer?.cancel();
    _fadeAnimTimer = null;
    removeToDatabase();
  }

  //---------------------------------------------------------------------------
  // 他ユーザーとのリアルタイム同期
  void sentToDatabase(MyPolyline polyline)
  {
    // 配置ファイルがオープンされていなければ何もしない
    if(_freehandDrawing.databaseRef == null) return;

    DatabaseReference ref = _freehandDrawing.databaseRef!.push();
    _polylineRefs.add(ref);

    // ストロークをデータベースに登録
    List<double> latlngs = [];
    polyline.points.forEach((pt){
      latlngs.add(pt.latitude);
      latlngs.add(pt.longitude);
    });
    ref.set({
      "key": _key,
      "senderId": _freehandDrawing.appInstKey,
      "time": ServerValue.timestamp,
      "color": polyline.color.value,
      "points": latlngs,
    });
  }

  // データベース上のストロークを消す
  void removeToDatabase()
  {
    _polylineRefs.forEach((ref){
      ref.remove();
    });
    _polylineRefs.clear();
  }

  // データベース経由で削除
  void removeByRemote()
  {
    // フェードアウトの削除シーケンス開始
    _onShowTimer();
  }

  // 同期データからポリラインを作成
  static MyPolyline? makePolyline(Map<String,dynamic> data)
  {
    MyPolyline? polyline;
    try {
      // 座標を LatLng 配列に変換
      List<dynamic> points = data["points"] as List<dynamic>;
      List<LatLng> latlngs = [];
      for(int i = 0; i < points.length; i += 2){
        latlngs.add(LatLng(
          points[i] as double, points[i+1] as double));
      }
      // ポリライン作成
      var color = Color(data["color"] as int);
      polyline = MyPolyline(
        points: latlngs,
        color: color,
        strokeWidth: 4.0,
        shouldRepaint: true);
    } catch(e) {
      //!!!!
      print(">Figure.makePolyline() failed!!!!");
    }
    return polyline;
  }
}

//-----------------------------------------------------------------------------
enum FigureState {
  Open,       // 次のストロークの追加可能な期間
  WaitStroke, // 次のストロークの完了を待っている
  Close,      // 次のストロークの追加は終了した期間(フェードアウトまでの待ち)
  FadeOut,    // フェードアウト中

  RemoteOpen, // 他のユーザーが作成したリモート図形として
}

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// ポリラインのリダクション
List<Offset> reducePolyline(List<Offset> points)
{
  // ポイントが2点以下ならそのまま戻す。
  final int N = points.length;
  if(N <= 2) return points;

  // 角として残すポイントのフラグ配列
  List<bool> corner = List.filled(N, false);
  corner[0] = corner[N-1] = true;

  // 残す角を探す
  reducePolylineSub(points, corner, 0, N-1);

  // 角として残ったポイントのみで配列を作って返す
  List<Offset> res = [];
  for(int i = 0; i < N; i++){
    if(corner[i]) res.add(points[i]);
  }

  return res;
}

// 再帰処理
void reducePolylineSub(
  List<Offset> points, List<bool> corner, int sidx, int tidx)
{
  // 始点[sidx]終点[tidx]の間にポイントがなければ、それ以上探索しない
  if(tidx < sidx+2) return;

  // 始点終点の間で、最も遠いポイントを探す
  var r = getMaxLength(points, sidx, tidx);

  // それがしきい値より遠ければ、そこを角として残して、その前後に再帰
  // しきい値 : 2ドット
  final double th = 2.0;
  if(th <= r["distance"]){
    final int index = r["index"];
    corner[index] = true;
    // 前半へ
    reducePolylineSub(points, corner, sidx, index);
    // 後半へ
    reducePolylineSub(points, corner, index, tidx);
  }
}

//-----------------------------------------------------------------------------
// エッジから最も遠いポイントを求める
dynamic getMaxLength(List<Offset> points, int sidx, int tidx)
{
  // 始点[sidx]終点[tidx]の間にポイントがなければ始点を返す
  // NOTE: 呼び出し元で対策済み
//  if(tidx < sidx+2){
//    return { "distance":0.0, "index":sidx };
//  }

  // 最も遠いポイントを求める
  double maxDistance = 0.0;
  int maxDistanceIndex = sidx;
  final double v0d = (points[tidx] - points[sidx]).distance;
  if(3.0 <= v0d){
    // 始点[sidx]終点[tidx]の距離がある場合にはエッジとの距離
    final double v0x = -(points[tidx].dy - points[sidx].dy);
    final double v0y =  (points[tidx].dx - points[sidx].dx);
    for(int i = sidx+1; i < tidx; i++){
      final double v1x = (points[i].dx - points[sidx].dx);
      final double v1y = (points[i].dy - points[sidx].dy);
      final double ip = (v0x * v1x) + (v0y * v1y);
      final double d = (ip / v0d).abs();
      if(maxDistance <= d){
        maxDistance = d;
        maxDistanceIndex = i;
      }
    }
  }else{
    // 距離が無い場合には中点との距離
    final Offset p0 = (points[sidx] + points[tidx]) / 2;
    for(int i = sidx+1; i < tidx; i++){
      final double d = (points[i] - p0).distance;
      if(maxDistance <= d){
        maxDistance = d;
        maxDistanceIndex = i;
      }
    }
  }

  return { "distance":maxDistance, "index":maxDistanceIndex };
}

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// アプリへの組み込み
class FreehandDrawingOnMap extends StatefulWidget
{
  const FreehandDrawingOnMap({super.key});

  @override
  State<FreehandDrawingOnMap> createState() => _FreehandDrawingOnMapState();
}

class _FreehandDrawingOnMapState extends State<FreehandDrawingOnMap>
{
  // 手書き有効/無効スイッチ
  bool _dawingActive = false;

  @override
  void initState()
  {
  }

  @override
  Widget build(BuildContext context)
  {
    //!!!!
    print(">FreehandDrawingOnMap.build() !!!!");

    return Stack(
      children: [
        // 手書き有効/無効ボタン
        Align(
          // 画面右下に配置
          alignment: const Alignment(1.0, 1.0),
          child: FractionalTranslation(
            translation: const Offset(0, -1),
            child: TextButton(
              child: const Icon(Icons.border_color, size: 55),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange.shade900,
                backgroundColor: _dawingActive? Colors.white: Colors.transparent,
                shadowColor: Colors.transparent,
                fixedSize: const Size(80,80),
                padding: const EdgeInsets.fromLTRB(0,0,0,20),
                shape: const CircleBorder(),
              ),
              onPressed: ()
              {
                // この setState() は FreehandDrawingOnMap の範囲のみ build を実行
                // FlutterMap 含む MyHomePage は build されない
                setState((){ _dawingActive = !_dawingActive; });
              },
            ),
          ),
        ),

        // 手書きジェスチャー
        if(_dawingActive) GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (details)
          {
            freehandDrawing.onStrokeStart(details.localPosition);
          },
          onPanUpdate: (details)
          {
            freehandDrawing.onStrokeUpdate(details.localPosition);
          },
          onPanEnd: (details)
          {
            freehandDrawing.onStrokeEnd();
          }
        ),
      ],
    );
  }
}
