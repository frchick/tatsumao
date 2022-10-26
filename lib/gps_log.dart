import 'dart:async';   // Stream使った再描画
import 'dart:typed_data'; // Uint8List
import 'dart:convert';  // Base64

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';  // GPXの読み込み
import 'package:file_selector/file_selector.dart';  // ファイル選択
import 'package:flutter_map/flutter_map.dart';  // 地図
import 'package:intl/intl.dart';  // 日時の文字列化
import 'package:firebase_storage/firebase_storage.dart';  // Cloud Storage

import 'file_tree.dart';
import 'text_ballon_widget.dart';
import 'globals.dart';  // 画面解像度

// ログデータがないときに使う、ダミーの開始終了時間
final _dummyStartTime = DateTime(2022, 1, 1, 7);  // 2022/1/1 AM7:00
final _dummyEndTime = DateTime(2022, 1, 1, 11);  // 2022/1/1 AM11:00

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 犬達のログ
GPSLog gpsLog = GPSLog();

class GPSLog
{
  Map<int, _Route> routes = {};
  List<Polyline> _mapLines = [];

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
  set trimStartTime(DateTime t) =>
    _trimStartTime = (t.isAfter(_startTime)? t: _startTime);

  // トリミング終了時間
  DateTime _trimEndTime = _dummyEndTime;
  DateTime get trimEndTime => _trimEndTime;
  set trimEndTime(DateTime t) =>
    _trimEndTime = (t.isBefore(_endTime)? t: _endTime);

  // GPS端末のパラメータ
  final Map<int, GPSDeviceParam> deviceParams = {
    1568: GPSDeviceParam(name:"ムロ", color:Color.fromARGB(255,255,0,110)),
    1674: GPSDeviceParam(name:"ロト", color:Color.fromARGB(255,128,0,255)),
    4539: GPSDeviceParam(name:"ガロ", color:Color.fromARGB(255,255,106,0)),
    4739: GPSDeviceParam(name:"マナミ", color:Color.fromARGB(255,255,216,0)),
  };

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
    routes.clear();
    _mapLines.clear();
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
    } on FirebaseException catch (e) {
      res = false;
    } on Exception catch (e) {
      res = false;
    }

    //!!!!
    print("uploadToCloudStorage() res=${res}");

    return res;
  }

  // クラウドストレージからダウンロード
  Future<bool> downloadFromCloudStorage(String path) async
  {
    //!!!!
    print("downloadFromCloudStorage(${path})");

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
    } on FirebaseException catch (e) {
      res = false;
    } on Exception catch (e) {
      res = false;
    }

    //!!!!
    print("downloadFromCloudStorage() res=${res}");

    return res;
  }

  // クラウドストレージから削除
  static void deleteFromCloudStorage(String path)
  {
    // ストレージ上のファイルパスを参照
    final gpxRef = _getRef(path);
    gpxRef.delete();
  }

  //----------------------------------------------------------------------------
  // FlutterMap用のポリラインを作成
  List<Polyline> makePolyLines()
  {
    _mapLines.clear();
    routes.forEach((id, route){
      _mapLines.add(route.makePolyLine(_trimStartTime, _trimEndTime));
    });
    return _mapLines;
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
  });
  // 犬の名前
  String name;
  // ラインカラー
  Color color;
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
  // FlutterMap用のポリラインを作成
  Polyline makePolyLine(DateTime trimStart, DateTime trimEnd)
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
      gpsLog.deviceParams[_deviceId]?.color ??
      const Color.fromARGB(255,128,128,128);

    return Polyline(
      points:line,
      color:color,
      strokeWidth:2.0);
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
      PopupMenuItem(
        value: 0,
        child: Row(
          children: [
            Icon(Icons.file_open, color: Colors.black45),
            const SizedBox(width: 5),
            const Text('ログ読み込み'),
          ]
        ),
        height: (kMinInteractiveDimension * 0.8),
      ),
      PopupMenuItem(
        value: 1,
        child: Row(
          children: [
            Icon(Icons.content_cut, color: Colors.black45),
            const SizedBox(width: 5),
            const Text('トリミング'),
          ]
        ),
        height: (kMinInteractiveDimension * 0.8),
      ),
    ],
  ).then((value) async {
    switch(value ?? -1){
    case 0: // GPSログの読み込み
      bool res = await readGPSLog(context);
      // 読み込み成功したらマップを再描画
      if(res){
        gpsLog.makePolyLines();
        gpsLog.redraw();
        showTextBallonMessage("GPSログの読み込み成功");
        // 裏でクラウドストレージへのアップロードを実行
        final String filePath = getCurrentFilePath();
        gpsLog.uploadToCloudStorage(filePath);
      }else{
        showTextBallonMessage("GPSログの読み込み失敗");
      }
      break;

    case 1: // トリミング
      showTrimmingBottomSheet(context);
      break;
    }
  });
}

//----------------------------------------------------------------------------
void _updateTrimRange(RangeValues values, int baseMS)
{
  final int trimStartMS = baseMS + (values.start.toInt() * 1000);
  gpsLog.trimStartTime = DateTime.fromMillisecondsSinceEpoch(trimStartMS);

  final int trimEndMS = baseMS + (values.end.toInt() * 1000);
  gpsLog.trimEndTime = DateTime.fromMillisecondsSinceEpoch(trimEndMS);

  // 描画
  gpsLog.makePolyLines();
  gpsLog.redraw();
}

//----------------------------------------------------------------------------
// トリミング用ボトムシートを開く
void showTrimmingBottomSheet(BuildContext context)
{
  // ログ全体の時間範囲
  final int baseMS = gpsLog.startTime.millisecondsSinceEpoch;
  final double durationSec = (gpsLog.endTime.millisecondsSinceEpoch - baseMS) / 1000;
  
  appScaffoldKey.currentState!.showBottomSheet((context)
  {
    return StatefulBuilder(
      builder: (context, StateSetter setModalState)
      {
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

        return Container(
          height: 80,
          color: Colors.brown.shade100,
          child: Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                ),
                child: RangeSlider(
                  values: rangeValues,
                  min: 0,
                  max: durationSec,
                  onChanged: (values) {
                    setModalState(() => _updateTrimRange(values, baseMS));
                  },
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal:20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      trimStartText,
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      trimEndText,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              )
            ]
          ),
        );
      }
    );
  });
}

String _twoDigits(int n) {
  if (n >= 10) return "${n}";
  return "0${n}";
}