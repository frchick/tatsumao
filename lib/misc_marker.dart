import 'package:flutter/material.dart';
import 'dart:async';  // データベースの同期
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'mydragmarker.dart';
import 'globals.dart';

//-----------------------------------------------------------------------------

MiscMarkers miscMarkers = MiscMarkers();

// アイコン
class _MiscMarkerIcon
{
  _MiscMarkerIcon({ required this.path });

  // パス
  final String path;
  // アイコン画像
  Image? image;
}
List<_MiscMarkerIcon> _icons = [
  _MiscMarkerIcon(path:"assets/misc/deer_icon0.png"), // index = 0
  _MiscMarkerIcon(path:"assets/misc/deer_icon1.png"),
  _MiscMarkerIcon(path:"assets/misc/deer_icon2.png"),
];

const double _iconWidth = 56;
const double _iconHeight = 56;

//-----------------------------------------------------------------------------
// 汎用マーカーのデータ
class MiscMarker
{
  MiscMarker({ required this.position, this.iconType=0, this.memo="" });

  // 座標
  LatLng position;
  // アイコンタイプ
  int iconType;
  // メモ
  String memo;

  // データが有効か？
  bool get ok => ((position.latitude != 0) && (position.longitude != 0));

  // マーカーの build に渡された BuildContext
  BuildContext? _context;

  // データベースに保存する用のMapデータを取得
  Map<String, dynamic> toMapData()
  {
    return {
      "latitude": position.latitude,
      "longitude": position.longitude,
      "iconType": iconType,
      "memo": memo,
    };
  }

  // データベースに保存されたMapデータから読み込み
  factory MiscMarker.fromMapData(Map<String,dynamic> map)
  {
    try {
      double latitude = map["latitude"] as double;
      double longitude = map["longitude"] as double;
      final position = LatLng(latitude, longitude);
      final iconType = map["iconType"] as int;
      final memo = map["memo"] as String;
      return MiscMarker(position: position, iconType: iconType, memo: memo);
    } catch(e) {
      return MiscMarker(position: LatLng(0,0));
    }
  }

  // マップ上に表示する用のマーカーを作成
  MyDragMarker makeMapMarker(int index)
  {
    //!!!!
    print(">MiscMarker.makeMapMarker(${index})");

    return MyDragMarker(
      point: position,
      builder: (cnx) {
        _context = cnx;
        return _icons[iconType].image!;
      },
      width: _iconWidth,
      height: _iconHeight,
      offset: Offset(0.0, _iconHeight/2),
      feedbackOffset: Offset(0.0, _iconHeight/2),
      index: index,
      onDragEnd: onMapMarkerDragEnd,
      onTap: (LatLng position, int index){
        if(_context != null){
          miscMarkers.onMapMarkerTap(_context!, position, index);
        }
      },
    );
  }


  LatLng onMapMarkerDragEnd(DragEndDetails detail, LatLng pos, Offset offset, int index, MapState? state)
  {
    //!!!!
    print(">MiscMarker.onMapMarkerDragEnd(${index})");

    position = pos;
    miscMarkers.sync();

    return pos;
  }
}

//-----------------------------------------------------------------------------
// 汎用マーカー
class MiscMarkers
{
  // 汎用マーカーのデータの配列
  List<MiscMarker> _markers = [];

  // リソースを読み込み
  void initialize()
  {
    _icons.forEach((icon){
      icon.image = Image.asset(icon.path);
    });
  }

  // マーカーを追加
  void addMarker(MiscMarker marker)
  {
    final int index = _markers.length;
    _markers.add(marker);
    _mapOption.markers.add(marker.makeMapMarker(index));
  }

  // クリア
  void clear()
  {
    releaseSync();
    _markers.clear();
    _mapOption.markers.clear();
  }

  //-----------------------------------------------------------------------------
  // FlutterMap のマーカーリストを含むレイヤーデータを取得
  MyDragMarkerPluginOptions _mapOption = MyDragMarkerPluginOptions(
    markers: [],
  );

  MyDragMarkerPluginOptions getMapLayerOptions()
  {
    return _mapOption;
  }

  //-----------------------------------------------------------------------------
  // 変更の同期
  
  // 現在開いているファイルのパス
  String _openedPath = "";

  // 変更通知を受け取るリスナー
  StreamSubscription<DatabaseEvent>? _syncListener;

  // 変更通知が initSync() による初期化によるものかを判定するフラグ
  bool _firstOnSyncAfterOpenFile = true;

  // 変更を送る
  void sync()
  {
    //!!!!
    print(">MiscMarkers.sync(${_openedPath})");

    // マーカー数が少ない想定なので、全マーカーを配列で一括で送る
    final String path = "assign" + _openedPath + "/misc_markers";
    final DatabaseReference ref = FirebaseDatabase.instance.ref(path);
    List<Map<String,dynamic>> data = [];
    _markers.forEach((marker){
      data.add(marker.toMapData());
    });
    ref.set({
      "sender_id": appInstKey,
      "markers": data,
    });

    //!!!! Firestore にコピーを作成(過渡期の処理。最終的には Firestore のみにする)
    {
      final dbDocId = _openedPath.split("/").last;
      final ref = FirebaseFirestore.instance.collection("assign").doc(dbDocId);
      ref.update({ "misc_markers": data });
    }
  }

