import 'dart:async';   // Stream使った再描画
import 'dart:typed_data'; // Uint8List
import 'dart:convert';  // Base64
import 'dart:ui';  // lerp
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';  // GPXの読み込み
import 'package:file_selector/file_selector.dart';  // ファイル選択
import 'package:flutter_map/flutter_map.dart';  // 地図
import 'package:intl/intl.dart';  // 日時の文字列化
import 'package:firebase_storage/firebase_storage.dart';  // Cloud Storage
import 'package:cloud_firestore/cloud_firestore.dart';

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
final Map<String, GPSDeviceParam> _deviceParams = {
  "ムロ": GPSDeviceParam(
    name: "ムロ",
    color:const Color.fromARGB(255,255,0,110),
    iconImagePath: "assets/dog_icon/001.png"),
  "ロト": GPSDeviceParam(
    name: "ロト",
    color:const Color.fromARGB(255,128,0,255),
    iconImagePath: "assets/dog_icon/002.png",
    actice: false),
  "トノ": GPSDeviceParam(
    name: "トノ",
    color: const Color.fromARGB(255, 142, 85, 62),
    iconImagePath: "assets/dog_icon/004.png"),
  "ガロ": GPSDeviceParam(
    name: "ガロ",
    color:const Color.fromARGB(255,255,106,0),
    iconImagePath: "assets/dog_icon/000.png"),
  "アオ": GPSDeviceParam(
    name:"アオ",
    color:const Color.fromARGB(255,255,216,0),
    iconImagePath: "assets/dog_icon/003.png",
    actice: false),
  "ルウ": GPSDeviceParam(
    name:"ルウ",
    color:Color.fromARGB(255, 0, 255, 200),
    iconImagePath: "assets/dog_icon/005.png"),
  "予備1": GPSDeviceParam(
    name:"予備1",
    color:const Color.fromARGB(255,128,128,128),
    iconImagePath: "assets/dog_icon/998.png"),

  "パパっち": GPSDeviceParam(
    name:"パパっち",
    color:const Color.fromARGB(255,0,192,0),
    iconImagePath: "assets/member_icon/002.png",
    actice: false),
  "ママっち": GPSDeviceParam(
    name:"ママっち",
    color:const Color.fromARGB(255,0,0,240),
    iconImagePath: "assets/member_icon/000.png",
    actice: false),

  "未定義": _undefDeviceParam,
};
// 未定義のGPS端末のパラメータ
final _undefDeviceParam = GPSDeviceParam(
  name:"未定義",
  color: const Color.fromARGB(255,128,128,128),
  iconImagePath: "assets/dog_icon/999.png",
  actice: false,
);

// GPS端末IDと犬の対応(最新のデフォルト値)
// 2023-24シーズン更新済み
final Map<int, String> _defaultDeviceID2Dogs = {
  1568: "ロト",
  1674: "ムロ",
  4539: "ガロ",
  4737: "トノ",
  5674: "ルウ",
  5675: "ルウ",

  4739: "アオ",
  5218: "予備1",
  0703: "予備2",

  3993: "パパっち",
  4367: "ママっち",
};

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 犬達のログ
GPSLog gpsLog = GPSLog();

class GPSLog
{
  // デバイスIDと、デバイスのルートデータ
  Map<int, _Route> _routes = {};

  // マップ上に表示する Polyline データ配列
  List<MyPolyline> _mapLines = [];

  // マップ上に表示する犬マーカー配列
  List<Marker> _dogMarkers = [];

  // 子機のデバイスIDと犬の対応
  Map<int,String> _deviceID2Dogs = {};
  Map<int,String> get deviceID2Dogs => _deviceID2Dogs;
  
  // デバイスIDと犬の対応が更新されたか？
  bool _modifyDeviceID2Dogs = false;

  // 現在読み込んでいるログの、クラウド上のパス(ユニークID)
  String? _openedUIDPath;
  // 他のデータへの参照か？
  bool _isReferenceLink = false;
  bool get isReferenceLink => _isReferenceLink;

  //----------------------------------------------------------------------------
  // ログの登録のあるデバイスID一覧を取得
  List<int> getLoggedIDs()
  {
    List<int> ids = [];
    _routes.forEach((id, route){ ids.add(id); });
    return ids;
  }

  // デバイスIDから名前を取得
  String getID2Name(int id)
  {
    return _deviceID2Dogs[id] ?? "未定義";
  }

