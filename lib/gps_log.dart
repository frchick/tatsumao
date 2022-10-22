import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';  // GPXの読み込み
import 'package:file_selector/file_selector.dart';  // ファイル選択
import 'package:flutter_map/flutter_map.dart';  // 地図
import 'package:intl/intl.dart';  // 日時の文字列化
import 'globals.dart';  // 画面解像度

// ログデータがないときに使う、ダミーの開始終了時間
final DateTime _dummyStartTime = DateTime(2022, 1, 1, 7);  // 2022/1/1 AM7:00
final DateTime _dummyEndTime = DateTime(2022, 1, 1, 11);  // 2022/1/1 AM11:00

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 犬達のログ
class GPSLog
{
  List<_Route> routes = [];

  // 開始時間
  DateTime _startTime = _dummyStartTime;
  DateTime get startTime => _startTime;
  DateTime _getStartTime()
  {
    if(routes.isEmpty) return _dummyStartTime;

    DateTime t = routes[0].startTime;
    routes.forEach((route){
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

    DateTime t = routes[0].endTime;
    routes.forEach((route){
      if(route.endTime.isAfter(t)){
        t = route.endTime;
      }
    });
    return t;
  }

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

  // リセット
  void clear()
  {
    _startTime = _trimStartTime = _dummyStartTime;
    _endTime = _trimEndTime = _dummyEndTime;
    routes.clear();
  }

  // GPXファイルからログを読み込む
  bool addLogFromGPX(String fileContent)
  {
    _Route newRoute = _Route();
    bool res = newRoute.readFromGPX(fileContent);
    if(res){
      // トリムが設定されているかをチェック
      final bool changeTrimSrart = (_startTime != _trimStartTime);
      final bool changeTrimEnd = (_endTime != _trimEndTime);
      //!!!!
      print("changeTrimSrart=${changeTrimSrart}, changeTrimEnd=${changeTrimEnd}");

      // 新しいログを追加
      routes.add(newRoute);
      _startTime = _getStartTime();
      _endTime = _getEndTime();

      // トリム時間を新しい範囲に合わせる(トリムの設定がない場合のみ)
      if(!changeTrimSrart) _trimStartTime = _startTime;
      if(!changeTrimEnd)  _trimEndTime = _endTime;
    }
    return res;
  }

  // FlutterMap用のポリラインを作成
  List<Polyline> makePolyLines()
  {
    //!!!!
    print("GPSLog.makePolyLines() !!!!");
  
    List<Polyline> lines = [];
    routes.forEach((route){
      lines.add(route.makePolyLine());
    });
    return lines;
  }
}

GPSLog gpsLog = GPSLog();

//----------------------------------------------------------------------------
// 一頭のルート
class _Route
{
  // 通過点リスト
  List<_Point> points = [];
  // 端末名
  String name = "";

  // 開始時間
  DateTime get startTime =>
    (0 < points.length)? points.first.time: _dummyStartTime;
  // 終了時間
  DateTime get endTime =>
    (0 < points.length)? points.last.time: _dummyEndTime;

  // GPXファイルからログを作成
  bool readFromGPX(String fileContent)
  {
    // XMLパース
    final XmlDocument gpxDoc = XmlDocument.parse(fileContent);

    final XmlElement? gpx_ = gpxDoc.getElement("gpx");
    if(gpx_ == null) return false;
    final XmlElement? rte_ = gpx_.getElement("rte");
    if(rte_ == null) return false;

    final XmlElement? name_ = rte_.getElement("name");
    if(name_ == null) return false;
    name = name_.text;

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
        
        points.add(_Point(
          LatLng(double.parse(lat), double.parse(lon)),
          dateTime));
      }else{
        ok = false;
        return;
      }
    });

    // なんらか失敗していたらデータを破棄
    if(!ok){
      points.clear();
    }
  
    return ok;
  }

  // FlutterMap用のポリラインを作成
  Polyline makePolyLine()
  {
    List<LatLng> line = [];
    points.forEach((pt){
      line.add(pt.pos);
    });
    return Polyline(points:line);
  }
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

  // メッセージを表示
  final String message = "GPSログの読み込み成功";
  await showDialog(
    context: context,
    builder: (_){ return AlertDialog(content: Text(message)); });

  return true;
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// GPSメニュー用のポップアップメニューを開く
void showGPSLogPopupMenu(BuildContext context, Function rebuildMapView)
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
        rebuildMapView();
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
}

//----------------------------------------------------------------------------
// トリミング用ボトムシートを開く
void showTrimmingBottomSheet(BuildContext context)
{
  // ログ全体の時間範囲
  final int baseMS = gpsLog.startTime.millisecondsSinceEpoch;
  final double durationSec = (gpsLog.endTime.millisecondsSinceEpoch - baseMS) / 1000;

  // メンバー一覧メニューを開く
  showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext context)
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
          String trimStartTimeText = DateFormat('hh:mm').format(trimStartTime);
          String trimEndTimeText = DateFormat('hh:mm').format(trimEndTime);

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
                        trimStartTimeText,
                        style: const TextStyle(fontSize: 16),
                      ),
                      Text(
                        trimEndTimeText,
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
    }
  );
}