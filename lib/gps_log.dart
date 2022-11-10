import 'dart:async';   // Stream使った再描画
import 'dart:typed_data'; // Uint8List
import 'dart:convert';  // Base64
import 'dart:ui';  // lerp

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';  // GPXの読み込み
import 'package:file_selector/file_selector.dart';  // ファイル選択
import 'package:flutter_map/flutter_map.dart';  // 地図
import 'package:intl/intl.dart';  // 日時の文字列化
import 'package:firebase_storage/firebase_storage.dart';  // Cloud Storage
import 'package:firebase_core/firebase_core.dart';  // Firebase RealtimeDatabase
import 'package:firebase_database/firebase_database.dart';

import 'file_tree.dart';
import 'text_ballon_widget.dart';
import 'ok_cancel_dialog.dart';
import 'mypolyline_layer.dart'; // マップ上のカスタムポリライン
import 'misc_marker.dart';  // キルマーカー
import 'globals.dart';  // 画面解像度

// ログデータがないときに使う、ダミーの開始終了時間
final _dummyStartTime = DateTime(2022, 1, 1, 7);  // 2022/1/1 AM7:00
final _dummyEndTime = DateTime(2022, 1, 1, 11);  // 2022/1/1 AM11:00

// GPS端末のパラメータ
final Map<int, GPSDeviceParam> _deviceParams = {
  1568: GPSDeviceParam(
    name: "ムロ",
    color:Color.fromARGB(255,255,0,110),
    iconImagePath: "assets/dog_icon/001.png"),
  1674: GPSDeviceParam(
    name: "ロト",
    color:Color.fromARGB(255,128,0,255),
    iconImagePath: "assets/dog_icon/002.png"),
  4539: GPSDeviceParam(
    name: "ガロ",
    color:Color.fromARGB(255,255,106,0),
    iconImagePath: "assets/dog_icon/000.png"),
  4739: GPSDeviceParam(
    name:"アオ",
    color:Color.fromARGB(255,255,216,0),
    iconImagePath: "assets/dog_icon/003.png"),
};


//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 犬達のログ
GPSLog gpsLog = GPSLog();

class GPSLog
{
  Map<int, _Route> routes = {};
  List<MyPolyline> _mapLines = [];

  // マップ上の犬マーカー配列
  List<Marker> _dogMarkers = [];

  // 現在読み込んでいるログの、クラウド上のパス(ユニークID)
  String? _openedUIDPath;
  // 他のデータへの参照か？
  bool _isReferenceLink = false;

  //----------------------------------------------------------------------------
  // 開始時間
  DateTime _startTime = _dummyStartTime;
  DateTime get startTime => _startTime;
  DateTime _getStartTime()
  {
    if(routes.isEmpty) return _dummyStartTime;

    var t = DateTime(2100); // 適当な遠い未来の時間
    routes.forEach((id, route){
      if(route.startTime.isBefore(t)){
        t = route.startTime;
      }
    });
    return t;
  }

  // 終了時間
  DateTime _endTime = _dummyEndTime;
  DateTime get endTime => _endTime;
  DateTime _getEndTime()
  {
    if(routes.isEmpty) return _dummyEndTime;

    var t = DateTime(2000); // 適当な過去の時間
    routes.forEach((id, route){
      if(t.isBefore(route.endTime)){
        t = route.endTime;
      }
    });
    return t;
  }

  //----------------------------------------------------------------------------
  // トリミング開始時間
  DateTime _trimStartTime = _dummyStartTime;
  DateTime get trimStartTime => _trimStartTime;
  void setTrimStartTime(DateTime t)
  {
    _trimStartTime = (t.isAfter(_startTime)? t: _startTime);
    if(_currentTime.isBefore(_trimStartTime)) _currentTime = _trimStartTime;
  }

  // トリミング終了時間
  DateTime _trimEndTime = _dummyEndTime;
  DateTime get trimEndTime => _trimEndTime;
  void setTrimEndTime(DateTime t)
  {
    _trimEndTime = (t.isBefore(_endTime)? t: _endTime);
    if(_trimEndTime.isBefore(_currentTime)) _currentTime = _trimEndTime;
  }

  //----------------------------------------------------------------------------
  // 再生時間
  DateTime _currentTime = _dummyStartTime;
  DateTime get currentTime => _currentTime;
  void setCurrentTime(DateTime time)
  {
    if(time.isBefore(_trimStartTime)) time = _trimStartTime;
    if(_trimEndTime.isBefore(time)) time = _trimEndTime;
    _currentTime = time;
  }