  // ログが空か調べる
  bool get isEmpty => _routes.isEmpty;

  //----------------------------------------------------------------------------
  // 開始時間
  DateTime _startTime = _dummyStartTime;
  DateTime get startTime => _startTime;
  DateTime _getStartTime()
  {
    if(_routes.isEmpty) return _dummyStartTime;

    // ルートから最も早い開始時間を取得
    var t = DateTime(2100); // 適当な遠い未来の時間(西暦2100年)
    _routes.forEach((id, route){
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
    if(_routes.isEmpty) return _dummyEndTime;

    // ルートから最も遅い終了時間を取得
    var t = DateTime(2000); // 適当な過去の時間(西暦2000年)
    _routes.forEach((id, route){
      if(t.isBefore(route.endTime)){
        t = route.endTime;
      }
    });
    return t;
  }

  // デバイスIDからログの開始時間を取得
  DateTime getStartTimeByID2(int id)
  {
    return _routes[id]?.startTime ?? _dummyStartTime;
  }

  //----------------------------------------------------------------------------
  // トリミング開始時間
  DateTime _trimStartTime = _dummyStartTime;
  DateTime get trimStartTime => _trimStartTime;
  void setTrimStartTime(DateTime t, { bool snapCurrentTimeIfModify = false})
  {
    var tt = t;
    tt = (tt.isAfter(_startTime)? tt: _startTime); // 開始時間より前にはしない
    tt = (tt.isBefore(_endTime)? tt: _endTime);    // 終了時間より後にはしない
    final bool modify = (_trimStartTime != tt);
    _trimStartTime = tt;

    // 指定されていたら、現在のアニメーション時間を、トリミング開始時間にする
    // もしアニメーション時間がトリミング範囲外になったら補正する
    // そうでなければ、そのまま
    final bool snap = (modify && snapCurrentTimeIfModify);
    if(_currentTime.isBefore(_trimStartTime) || snap){
      _currentTime = _trimStartTime;
    }
  }

  // トリミング終了時間
  DateTime _trimEndTime = _dummyEndTime;
  DateTime get trimEndTime => _trimEndTime;
  void setTrimEndTime(DateTime t, { bool snapCurrentTimeIfModify = false})
  {
    var tt = t;
    tt = (tt.isAfter(_startTime)? tt: _startTime); // 開始時間より前にはしない
    tt = (tt.isBefore(_endTime)? tt: _endTime);    // 終了時間より後にはしない
    final bool modify = (_trimEndTime != tt);
    _trimEndTime = tt;

    // 指定されていたら、現在のアニメーション時間を、トリミング開始時間にする
    // もしアニメーション時間がトリミング範囲外になったら補正する
    // そうでなければ、そのまま
    final bool snap = (modify && snapCurrentTimeIfModify);
    if(_trimEndTime.isBefore(_currentTime) || snap){
      _currentTime = _trimEndTime;
    }
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
  final _stream = StreamController<void>.broadcast();
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

    _routes.clear();
    _mapLines.clear();
    _dogMarkers.clear();
    _deviceID2Dogs = {..._defaultDeviceID2Dogs};
    _modifyDeviceID2Dogs = false;
  
    _thisUpdateTime = null;

    _openedUIDPath = null;
    _isReferenceLink = false;
  }

  //----------------------------------------------------------------------------
  // デバイスIDと犬の対応を読み込む
  Future<bool> loadDeviceID2DogFromDB(String fileUID, { bool recurcive=false }) async
  {
    print(">GPSLog.loadDeviceID2DogFromDB($fileUID) recurcive=$recurcive");

    //!!!! Firestore から優先的に読み込む。
    final docRef = FirebaseFirestore.instance.collection("assign").doc(fileUID);
    bool existData = false;
    try {
      final docSnapshot = await docRef.get();
      if(docSnapshot.exists){
        final data = docSnapshot.data();
        final deviceIDs = data!["gps_log"]["deviceIDs"];
        if(deviceIDs != null){
          _deviceID2Dogs.clear();
          _modifyDeviceID2Dogs = false;
          deviceIDs.forEach((key, value){
            int id = int.parse(key);
            _deviceID2Dogs[id] = value as String;
          });
          existData = true;
          print(">GPSLog.loadDeviceID2DogFromDB($fileUID) $_deviceID2Dogs");
        }
      }
    } catch(e) { /**/ }

    return existData;
  }

  //----------------------------------------------------------------------------
  // デバイスIDと犬の対応を保存
  void saveDeviceID2DogToDB(String fileUID)
  {
    //!!!!
    print(">GPSLog.saveDeviceID2DogToDB($fileUID)");

    // 変更がなければ保存しない
    if(!_modifyDeviceID2Dogs) return;
  
    try {
      Map<String,dynamic> data = {};
      _deviceID2Dogs.forEach((key, value){
        final String k = _fourDigits(key);
        data[k] = value;
      });

      //!!!! Firestore にコピーを作成(過渡期の処理。最終的には Firestore のみにする)
      final ref = FirebaseFirestore.instance.collection("assign").doc(fileUID);
      ref.update({ "gps_log.deviceIDs": data });

      print(">GPSLog.saveDeviceID2DogToDB($fileUID) $data");
    } catch(e) { /**/ }
}

  //----------------------------------------------------------------------------
  // GPXファイルからログを読み込む
  bool _addLogFromGPX(String fileContent)
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
      // 名前からデバイスID、犬名、GPS端末パラメータを取得
      int i = name.indexOf("ID_");
      int deviceId = 0;
      if(0 <= i){
        deviceId = int.tryParse(name.substring(i + 3)) ?? 0;
      }
      String dogName = getID2Name(deviceId);  // IDと犬の対応変更は、ここで反映する
      GPSDeviceParam deviceParam = _deviceParams[dogName] ?? _undefDeviceParam;
      print("name=$name, deviceId=$deviceId, dogName=$dogName, deviceParam=${deviceParam.name}");

      // 登録されているデバイスのログのみを読み込み
      if(deviceParam.name != "未定義"){
        _Route newRoute = _Route();
        bool res = newRoute.readFromGPX(rte_, deviceId, deviceParam);
        if(res){
          if(!_routes.containsKey(deviceId)){
            // 新しいログを追加
            _routes[deviceId] = newRoute;
          }else{
            // 既にあるログと結合
            _routes[deviceId]!.merge(newRoute);
          }
          addCount++;
        }
      }
    });