  // 変更通知の受信を設定
  // ファイルを開いたタイミングで呼び出される
  void initSync(String openedPath)
  {
    //!!!!
    print(">MiscMarkers.initSync(${openedPath})");
  
    // 直前の変更通知リスナーを停止
    releaseSync();

    _openedPath = openedPath;
    final String path = "assign" + _openedPath + "/misc_markers";
    final DatabaseReference ref = FirebaseDatabase.instance.ref(path);
    _firstOnSyncAfterOpenFile = true;
    _syncListener = ref.onValue.listen((DatabaseEvent event){
      _onSync(event, _openedPath);
    });
  }

  // 同期リスナーを停止
  void releaseSync()
  {
    _syncListener?.cancel();
    _syncListener = null;
  }

  // 変更通知受けたときの処理
  void _onSync(DatabaseEvent event, String uidPath)
  {
    //!!!!
    print(">MiscMarkers._onSync(${event.snapshot.ref.path})");

    try {
      var data = event.snapshot.value as Map<String, dynamic>;
      // 自分自身からの変更通知ならば無視する
      // ただしファイルオープン直後は初期化のために読み込む
      if(_firstOnSyncAfterOpenFile){
        //!!!!
        print("> ... first sync.");
      }else{
        final String sender_id = data["sender_id"] as String;
        if(sender_id == appInstKey){
          //!!!!
          print("> ... from myself.");
          return;
        }
      }

      // 他のユーザーからの通知、もしくはファイルオープン時の初期化ならば、マーカーリストを構築
      _markers.clear();
      _mapOption.markers.clear();
      if(data.containsKey("markers")){
        final List<dynamic> markers = data["markers"] as List<dynamic>;
        markers.forEach((data){
          final map = data as Map<String,dynamic>;
          final marker = MiscMarker.fromMapData(map);
          if(marker.ok){
            addMarker(marker);
          }
        });

        //!!!! Firestore にコピーを作成(過渡期の処理。最終的には Firestore のみにする)
        {
          final dbDocId = uidPath.split("/").last;
          final ref = FirebaseFirestore.instance.collection("assign").doc(dbDocId);
          ref.update({ "misc_markers": markers });
        }
      }
    } catch(e) {
      //!!!!
      print("> ... Exception !");
    }
    // 再描画
    updateMapView();

    _firstOnSyncAfterOpenFile = false;
  }

  //----------------------------------------------------------------------------
  // マーカーをタップして編集
  void onMapMarkerTap(BuildContext context, LatLng position, int index)
  {
    //!!!!
    print(">MiscMarkers.onMapMarkerTap(${index})");

    // タツマ名の変更ダイアログ
    var marker = _markers[index];
    _showMiscMarkerDialog(context, marker).then((res){
      if(res != null){
        if(res.containsKey("delete")){
          // 削除
          _markers.removeAt(index);
          _mapOption.markers.clear();
          for(int index = 0; index < _markers.length; index++){
            _mapOption.markers.add(_markers[index].makeMapMarker(index));
          }
          //!!!!
          print(">MiscMarkers.onMapMarkerTap(${index}) ... delete");
        }else{
          // 変更
          marker.iconType = res["iconType"] as int;
          marker.memo     = res["memo"] as String;
          _mapOption.markers[index] = marker.makeMapMarker(index);
          //!!!!
          print(">MiscMarkers.onMapMarkerTap(${index}) ... modify");
        }
        // 同期
        sync();
        // 再描画
        updateMapView();
      }
    });
  }
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 汎用マーカーダイアログ
class MiscMarkerDialog extends StatefulWidget
{
  MiscMarkerDialog({
    super.key,
    required this.iconType,
    required this.memo,
  }){}

  // アイコン
  int iconType;
  // メモ
  String memo;

  @override
  State createState() => _MiscMarkerDialogState();
}

class _MiscMarkerDialogState extends State<MiscMarkerDialog>
{
  late TextEditingController _dateTextController;

  @override 
  void initState()
  {
    super.initState();

    // NOTE: 初期値の設定を build() に書くと、他の Widget 由来の再描画があるたびに、
    // NOTE: テキストフィールドが元に戻ってしまう。initState() に書くのが正解。
    _dateTextController = TextEditingController(text: widget.memo);
  }

  @override
  Widget build(BuildContext context)
  {
    // アイコンタイプの表示スイッチ
    List<bool> iconTypeFlag = [ false, false, false ];
    iconTypeFlag[widget.iconType] = true;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("キルマーカー"),
          // 削除ボタン
          IconButton(
            icon: const Icon(Icons.delete),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: (){
              Navigator.pop<Map<String,dynamic>>(context, {
                "delete": true,
            });
            },
          ),
        ],
      ),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // アイコン選択
          ToggleButtons(
            children: [
              _icons[0].image!,
              _icons[1].image!,
              _icons[2].image!,
            ],
            isSelected: iconTypeFlag,
            onPressed: (index) {
              setState((){
                widget.iconType = index;
              });
            },
          ),
          // メモ
          const SizedBox(width:5, height:25),
          Text("メモ："),
          TextField(
            controller: _dateTextController,
            autofocus: true,
          ),
        ]
      ),
      actions: [
        ElevatedButton(
          child: const Text("キャンセル"),
          onPressed: () {
            Navigator.pop(context);
          }
        ),
        ElevatedButton(
          child: const Text("OK"),
          onPressed: () {
            Navigator.pop<Map<String,dynamic>>(context, {
              "memo": _dateTextController.text,
              "iconType": widget.iconType,
            });
          },
        ),
      ],
    );
  }
}

//----------------------------------------------------------------------------
// 汎用マーカーダイアログ
Future<Map<String,dynamic>?>
  _showMiscMarkerDialog(BuildContext context, MiscMarker data)
{
  return showDialog<Map<String,dynamic>>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return MiscMarkerDialog(
        iconType: data.iconType,
        memo: data.memo);
    },
  );
}