  //----------------------------------------------------------------------------
  // アニメーション再生、停止、巻き戻し
  void playAnim()
  {
    // すでに再生中なら何もしない
    if(_animPlaying) return;
    _animPlaying = true;

    // タイマースタート
    _animTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // すすめる
      // 60倍速(1時間を1分で再生)
      _currentTime = _currentTime.add(const Duration(seconds:6));
      // リピート
      if(_trimEndTime.isBefore(_currentTime)){
        _currentTime = _trimStartTime;
      }
      // 再描画
      makeDogMarkers();
      redraw();
      bottomSheetSetState?.call((){});
    });
  }

  void stopAnim()
  {
    // 再生中でなければ何もしない
    if(!_animPlaying) return;
    _animPlaying = false;

    // タイマーを停止
    _animTimer?.cancel();
    _animTimer = null;

    // 再描画
    bottomSheetSetState?.call((){});
  }

  void firstRewindAnim()
  {
    // 再生位置リセット
    _currentTime = _trimStartTime;
    // 再描画
    makeDogMarkers();
    redraw();
    bottomSheetSetState?.call((){});
  }

  bool isAnimPlaying()
  {
    return _animPlaying;
  }

  // アニメーション再生中かフラグ
  bool _animPlaying = false;

  // 描画更新用のタイマー
  Timer? _animTimer;

  //----------------------------------------------------------------------------
  // 再描画用の Stream
  var _stream = StreamController<void>.broadcast();
  // 再描画用のストリームを取得
  Stream<void> get reDrawStream => _stream.stream;
  // 再描画
  void redraw()
  {
    _stream.sink.add(null);
  }

  //----------------------------------------------------------------------------
  // リセット
  void clear()
  {
    _startTime = _trimStartTime = _dummyStartTime;
    _endTime = _trimEndTime = _dummyEndTime;
    _currentTime = _trimStartTime;

    routes.clear();
    _mapLines.clear();
    _dogMarkers.clear();
  
    _thisUpdateTime = null;

    _openedUIDPath = null;
    _isReferenceLink = false;

    // 直前の同期イベントを削除
    _updateTrimSyncEvent?.cancel();
    _updateTrimSyncEvent = null;
  }

  //----------------------------------------------------------------------------
  // GPXファイルからログを読み込む
  bool addLogFromGPX(String fileContent)
  {
    // XMLパース
    final XmlDocument gpxDoc = XmlDocument.parse(fileContent);

    final XmlElement? gpx_ = gpxDoc.getElement("gpx");
    if(gpx_ == null) return false;

    // トリムが設定されているかをチェック
    final bool changeTrimSrart = (_startTime != _trimStartTime);
    final bool changeTrimEnd = (_endTime != _trimEndTime);

    // 複数のログがマージされたファイルに対応
    final Iterable<XmlElement> rtes_ = gpx_.findElements("rte");
    int addCount = 0;
    rtes_.forEach((rte_) {
      final XmlElement? name_ = rte_.getElement("name");
      if(name_ == null) return;
      final String name = name_.text;
      // 名前からデバイスIDを取得
      int i = name.indexOf("ID_");
      int deviceId = 0;
      if(0 <= i){
        deviceId = int.tryParse(name.substring(i + 3)) ?? 0;
      }
      print("name=${name}, deviceId=${deviceId}");

      _Route newRoute = _Route();
      bool res = newRoute.readFromGPX(rte_, name, deviceId);
      if(res){
        if(!routes.containsKey(deviceId)){
          // 新しいログを追加
          routes[deviceId] = newRoute;
        }else{
          // 既にあるログと結合
          routes[deviceId]!.merge(newRoute);
        }
        addCount++;
      }
    });
    bool res = (0 < addCount);

    // トリム時間を新しい範囲に合わせる(トリムの設定がない場合のみ)
    if(res){
      _startTime = _getStartTime();
      _endTime = _getEndTime();
      if(!changeTrimSrart) _trimStartTime = _startTime;
      if(!changeTrimEnd)  _trimEndTime = _endTime;
    }
    
    return res;
  }

  // GPXへ変換
  String exportGPX()
  {
    // ヘッダ
    String gpx = '<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1">\n';

    // デバイス毎
    routes.forEach((id, route){
      gpx += route.exportGPX();
    });

    // フッダー
    gpx += '</gpx>\n';

    return gpx;
  }

  //----------------------------------------------------------------------------
  // クラウドストレージ
  static Reference _getRef(String path)
  {
    if(path[0] == "/") path = path.substring(1);
    final String storagePath = path + ".gpx";
    return FirebaseStorage.instance.ref().child(storagePath);
  }

  // 取得しているデータの更新日時
  DateTime? _thisUpdateTime;

  // クラウドストレージにアップロード
  Future<bool> uploadToCloudStorage(String path) async
  {
    //!!!!
    print("uploadToCloudStorage(${path})");

    // ストレージ上のファイルパスを参照
    final gpxRef = _getRef(path);
  
    // GPXに変換してアップロード
    String gpx = exportGPX();
    bool res = true;
    try {
      await gpxRef.putString(gpx,
        format: PutStringFormat.raw,
        metadata: SettableMetadata(contentType: "application/xml"));
      FullMetadata meta = await gpxRef.getMetadata();
      _thisUpdateTime = meta.updated;
    } on FirebaseException catch (e) {
      res = false;
    } on Exception catch (e) {
      res = false;
    }

    // 成功していたらパスを記録
    if(res){
      _openedUIDPath = path;
    }
  
    //!!!!
    print("uploadToCloudStorage() res=${res}");

    return res;
  }

  // クラウドストレージからダウンロード
  Future<bool> downloadFromCloudStorage(String path, bool referenceLink) async
  {
    //!!!!
    print(">downloadFromCloudStorage(${path})");

    // ストレージ上のファイルパスを参照
    final gpxRef = _getRef(path);

    // GPXから読み込み
    bool res = true;
    try {
      final Uint8List? data = await gpxRef.getData();
      res = (data != null);
      if(res){
        var gpxText = utf8.decode(data);
        res = addLogFromGPX(gpxText);
      }
      if(res){
        FullMetadata meta = await gpxRef.getMetadata();
        _thisUpdateTime = meta.updated;
      }
    } on FirebaseException catch (e) {
      res = false;
    } on Exception catch (e) {
      res = false;
    }

    // 成功していたらパスを記録
    if(res){
      _openedUIDPath = path;
      _isReferenceLink = referenceLink;
    }

    //!!!!
    print(">downloadFromCloudStorage(${path}) ${res}");

    return res;
  }

  // クラウドストレージから削除
  static void deleteFromCloudStorage(String path)
  {
    // ストレージ上のファイルパスを参照
    final gpxRef = _getRef(path);
    try {
      gpxRef.delete();
    } catch(e){}
  }

  // クラウドストレージのデータが更新されているか？
  Future<bool> isUpdateCloudStorage(String path) async
  {
    // クラウドストレージ上のファイルのメタデータを取得して比較
    // クラウド上にデータが無ければ、必ず false にする。
    final gpxRef = _getRef(path);
    DateTime? cloudUpdateTime;
    try {
      FullMetadata meta = await gpxRef.getMetadata();
      cloudUpdateTime = meta.updated;
    } catch(e) {
    }
    if(cloudUpdateTime == null) return false;

    // クラウド上にデータがあって、ローカルが空なら、必ず true になる。
    if(_thisUpdateTime == null){
      return true;
    }

    // クラウドとローカルの両方にデータがあれば、比較
    // クラウドのほうが新しければ true を返す
    return (_thisUpdateTime!.compareTo(cloudUpdateTime!) < 0);
  }

  //----------------------------------------------------------------------------
  // 読み込んでいるログのクラウド上のパスを取得(ユニークID)
  String? getOpenedPath()
  {
    return _openedUIDPath;
  }

  //----------------------------------------------------------------------------
  // 他のデータへの参照かを取得
  bool isReferenceLink()
  {
    return _isReferenceLink;
  }

  //----------------------------------------------------------------------------
  // 他のデータを参照
  void saveReferencePath(String thisUIDPath, String refUIDPath)
  {
    print(">saveReferencePath(${thisUIDPath} -> ${refUIDPath})");
  
    final String dbPath = "assign" + thisUIDPath + "/gps_log";
    final DatabaseReference ref = FirebaseDatabase.instance.ref(dbPath);
    final data = {
      "referencePath" : refUIDPath,
    };
    ref.update(data);
  }

  // 読み込むべきデータのパスを取得
  // 他のデータを参照していれば、そちらのパスを返す
  Future<String> getReferencePath(String thisUIDPath) async
  {
    print(">getReferencePath(${thisUIDPath})");

    String? refUIDPath;
    final String dbPath = "assign" + thisUIDPath + "/gps_log";
    final DatabaseReference ref = FirebaseDatabase.instance.ref(dbPath);
    final DataSnapshot snapshot = await ref.get();
    if(snapshot.exists){
      try {
        var data = snapshot.value as Map<String, dynamic>;
        refUIDPath = data["referencePath"];
      } catch(e) {}
    }
    if(refUIDPath == null) refUIDPath = thisUIDPath;
  
    print(">getReferencePath(${thisUIDPath}) -> ${refUIDPath}");

    return refUIDPath;
  }

  // 他のデータへの参照を削除
  void removeReferencePath(String thisUIDPath)
  {
    print(">removeReferencePath(${thisUIDPath})");

    final String dbPath = "assign" + thisUIDPath + "/gps_log";
    final DatabaseReference ref = FirebaseDatabase.instance.ref(dbPath);
    ref.remove();
  }

  //----------------------------------------------------------------------------
  // トリミング範囲の同期
  StreamSubscription<DatabaseEvent>? _updateTrimSyncEvent;
  void Function(void Function())? bottomSheetSetState;

  void saveGPSLogTrimRangeToDB(String uidPath)
  {
    final String dbPath = "assign" + uidPath + "/gps_log";
    final DatabaseReference ref = FirebaseDatabase.instance.ref(dbPath);
    final trimData = {
      "trimStartTime" : _trimStartTime.toIso8601String(),
      "trimEndTime" : _trimEndTime.toIso8601String(),
    };
    ref.update(trimData);
  }

  Future<void> loadGPSLogTrimRangeFromDB(String uidPath) async
  {
    // 直前の同期イベントを削除
    _updateTrimSyncEvent?.cancel();
    _updateTrimSyncEvent = null;
  
    // 読み込み
    final String dbPath = "assign" + uidPath + "/gps_log";
    final DatabaseReference ref = FirebaseDatabase.instance.ref(dbPath);
    final DataSnapshot snapshot = await ref.get();
    if(snapshot.exists){
      try {
        // 同期イベントを設定
        // 接続直後の初回読み込みで、読み込みと再描画が行われる。
        _updateTrimSyncEvent = ref.onValue.listen((DatabaseEvent event){
          _onUpdateTrimSync(event);
        });
      } catch(e) {}
    }
  }

  void _onUpdateTrimSync(DatabaseEvent event)
  {
    if(event.snapshot.exists){
      try {
        final trimData = event.snapshot.value as Map<String, dynamic>;
        final start = DateTime.parse(trimData["trimStartTime"]!);
        final end = DateTime.parse(trimData["trimEndTime"]!);
        bool change = (trimStartTime != start) || (trimEndTime != end);
        if(change){
          setTrimStartTime(start);
          setTrimEndTime(end);
          // 描画
          gpsLog.makePolyLines();
          gpsLog.makeDogMarkers();
          gpsLog.redraw();
          bottomSheetSetState?.call((){});
        }
      } catch(e) {}
    }
  }

  //----------------------------------------------------------------------------
  // FlutterMap用のポリラインを作成

  // 表示/非表示フラグ
  bool showLogLine = true;

  List<MyPolyline> makePolyLines()
  {
    _mapLines.clear();
    if(showLogLine){
      routes.forEach((id, route){
        _mapLines.add(route.makePolyLine(_trimStartTime, _trimEndTime));
      });
    }
    return _mapLines;
  }

  //----------------------------------------------------------------------------
  // FlutterMap用の犬マーカーを作成
  List<Marker> makeDogMarkers()
  {
    _dogMarkers.clear();
    if(showLogLine){
      routes.forEach((id, route){
        var marker = route.makeDogMarker(_currentTime);
        if(marker != null){
          _dogMarkers.add(marker);
        }
      });
    }
    return _dogMarkers;
  }
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 犬毎のパラメータ
class GPSDeviceParam
{
  GPSDeviceParam({
    this.name = "",
    this.color = Colors.green,
    this.iconImagePath = "",
  });
  // 犬の名前
  String name;
  // ラインカラー
  Color color;
  // アイコン用画像
  String iconImagePath;
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 一頭のルート
class _Route
{
  // 通過点リスト
  List<_Point> _points = [];
  // 端末名
  String _name = "";
  // ID(nameに書かれている端末ID)
  int _deviceId = 0;
  // アイコンイメージ
  Image? _iconImage = null;