    if(0 < addCount){
      // 全体の開始終了時間を更新
      _startTime = _getStartTime();
      _endTime = _getEndTime();
      // トリミングが未設定の場合、トリム時間を新しい範囲に合わせる
      // NOTE: トリミングが設定されている場合には、それを維持する意味
      if(!changeTrimSrart) _trimStartTime = _startTime;
      if(!changeTrimEnd)  _trimEndTime = _endTime;
      // 再生時間をトリム範囲に維持する
      setCurrentTime(_currentTime);
    }
  
    return true;
  }

  // GPXへ変換
  String exportGPX()
  {
    // ヘッダ
    String gpx = '<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1">\n';

    // デバイス毎
    _routes.forEach((id, route){
      gpx += route.exportGPX();
    });

    // フッダー
    gpx += '</gpx>\n';

    return gpx;
  }

  // 子機のデバイスIDと犬の対応を設定
  bool changeDeviceID2DogName(int id, String name)
  {
    // GPS端末に登録されてい名前でなければ何もしない
    // 表示されているデバイスIDでなければ何もしない
    if(!_deviceID2Dogs.containsKey(id) ||
       !_deviceParams.containsKey(name) ||
       !_routes.containsKey(id)){
      print(">GPSLog.changeDeviceID2DogName($id, $name) failed.");
      return false;
    }
  
    _deviceID2Dogs[id] = name;
    _routes[id]!.changeDeviceParam(_deviceParams[name]!);
    _modifyDeviceID2Dogs = true;

    return true;
  }

  // ログを削除
  void deleteLog(int id)
  {
    // 指定されたデバイスIDのルートを削除
    if(_routes.containsKey(id)){
      _routes.remove(id);
    }
    // 空になったらクラウドストレージ上のファイルを削除
    if(_routes.isEmpty && ((_openedUIDPath ?? "") != "")){
      deleteFromCloudStorage(_openedUIDPath!);
      clear();
    }
  }

  //----------------------------------------------------------------------------
  // クラウドストレージ
  static Reference _getRef(String path)
  {
    if(path[0] == "/") path = path.substring(1);
    final String storagePath = path + ".gpx";
    return FirebaseStorage.instance.ref().child(storagePath);
  }

  static Reference _getDirRef(String path)
  {
    if(path[0] == "/") path = path.substring(1);
    final String storagePath = path;
    return FirebaseStorage.instance.ref().child(storagePath);
  }

  // 取得しているデータの更新日時
  DateTime? _thisUpdateTime;

  // クラウドストレージにアップロード
  Future<bool> uploadToCloudStorage(String path) async
  {
    //!!!!
    print(">GPSLog.uploadToCloudStorage($path)");

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
    } catch (e) {
      print(">GPSLog.uploadToCloudStorage($path) GPS Log couldn't be uploaded.");
      res = false;
    }

    // 成功していたらパスを記録
    if(res){
      _openedUIDPath = path;
    }
  
    //!!!!
    print("GPSLog.uploadToCloudStorage($path) res=$res");

    return res;
  }

  // クラウドストレージからダウンロード
  Future<bool> downloadFromCloudStorage(String path, bool referenceLink) async
  {
    //!!!!
    print(">GPSLog.downloadFromCloudStorage($path)");

    // ストレージ上のファイルパスを参照
    final gpxRef = _getRef(path);

    // GPXから読み込み
    bool res = false;
    try {
      final Uint8List? data = await gpxRef.getData();
      res = (data != null);
      // デバイスIDと犬の対応表も読み込む(_addLogFromGPX() より前で)
      if(res){
        final fileUID = path.split("/").last;
        await loadDeviceID2DogFromDB(fileUID);
      }
      if(res){
        var gpxText = utf8.decode(data);
        res = _addLogFromGPX(gpxText);
      }
      if(res){
        FullMetadata meta = await gpxRef.getMetadata();
        _thisUpdateTime = meta.updated;
      }
    } catch (e) {
      print(">GPSLog.downloadFromCloudStorage($path) GPS Log couldn't be downloaded.");
      res = false;
    }

    // 成功していたらパスを記録
    if(res){
      _openedUIDPath = path;
      _isReferenceLink = referenceLink;
    }

    //!!!!
    print(">GPSLog.downloadFromCloudStorage($path) $res");

    return res;
  }

  // クラウドストレージから削除
  static void deleteFromCloudStorage(String path)
  {
    //!!!!
    print(">GPSLog.deleteFromCloudStorage(${path})");

    // ストレージ上のファイルパスを参照
    final gpxRef = _getRef(path);
    try {
      gpxRef.delete();
    } catch(e){ /**/ }
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
    } catch(e) { /**/ }
    if(cloudUpdateTime == null) return false;

    // クラウド上にデータがあって、ローカルが空なら、必ず true になる。
    if(_thisUpdateTime == null){
      return true;
    }

    // クラウドとローカルの両方にデータがあれば、比較
    // クラウドのほうが新しければ true を返す
    return (_thisUpdateTime!.compareTo(cloudUpdateTime!) < 0);
  }

  // クラウドストレージから、ディレクトリにあるファイルの一覧を取得
  Future<List<String>> getFileList(String path) async
  {
    //!!!!
    print(">GPSLog.getFileList(${path})");

    final dirRef = _getDirRef(path);
    final list = await dirRef.listAll();
    List<String> fileList = [];
    list.items.forEach((var item){
      fileList.add(item.name);
    });
    return fileList;
  }

  // 配置データから、GPSログ関連のデータを削除
  void deleteFromAssignData(String thisUIDPath)
  {
    print(">GPSLog.deleteFromAssignData(${thisUIDPath})");

    // Firestore から削除
    final dbDocId = thisUIDPath.split("/").last;
    final ref = FirebaseFirestore.instance.collection("assign").doc(dbDocId);
    ref.update({ "gps_log": FieldValue.delete() });
  }

  //----------------------------------------------------------------------------
  // 読み込んでいるログのクラウド上のパスを取得(ユニークID)
  String? getOpenedPath()
  {
    return _openedUIDPath;
  }

  //----------------------------------------------------------------------------
  // 他のデータを参照
  void saveReferencePath(String thisUIDPath, String refUIDPath)
  {
    print(">GPSLog.saveReferencePath($thisUIDPath) -> $refUIDPath");
  
    // Firestore に保存
    final dbDocId = thisUIDPath.split("/").last;
    final docRef = FirebaseFirestore.instance.collection("assign").doc(dbDocId);
    docRef.update({ "gps_log.referencePath": refUIDPath });
  }

  // 読み込むべきデータのパスを取得
  // 他のデータを参照していれば、そちらのパスを返す
  Future<String> getReferencePath(String thisUIDPath) async
  {
    print(">GPSLog.getReferencePath($thisUIDPath)");

    // Firestore から読み込む
    final dbDocId = thisUIDPath.split("/").last;
    final docRef = FirebaseFirestore.instance.collection("assign").doc(dbDocId);
    String? refUIDPath;
    try {
      final docSnapshot = await docRef.get();
      if(docSnapshot.exists){
        final data = docSnapshot.data();
        refUIDPath = data!["gps_log"]["referencePath"];
      }
    } catch(e) { /**/ }

    // 他のデータへの参照がなければ、自分のパスを返す
    refUIDPath ??= thisUIDPath;
  
    print(">GPSLog.getReferencePath($thisUIDPath) -> $refUIDPath");

    return refUIDPath;
  }

  //----------------------------------------------------------------------------
  // トリミング範囲
  void Function(void Function())? bottomSheetSetState;

  void saveGPSLogTrimRangeToDB(String fileUID)
  {
    print(">GPSLog.saveGPSLogTrimRangeToDB($fileUID)");

    // Firestore に保存
    final docRef = FirebaseFirestore.instance.collection("assign").doc(fileUID);
    docRef.update({
      "gps_log.trimStartTime": _trimStartTime.toIso8601String(),
      "gps_log.trimEndTime": _trimEndTime.toIso8601String(),
    });
  }

  Future<void> loadGPSLogTrimRangeFromDB(String fileUID, { bool recurcive=false }) async
  {
    print(">GPSLog.loadGPSLogTrimRangeFromDB($fileUID), recurcive=$recurcive");

    // Firestore から読み込む
    final docRef = FirebaseFirestore.instance.collection("assign").doc(fileUID);
    bool existData = false;
    try {
      final docSnapshot = await docRef.get();
      if(docSnapshot.exists){
        final data = docSnapshot.data();
        final start = DateTime.parse(data!["gps_log"]["trimStartTime"]!);
        final end = DateTime.parse(data!["gps_log"]["trimEndTime"]!);
        setTrimStartTime(start);
        setTrimEndTime(end);
        existData = true;
        // 描画
        gpsLog.makePolyLines();
        gpsLog.makeDogMarkers();
        gpsLog.redraw();
      }
    } catch(e) { /**/ }
  }

  //----------------------------------------------------------------------------
  // FlutterMap用のポリラインを作成

  // 表示/非表示フラグ
  bool showLogLine = true;

  List<MyPolyline> makePolyLines()
  {
    _mapLines.clear();
    if(showLogLine){
      _routes.forEach((id, route){
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
      _routes.forEach((id, route){
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
    this.actice = true,
  });
  // 犬の名前
  String name;
  // ラインカラー
  Color color;
  // アイコン用画像
  String iconImagePath;
  // 現役か？(犬選択ダイアログに表示するか)
  bool actice;
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 一頭のルート
class _Route
{
  // 通過点リスト
  List<_Point> _points = [];
  // ID(nameに書かれている端末ID)
  int _deviceId = 0;
  // パスの描画用パラメータ
  // NOTE: ログファイルには保存されない
  var _deviecParam = GPSDeviceParam(
    name: "",
    color: const Color.fromARGB(255,128,128,128));
  // アイコンイメージ
  // NOTE: ログファイルには保存されない
  Image? _iconImage;

  //----------------------------------------------------------------------------
  // パスの描画用パラメータ(犬情報)を変更
  void changeDeviceParam(GPSDeviceParam param)
  {
    _deviecParam = param;
    _iconImage = null;
  }

  //----------------------------------------------------------------------------
  // 開始時間
  DateTime get startTime =>
    (_points.isNotEmpty? _points.first.time: _dummyStartTime);
  // 終了時間
  DateTime get endTime =>
    (_points.isNotEmpty? _points.last.time: _dummyEndTime);

  // トリミングに対応した開始インデックス
  int _trimStartIndex = -1;
  DateTime _trimStartCache = DateTime(2022);
  // トリミングに対応した終了インデックス
  int _trimEndIndex = -1;
  DateTime _trimEndCache = DateTime(2022);

  //----------------------------------------------------------------------------
  // GPXファイルからログを作成
  bool readFromGPX(XmlElement rte_, int deviceId, GPSDeviceParam deviecParam)
  {
    _deviceId = deviceId;
    _deviecParam = deviecParam;
    
    // ルートの通過ポイントを読み取り
    bool ok = true;
    final Iterable<XmlElement> rtepts_ = rte_.findElements("rtept");
    for(final pt in rtepts_){
      final String? lat = pt.getAttribute("lat");
      final String? lon = pt.getAttribute("lon");
      final XmlElement? time = pt.getElement("time");
      ok = (lat != null) && (lon != null) && (time != null);
      if(ok){
        try {
          // 時間はUTCから日本時間に変換しておく
          final dateTime = DateTime.parse(time.text).toLocal();
          _points.add(_Point(
            LatLng(double.parse(lat), double.parse(lon)),
            dateTime));
        }catch(e){
          ok = false;
        }
      }
      if(!ok) break;
    }

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
    const distance = Distance();
    while(seek < _points.length)
    {
      // 直前の通過ポイントから、5[m]以上離れているか、60[秒]以上経過していれば採用
      final pt0 = _points[prev]; 
      final pt1 = _points[seek]; 
      final D = distance(pt0.pos, pt1.pos);
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
  // NOTE: time はトリム範囲内であることを前提とする
  LatLng calcPositionAtTime(DateTime time)
  {
    final int t = time.millisecondsSinceEpoch;

    // トリム範囲がデータの範囲外の場合は、先頭か終端の座標を返す
    if(_trimStartIndex == _trimEndIndex){
      if(_trimStartIndex == 0){
        return _points.first.pos;
      }else{
        return _points.last.pos;
      } 
    }

    // データの範囲外なら、先頭か終端の座標を返す
    var firstPointMs = _points[_trimStartIndex].time.millisecondsSinceEpoch;
    if(t <= firstPointMs) return _points[_trimStartIndex].pos;

    var lastPointMs = _points[max(0, _trimEndIndex-1)].time.millisecondsSinceEpoch;
    if(lastPointMs <= t) return _points[max(0, _trimEndIndex-1)].pos;
  
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

      if(isEqualBefore(trimEnd, _points.first.time)){
        // トリム範囲がログの範囲より前なら、最初のポイントのみ
        _trimStartIndex = 0;
        _trimEndIndex = 0;
      }else if(isEqualBefore(_points.last.time, trimStart)){
        // トリム範囲がログの範囲より後ろなら、最後のポイントのみ
        _trimStartIndex = _points.length;
        _trimEndIndex = _points.length;
      }else{
        // トリム範囲に含まれるポイントの範囲を探す
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
    }
    // キャッシュされた範囲でポリラインを作成
    List<LatLng> line = [];
    for(int i = _trimStartIndex; i < _trimEndIndex; i++){
      line.add(_points[i].pos);
    }
    return MyPolyline(
      points:line,
      color:_deviecParam.color,
      strokeWidth:2.0,
      startCapMarker:true,
      endCapMarker:true,
      shouldRepaint:true);
  }

  // FlutterMap用の犬マーカーを作成
  Marker? makeDogMarker(DateTime time)
  {
    // アイコン画像を読み込んでおく
    _iconImage ??= Image.asset(_deviecParam.iconImagePath);
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
Future<bool> _readGPSLogFromLocalFile(BuildContext context) async
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
  final bool res = gpsLog._addLogFromGPX(fileContent);
  if(!res) return false;

  return true;
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// GPSメニュー用のポップアップメニューを開く
void showGPSLogPopupMenu(BuildContext context)
{
  // メニューの座標
  final double x = getScreenWidth();  // 画面右寄せ
  final double y = 60;

  // Note: アイコンカラーは ListTile のデフォルトカラー合わせ
  showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(x, y, x, y),
    elevation: 8.0,
    items: [
      makePopupMenuItem(
        0, "ログ読み込み", Icons.file_open, 
        enabled:(!lockEditing && !gpsLog.isReferenceLink)),

      if(!gpsLog.isReferenceLink) makePopupMenuItem(
        1, "ログ参照", Icons.link, enabled:!lockEditing),
      if(gpsLog.isReferenceLink) makePopupMenuItem(
        2, "ログ参照の解除", Icons.link_off, enabled:!lockEditing),

      makePopupMenuItem(
        3, "ログトリミング", Icons.content_cut, enabled:!lockEditing),
      makePopupMenuItem(
        4, "アニメーション", Icons.play_circle),
      makePopupMenuItem(
        5, "ログ/子機編集", Icons.pets,
        enabled:(!lockEditing && !gpsLog.isReferenceLink)),
      makePopupMenuItem(
        6, "キルマーカー", Icons.pin_drop, enabled:!lockEditing),
    ],
  ).then((value) async {
    switch(value ?? -1){
    case 0: // GPSログの読み込み
      _loadGPSLogFromLocalFileFunc(context);
      break;

    case 1: // ログ参照
      _linkGPSLogFunc(context);
      break;
    case 2: // ログ参照の解除
      gpsLog.stopAnim();
      final filePath = getOpenedFileUIDPath();
      gpsLog.deleteFromAssignData(filePath);
      gpsLog.clear();
      gpsLog.redraw();
      break;

    case 3: // トリミング
      // アニメーション停止
      gpsLog.stopAnim();
      showTrimmingBottomSheet(context);
      break;
    
    case 4: // アニメーション
      showAnimationBottomSheet(context);
      break;
    
    case 5: // 編集
      _showDogIDDialog(context);
      break;

    case 6: // キルマーカー
      addKillMarkerFunc(context);
      break;
    }
  });
}

//----------------------------------------------------------------------------
// GPSログ読み込み
void _loadGPSLogFromLocalFileFunc(BuildContext context) async
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
    // 開いているファイルのGPSログの有無フラグを更新
    setOpenedFileGPSLogFlag(true);
    return;
  }

  bool res = await _readGPSLogFromLocalFile(context);
  // 読み込み成功したらマップを再描画
  if(res){
    gpsLog.makePolyLines();
    gpsLog.makeDogMarkers();
    gpsLog.redraw();
    showTextBallonMessage("GPSログの読み込み成功");
    // 裏でクラウドストレージへのアップロードを実行
    gpsLog.uploadToCloudStorage(gpsLogPath);
    // デバイスIDと犬の対応を保存
    // NOTE: シーズンによって犬が使う子機が変わることがある
    // _defaultDeviceID2Dogs は、シーズンで変わる可能性があるので、ログ作成時の状態を保存する
    final fileUID = gpsLogPath.split("/").last;
    gpsLog.saveDeviceID2DogToDB(fileUID);
    // 開いているファイルのGPSログの有無フラグを更新
    setOpenedFileGPSLogFlag(true);
  }else{
    showTextBallonMessage("GPSログの読み込み失敗");
  }
}

//----------------------------------------------------------------------------
// GPSログ参照
void _linkGPSLogFunc(BuildContext context) async
{
  // アニメーション停止
  gpsLog.stopAnim();
  // BottomSheet を閉じる
  closeBottomSheet();
  // ファイル一覧画面に遷移して、ファイルの切り替え
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => FilesPage(
      referGPSLogMode: true,  // GPSログ参照モード
      readOnlyMode: true,

      onSelectFile: (refUIDPath) async {
        //!!!!
        print("_linkGPSLogFunc.onSelectFile($refUIDPath)");

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
  miscMarkers.addMarker(MiscMarker(position:mainMapController!.center));
  // 再描画
  updateMapView();
}

//----------------------------------------------------------------------------
// トリム範囲の更新と再描画
void _updateTrimRangeByUI(RangeValues values, int baseMS)
{
  final int trimStartMS = baseMS + (values.start.toInt() * 1000);
  gpsLog.setTrimStartTime(
    DateTime.fromMillisecondsSinceEpoch(trimStartMS),
    snapCurrentTimeIfModify:true);

  final int trimEndMS = baseMS + (values.end.toInt() * 1000);
  gpsLog.setTrimEndTime(
    DateTime.fromMillisecondsSinceEpoch(trimEndMS),
    snapCurrentTimeIfModify:true);

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
          if(gpsLog.isReferenceLink){
            final uidPath = gpsLog.getOpenedPath();
            if(uidPath != null){
              final uid = uidPath.split("/").last;
              final fileName = convertUID2Name(uid);
              refFileName = Row(children:[
                const Text("["),
                const Icon(Icons.link, size:20),
                Text(
                  " $fileName]",
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
                        gpsLog.saveGPSLogTrimRangeToDB(openedFileUID.toString());
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

String _fourDigits(int n)
{
  return n.toString().padLeft(4, '0');
}

String _twoDigits(int n)
{
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

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 子機IDダイアログ
class _DogIDDialog extends StatefulWidget
{
  _DogIDDialog();

  @override
  _DogIDDialogState createState() => _DogIDDialogState();
}

class _DogIDDialogState extends State<_DogIDDialog>
{
  @override
  Widget build(BuildContext context)
  {
    List<Container> dogs = [];
    final List<int> loggedIDs = gpsLog.getLoggedIDs();
    final DateFormat dateFormat = DateFormat(" yyyy-MM-dd");
    loggedIDs.forEach((id){
      final String dogName = gpsLog.getID2Name(id);
      final DateTime time = gpsLog.getStartTimeByID2(id);
      final GPSDeviceParam param = _deviceParams[dogName] ?? _undefDeviceParam;
      dogs.add(Container(
        height: 55,
        width: 320,
        child: ListTile(
          // 犬アイコン
          leading: IconButton(
            icon: Image.asset(param.iconImagePath),
            padding: const EdgeInsets.all(0),
            iconSize: 48,
            onPressed: () async {
              final changeName = await _showDogSelectDialog(context,
                title: "犬の変更(ID:$id $dogName)", excludeName: dogName);
              if(changeName != null){
                setState((){
                  gpsLog.changeDeviceID2DogName(id, changeName);
                });
                // 描画
                gpsLog.makePolyLines();
                gpsLog.makeDogMarkers();
                gpsLog.redraw();
                // 保存
                gpsLog.saveDeviceID2DogToDB(openedFileUID.toString());
              }
            },
          ),
          // 犬名とログの年月日
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dogName),
              Text(" ID:" + _fourDigits(id) + dateFormat.format(time)),
            ]),
          // 削除ボタン
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: (){
              onDeleteButton(context, id, dogName);
            },
          ),
          onTap: (){
          },
        ),
      ));
    });
    if(dogs.isEmpty){
      dogs.add(Container(
        height: 55,
        width: 320,
        child: ListTile(
          title: Text("(ログ登録なし)"),
          onTap: (){},
        ),
      ));
    }
  
    // ダイアログ表示
    return WillPopScope(
      // ページの戻り値
      onWillPop: (){
        Navigator.of(context).pop(false);
        return Future.value(false);
      },
      child: SimpleDialog(
        // ヘッダ部
        title: Text("ログ/子機編集"),
        // 犬一覧
        children: dogs,
      )
    );
  }

  // ログの削除ボタン
  void onDeleteButton(BuildContext context, int id, String name)
  {
    String text = "ID:" + _fourDigits(id) + " " + name + "のログを削除します。";
    showOkCancelDialog(context, title:"ログの削除", text:text).then((res) async {
      if(res ?? false){
        // デバイスIDを指定してログを削除
        gpsLog.deleteLog(id);

        // マップ上のログを再描画
        gpsLog.makePolyLines();
        gpsLog.makeDogMarkers();
        gpsLog.redraw();
        // ダイアログを再描画
        setState((){});

        // クラウドストレージにアップロード
        final filePath = getOpenedFileUIDPath();
        if(!gpsLog.isEmpty){
          final String gpsLogPath = await gpsLog.getReferencePath(filePath);
          gpsLog.uploadToCloudStorage(gpsLogPath);
        }
        // クラウドストレージからログが削除されたら、GPSログの有無フラグを更新
        // 同時に、配置データからGPSログ関連のデータを削除
        if(gpsLog.isEmpty){
          setOpenedFileGPSLogFlag(false);
          gpsLog.deleteFromAssignData(filePath);
        }
      }
    });
  }
}

Future<bool?> _showDogIDDialog(BuildContext context)
{
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context){
      return _DogIDDialog();
    },
  );
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 犬選択ダイアログ
class _DogSelectDialog extends StatelessWidget
{
  _DogSelectDialog({
    required this.title,
    this.excludeName = "",
  });

  final String title;
  final String excludeName;

  @override
  Widget build(BuildContext context)
  {
    List<Container> dogs = [];
    _deviceParams.forEach((name, param){
      // 現役の犬のみを表示
      if(!param.actice) return;
      // 指定された犬は除外
      if(name == excludeName) return;

      dogs.add(Container(
        height: 55,
        width: 200,
        child: ListTile(
          // 犬アイコン
          leading: Image.asset(param.iconImagePath),
          // 犬名
          title: Text(name),
          onTap: (){
            Navigator.pop(context, name);
          },
        ),
      ));
    });
  
    // ダイアログ表示
    return SimpleDialog(
      // ヘッダ部
      title: Text(title),
      // 犬一覧
      children: dogs,
    );
  }
}

// ダイアログを表示
Future<String?> _showDogSelectDialog(
  BuildContext context, { required String title, String excludeName="" })
{
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return _DogSelectDialog(title:title, excludeName:excludeName);
    },
  );
}