  //----------------------------------------------------------------------------
  // 開始時間
  DateTime get startTime =>
    (0 < _points.length)? _points.first.time: _dummyStartTime;
  // 終了時間
  DateTime get endTime =>
    (0 < _points.length)? _points.last.time: _dummyEndTime;

  // トリミングに対応した開始インデックス
  int _trimStartIndex = -1;
  DateTime _trimStartCache = DateTime(2022);
  // トリミングに対応した終了インデックス
  int _trimEndIndex = -1;
  DateTime _trimEndCache = DateTime(2022);

  //----------------------------------------------------------------------------
  // GPXファイルからログを作成
  bool readFromGPX(XmlElement rte_, String name, int deviceId)
  {
    _name = name;
    _deviceId = deviceId;
    
    // ルートの通過ポイントを読み取り
    bool ok = true;
    final Iterable<XmlElement> rtepts_ = rte_.findElements("rtept");
    rtepts_.forEach((pt){
      final String? lat = pt.getAttribute("lat");
      final String? lon = pt.getAttribute("lon");
      final XmlElement? time = pt.getElement("time");
      if((lat != null) && (lon != null) && (time != null)){
        // 時間はUTCから日本時間に変換しておく
        late DateTime dateTime;
        try { dateTime = DateTime.parse(time.text).toLocal(); }
        catch(e){ ok = false; }
        if(!ok) return;
        
        _points.add(_Point(
          LatLng(double.parse(lat), double.parse(lon)),
          dateTime));
      }else{
        ok = false;
        return;
      }
    });

    // なんらか失敗していたらデータを破棄
    if(!ok){
      _points.clear();
    }
  
    return ok;
  }

  // GPXへ変換
  String exportGPX()
  {
    // <rte>タグ開始
    String gpx = '<rte>\n<name>ID_${_deviceId}</name>\n';

    // 通過ポイント
    _points.forEach((pt){
      gpx += '<rtept lat="${pt.pos.latitude}" lon="${pt.pos.longitude}">\n';
      gpx += '<time>' + pt.time.toIso8601String() + '</time>\n';
      gpx += '</rtept>\n';
    });

    // 終了
    gpx += '</rte>\n';
  
    return gpx;
  }

  //----------------------------------------------------------------------------
  // 同じデバイスの2つのルートデータをマージ
  void merge(_Route route)
  {
    // リストを結合して、距離および時間の条件で通過ポイントを間引く
    _points.addAll(route._points);
    _points.sort((a,b) { return a.time.compareTo(b.time); });
    int prev = 0;
    int seek = 1;
    final distance = Distance();
    while(seek < _points.length)
    {
      // 直前の通過ポイントから、5[m]以上離れているか、60[秒]以上経過していれば採用
      final pt0 = _points[prev]; 
      final pt1 = _points[seek]; 
      double D = distance(pt0.pos, pt1.pos);
      int S = pt1.time.difference(pt0.time).inSeconds;
      if((5.0 <= D) || (60 <= S)){
        prev++;
        _points[prev] = pt1;
      }
      seek++;
    }
    // 最後の通過ポイントも
    if(_points[prev].time.compareTo(_points.last.time) < 0){
      prev++;
      _points[prev] = _points.last;
    }
    int count = prev + 1;
    if(count < _points.length){
      _points = _points.sublist(0, count);
    }
  }

  //----------------------------------------------------------------------------
  // 指定された時間の座標を計算
  LatLng calcPositionAtTime(DateTime time)
  {
    final int t = time.millisecondsSinceEpoch;

    // データの範囲外なら、先頭か終端の座標を返す
    var firstPointMs = _points[_trimStartIndex].time.millisecondsSinceEpoch;
    var lastPointMs = _points[_trimEndIndex-1].time.millisecondsSinceEpoch;
    if(t <= firstPointMs) return _points[_trimStartIndex].pos;
    if(lastPointMs <= t) return _points[_trimEndIndex-1].pos;
  
    // 直前と同じ区間か、その直後の可能性が高いので、そこを優先的にチェック
    int index = -1;
    late int t0;
    late int t1;
    if(0 <= _cacheIndexAtTime){
      t0 = _points[_cacheIndexAtTime].time.millisecondsSinceEpoch;
      t1 = _points[_cacheIndexAtTime+1].time.millisecondsSinceEpoch;
      final bool into = (t0 <= t) && (t <= t1);
      if(into){
        index = _cacheIndexAtTime;
      }else if(_cacheIndexAtTime < (_trimEndIndex-2)){
        t0 = t1;
        t1 = _points[_cacheIndexAtTime+2].time.millisecondsSinceEpoch;
        final bool into = (t0 <= t) && (t <= t1);
        if(into){
          index = _cacheIndexAtTime + 1;
        }
      }
    }

    // キャッシュヒットしなければ、この時間を含む通過点の区間を探す
    if(index < 0){
      for(int i = _trimStartIndex; i < _trimEndIndex-1; i++){
        t0 = _points[i].time.millisecondsSinceEpoch;
        t1 = _points[i+1].time.millisecondsSinceEpoch;
        bool into = (t0 <= t) && (t <= t1);
        if(into){
          index = i;
          break;
        }
      }
    }
  
    // 今回の通過点の区間をキャッシュしておく
    _cacheIndexAtTime = index;

    // 時間に対応する、通過点の区間の中の座標を計算
    var res = LatLng(0,0);
    if(0 <= index){
      double tt = (t - t0) / (t1 - t0);
      var pos0 = _points[index].pos;
      var pos1 = _points[index+1].pos;
      res = LatLng(
        lerpDouble(pos0.latitude, pos1.latitude, tt)!,
        lerpDouble(pos0.longitude, pos1.longitude, tt)!);
    }
    return res;
  }

  // 直前の calcPositionAtTime() で参照した通過点区間のインデックス(キャッシュ利用)
  int _cacheIndexAtTime = -1;

  //----------------------------------------------------------------------------
  // FlutterMap用のポリラインを作成
  MyPolyline makePolyLine(DateTime trimStart, DateTime trimEnd)
  {
    // トリミングのキャッシュが有効か判定して、必要なら範囲を探す
    final bool cacheOk =
      (_trimStartCache == trimStart) && (_trimEndCache == trimEnd);
    if(!cacheOk){
      _trimStartCache = trimStart;
      _trimEndCache = trimEnd;
      if(isEqualBefore(trimStart, _points.first.time)){
        _trimStartIndex = 0;
      }else{
        for(int i = 0; i < _points.length-1; i++){
          final DateTime t0 = _points[i].time;
          final DateTime t1 = _points[i+1].time;
          if(isEqualBefore(t0, trimStart) && isBefore(trimStart, t1)){
            _trimStartIndex = i;
            break;
          }
        }
      }
      if(isEqualBefore(_points.last.time, trimEnd)){
        _trimEndIndex = _points.length;
      }else{
        for(int i = _points.length-1; 0 < i; i--){
          final DateTime t0 = _points[i-1].time;
          final DateTime t1 = _points[i].time;
          if(isBefore(t0, trimEnd) && isEqualBefore(trimEnd, t1)){
            _trimEndIndex = i + 1;
            break;
          }
        }
      }
    }
    // キャッシュされた範囲でポリラインを作成
    List<LatLng> line = [];
    for(int i = _trimStartIndex; i < _trimEndIndex; i++){
      line.add(_points[i].pos);
    }
    // 端末IDからカラー
    final Color color =
      _deviceParams[_deviceId]?.color ??
      const Color.fromARGB(255,128,128,128);

    return MyPolyline(
      points:line,
      color:color,
      strokeWidth:2.0);
  }

  // FlutterMap用の犬マーカーを作成
  Marker? makeDogMarker(DateTime time)
  {
    // アイコン画像を読み込んでおく
    if(_iconImage == null){
      var path = _deviceParams[_deviceId]?.iconImagePath;
      if(path != null){
        _iconImage = Image.asset(path);
      }
    }
    if(_iconImage == null) return null;
  
    return Marker(
      point: calcPositionAtTime(time),
      width: 42.0,  // メンバーマーカー小と同じサイズ。([64x72]の2/3)
      height: 48.0,
      anchorPos: AnchorPos.exactly(Anchor(21, 0)),
      builder: (ctx) => _iconImage!,
    );
  }
}

// DateTime の比較
bool isBefore(DateTime t0, DateTime t1)
{
  return t0.compareTo(t1) < 0;
}
bool isEqualBefore(DateTime t0, DateTime t1)
{
  return t0.compareTo(t1) <= 0;
}

//----------------------------------------------------------------------------
// ルートを構成する通過ポイント
class _Point
{
  _Point(
    this.pos,
    this.time,
  );

  // 座標
  LatLng pos;
  // 時間
  DateTime time;
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// GPSログの読み込み処理
Future<bool> readGPSLog(BuildContext context) async
{
  // .pgx ファイルを選択して開く
  final XTypeGroup typeGroup = XTypeGroup(
    label: 'gpx',
    extensions: ['gpx'],
  );
  final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return false;

  // ファイル読み込み
  final String fileContent = await file.readAsString();

  // XMLパース
  final bool res = gpsLog.addLogFromGPX(fileContent);
  if(!res) return false;

  return true;
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// GPSメニュー用のポップアップメニューを開く
void showGPSLogPopupMenu(BuildContext context)
{
  // メニューの座標
  final double x = getScreenWidth() - 200;
  final double y = 60;

  // Note: アイコンカラーは ListTile のデフォルトカラー合わせ
  showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(x, y, x, y),
    elevation: 8.0,
    items: [
      makePopupMenuItem(0, "ログ読み込み", Icons.file_open),
      makePopupMenuItem(1, "ログ参照", Icons.link),
      makePopupMenuItem(2, "トリミング", Icons.content_cut),
      makePopupMenuItem(3, "アニメーション", Icons.play_circle),
      makePopupMenuItem(4, "キルマーカー", Icons.pin_drop),
    ],
  ).then((value) async {
    switch(value ?? -1){
    case 0: // GPSログの読み込み
      loadGPSLogFunc(context);
      break;

    case 1: // ログ参照
      linkGPSLogFunc(context);
      break;

    case 2: // トリミング
      // アニメーション停止
      gpsLog.stopAnim();
      showTrimmingBottomSheet(context);
      break;
    
    case 3: // アニメーション
      showAnimationBottomSheet(context);
      break;
    
    case 4: // キルマーカー
      addKillMarkerFunc(context);
      break;
    }
  });
}

//----------------------------------------------------------------------------
// GPSログ読み込み
void loadGPSLogFunc(BuildContext context) async
{
  // アニメーション停止
  gpsLog.stopAnim();
  // BottomSheet を閉じる
  closeBottomSheet();
  // クラウドの方に新しいデータがあれば、まずはそちらを読み込む
  final filePath = getOpenedFileUIDPath();
  final String gpsLogPath = await gpsLog.getReferencePath(filePath);
  final bool refLink = (gpsLogPath != filePath);
  if(await gpsLog.isUpdateCloudStorage(gpsLogPath))
  {
    await showOkDialog(context, title:"GPSログ",
      text:"オンラインに、他のユーザーによる新しいログデータがあります。まずそのデータを読み込みます。");
    gpsLog.clear();
    gpsLog.downloadFromCloudStorage(gpsLogPath, refLink).then((res){
      gpsLog.makePolyLines();
      gpsLog.makeDogMarkers();
      gpsLog.redraw();
    });
    return;
  }

  bool res = await readGPSLog(context);
  // 読み込み成功したらマップを再描画
  if(res){
    gpsLog.makePolyLines();
    gpsLog.makeDogMarkers();
    gpsLog.redraw();
    showTextBallonMessage("GPSログの読み込み成功");
    // 裏でクラウドストレージへのアップロードを実行
    gpsLog.uploadToCloudStorage(gpsLogPath);
  }else{
    showTextBallonMessage("GPSログの読み込み失敗");
  }
}

//----------------------------------------------------------------------------
// GPSログ参照
void linkGPSLogFunc(BuildContext context) async
{
  // アニメーション停止
  gpsLog.stopAnim();
  // BottomSheet を閉じる
  closeBottomSheet();
  // ファイル一覧画面に遷移して、ファイルの切り替え
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => FilesPage(
      onSelectFile: (refUIDPath) async {
        //!!!!
        print("linkGPSLogFunc.onSelectFile(${refUIDPath})");

        // 今と同じGPSログを選択した場合には、何もしない
        if(gpsLog.getOpenedPath() == refUIDPath) return;

        // GPSログを読み込み(遅延処理)
        gpsLog.clear();
        gpsLog.downloadFromCloudStorage(refUIDPath, true).then((res) async {
          if(res){
            String openedFileUIDPath = getOpenedFileUIDPath();
            gpsLog.saveReferencePath(openedFileUIDPath, refUIDPath);
          }
          showTextBallonMessage(
            (res? "他のファイルからGPSログを参照": "GPSログの参照に失敗"));
          gpsLog.makePolyLines();
          gpsLog.makeDogMarkers();
          gpsLog.redraw();
        });
      },
      onChangeState: (){},
    ))
  );
}

//----------------------------------------------------------------------------
// キルマーカーの追加
void addKillMarkerFunc(BuildContext context)
{
  // 現在のマップ表示の中心に
  miscMarkers.addMarker(mainMapController.center);
  // 再描画
  updateMapView();
}

//----------------------------------------------------------------------------
// トリム範囲の更新と再描画
void _updateTrimRangeByUI(RangeValues values, int baseMS)
{
  final int trimStartMS = baseMS + (values.start.toInt() * 1000);
  gpsLog.setTrimStartTime(DateTime.fromMillisecondsSinceEpoch(trimStartMS));

  final int trimEndMS = baseMS + (values.end.toInt() * 1000);
  gpsLog.setTrimEndTime(DateTime.fromMillisecondsSinceEpoch(trimEndMS));

  // 描画
  gpsLog.makePolyLines();
  gpsLog.makeDogMarkers();
  gpsLog.redraw();
}

//----------------------------------------------------------------------------
// アニメーション時間の更新と再描画
void _updateCurrentTimeByUI(double values, int baseMS)
{
  final int currentMS = baseMS + (values.toInt() * 1000);
  var currentTime = DateTime.fromMillisecondsSinceEpoch(currentMS);
  gpsLog.setCurrentTime(currentTime);

  // 描画
  gpsLog.makeDogMarkers();
  gpsLog.redraw();
}

//----------------------------------------------------------------------------
// トリミング用ボトムシートを開く
void showTrimmingBottomSheet(BuildContext context)
{
  // ログ全体の時間範囲
  final int baseMS = gpsLog.startTime.millisecondsSinceEpoch;
  final double durationSec = (gpsLog.endTime.millisecondsSinceEpoch - baseMS) / 1000;
  
  bottomSheetController = 
    appScaffoldKey.currentState!.showBottomSheet((context)
    {
      return StatefulBuilder(
        builder: (context, StateSetter setModalState)
        {
          // 他のユーザーからのトリミング範囲の変更通知で再描画
          gpsLog.bottomSheetSetState = setModalState;

          // 現在のトリミング時間範囲
          final DateTime trimStartTime = gpsLog.trimStartTime;
          final DateTime trimEndTime = gpsLog.trimEndTime;
          var rangeValues = RangeValues(
            (trimStartTime.millisecondsSinceEpoch - baseMS) / 1000,
            (trimEndTime.millisecondsSinceEpoch - baseMS) / 1000);
          String trimStartText =
            "${trimStartTime.hour}:" + _twoDigits(trimStartTime.minute);
          String trimEndText =
            "${trimEndTime.hour}:" + _twoDigits(trimEndTime.minute);

          // 他のフィルを参照していれば、参照先のファイル名を表示
          Widget? refFileName;
          if(gpsLog.isReferenceLink()){
            String uidPath = gpsLog.getOpenedPath() ?? "";
            final int t = uidPath.lastIndexOf("/");
            if(0 <= t){
              uidPath = uidPath.substring(t);
              final String fileName = convertUIDPath2NamePath(uidPath);
              refFileName = Row(children:[
                Text("["),
                const Icon(Icons.link, size:20),
                Text(
                  " " + fileName.substring(1) + "]",
                  style: const TextStyle(fontSize: 16),
                ),
              ]);
            }
          }

          return Scaffold(
            body: Container(
              padding: EdgeInsets.only(top:15), // スライダーの上のパディング
              color: Colors.brown.shade100,
              child: Column(
                children: [
                  // トリミング範囲スライダー
                  SliderTheme(
                    data: SliderThemeData(),
                    child: RangeSlider(
                      values: rangeValues,
                      min: 0,
                      max: durationSec,
                      onChanged: (values) {
                        // トリム範囲の更新と再描画
                        setModalState((){
                          _updateTrimRangeByUI(values, baseMS);
                        });
                      },
                      onChangeEnd: (value) {
                        // トリム範囲の変更をデータベースへ保存
                        final filePath = getOpenedFileUIDPath();
                        gpsLog.saveGPSLogTrimRangeToDB(filePath);
                      },
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal:20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        // トリミング開始時間
                        Text(
                          trimStartText,
                          style: const TextStyle(fontSize: 16),
                        ),
                        // 参照先(参照していれば)
                        if(refFileName != null) refFileName,
                        // トリミング終了時間
                        Text(
                          trimEndText,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  )
                ]
              ),
            ),
            // 閉じるボタン
            floatingActionButton: makeCloseButton(),
            floatingActionButtonLocation: FloatingActionButtonLocation.miniEndTop,
          );
        }
      );
    },
    // BottomSheet の高さ
    constraints: const BoxConstraints(minHeight:85, maxHeight:85),
  );
  // 他のユーザーからのトリミング範囲の変更通知のコールバックをリセット
  bottomSheetController!.closed.whenComplete((){
    gpsLog.bottomSheetSetState = null;
    bottomSheetController = null;
  });
}

String _twoDigits(int n) {
  if (n >= 10) return "${n}";
  return "0${n}";
}

// ボトムシートの閉じるボタン
Widget? _bottomSheetCloseButton;

// ボトムシートの閉じるボタンを返す
Widget makeCloseButton()
{
  if(_bottomSheetCloseButton == null){
    _bottomSheetCloseButton = Container(
      color: Colors.brown.shade100,
      // 若干 BottomSheet より上にはみ出させる(デザイン)
      transform: Matrix4.translationValues(0, -6, 0),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.brown.shade100,
          // 角丸なし(何故か上部の角が丸くならないので…)
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          // 細めの高さに(デフォルト36px)
          minimumSize: Size(64, 30),
          maximumSize: Size(double.infinity, 30),
        ),
        // タップで BottomSheet 閉じる
        onPressed: () {
          bottomSheetController!.close();
        },
        // アイコンとテキスト
        icon: Icon(
          Icons.keyboard_double_arrow_down,
          size: 18,
        ),
        label: Text('close'),
      ),
    );
  }
  return _bottomSheetCloseButton!;
}

//----------------------------------------------------------------------------
// アニメーション用ボトムシートを開く
void showAnimationBottomSheet(BuildContext context)
{
  // トリミングされた時間範囲
  final DateTime trimStartTime = gpsLog.trimStartTime;
  final DateTime trimEndTime = gpsLog.trimEndTime;
  final int baseMS = trimStartTime.millisecondsSinceEpoch;
  final double durationSec = (trimEndTime.millisecondsSinceEpoch - baseMS) / 1000;
  
  bottomSheetController = 
    appScaffoldKey.currentState!.showBottomSheet((context)
    {
      return StatefulBuilder(
        builder: (context, StateSetter setModalState)
        {
          gpsLog.bottomSheetSetState = setModalState;

          // 現在の時間とトリミング範囲
          final DateTime currentTime = gpsLog.currentTime;
          var currentValue = 
            (currentTime.millisecondsSinceEpoch - baseMS) / 1000;
          String trimStartText =
            "${trimStartTime.hour}:" + _twoDigits(trimStartTime.minute);
          String trimEndText =
            "${trimEndTime.hour}:" + _twoDigits(trimEndTime.minute);
          String currentText =
            "${currentTime.hour}:" + _twoDigits(currentTime.minute);

          final IconData playOrPauseIcon = 
            (gpsLog.isAnimPlaying()? Icons.pause: Icons.play_arrow);

          return Scaffold(
            body: Container(
              color: Colors.brown.shade100,
              child: Row(
                children:[
                  // 左側のボタン
                  Column(
                    children: [
                      // 再生/停止ボタン
                      IconButton(
                        icon: Icon(playOrPauseIcon),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.fromLTRB(28, 12, 10, 6),
                        onPressed:(){
                          if(gpsLog.isAnimPlaying()){
                            gpsLog.stopAnim();
                          }else{
                            gpsLog.playAnim();
                          }
                        },
                      ),
                      // 先頭に巻き戻しボタン
                      IconButton(
                        icon: Icon(Icons.fast_rewind),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.fromLTRB(28, 6, 10, 6),
                        onPressed:(){
                          gpsLog.firstRewindAnim();
                        },
                      )
                    ],
                  ),
                  // 右側のスライダー
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top:15), // スライダーの上のパディング,
                      child: Column(
                        children: [
                          // トリミング範囲スライダー
                          SliderTheme(
                            data: SliderThemeData(),
                            child: Slider(
                              value: currentValue,
                              min: 0,
                              max: durationSec,
                              onChanged: (values) {
                                // 再生位置の変更
                                setModalState(() {
                                  _updateCurrentTimeByUI(values, baseMS);
                              });
                              },
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal:20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                // トリミング開始時間
                                Text(
                                  trimStartText,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                // 再生時間
                                Text(
                                  currentText,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                // トリミング終了時間
                                Text(
                                  trimEndText,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        ]
                      ),
                    ),
                  ),
                ]
              ),
            ),
            // 閉じるボタン
            floatingActionButton: makeCloseButton(),
            floatingActionButtonLocation: FloatingActionButtonLocation.miniEndTop,
          );
        }
      );
    },
    // BottomSheet の高さ
    constraints: BoxConstraints(minHeight:85, maxHeight:85),
  );
  bottomSheetController!.closed.whenComplete((){
    gpsLog.bottomSheetSetState = null;
    bottomSheetController = null;
  });
}
