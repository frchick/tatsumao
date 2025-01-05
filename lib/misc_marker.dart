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
  MiscMarker({ required this.position, this.iconType=0, this.memo="", this.id="" });

  // 座標
  LatLng position;
  // アイコンタイプ
  int iconType;
  // メモ
  String memo;
  // ID(Firestore用)
  String id;

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
  factory MiscMarker.fromMapData(Map<String,dynamic> map, String id)
  {
    try {
      double latitude = map["latitude"] as double;
      double longitude = map["longitude"] as double;
      final position = LatLng(latitude, longitude);
      final iconType = map["iconType"] as int;
      final memo = map["memo"] as String;
      return MiscMarker(position: position, iconType: iconType, memo: memo, id: id);
    } catch(e) {
      return MiscMarker(position: LatLng(0,0));
    }
  }

  // マップ上に表示する用のマーカーを作成
  MyDragMarker makeMapMarker(int index)
  {
    //!!!!
    print(">MiscMarker.makeMapMarker($index)");

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
    print(">MiscMarker.onMapMarkerDragEnd($index)");

    position = pos;
    miscMarkers._syncModify(this);

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
    // もし Firestore 用のIDが未設定なら、新規作成としてIDを設定
    if(marker.id.isEmpty && (_colRef != null)){
      marker.id = _colRef!.doc().id;
      _syncModify(marker);
    }

    // マーカーを配列に追加
    final int index = _markers.length;
    _markers.add(marker);
    _mapOption.markers.add(marker.makeMapMarker(index));
  }

  // クリア(ファイルを切り替え)
  void clear()
  {
    _colRef = null;
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

  // 現在開いているファイルの、マーカーのコレクションへの参照
  CollectionReference<Map<String, dynamic>>? _colRef;

  // 変更通知を受け取るリスナー
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _syncListener;

  // 変更通知が initSync() による初期化によるものかを判定するフラグ
  bool _isFirstSyncEvent = true;

  // 変更を送る
  void _syncModify(MiscMarker marker)
  {
    //!!!!
    print(">MiscMarkers._syncModify(${marker.id})");

    //!!!! Firestore にコピーを作成(過渡期の処理。最終的には Firestore のみにする)
    var data = marker.toMapData();
    _colRef?.doc(marker.id).set(data);
  }

  // 削除を送る
  void _syncDelete(MiscMarker marker)
  {
    //!!!!
    print(">MiscMarkers._syncDelete(${marker.id})");

    _colRef?.doc(marker.id).delete();
  }

  // 変更通知の受信を設定
  // ファイルを開いたタイミングで呼び出される
  void initSync(String openedPath) async
  {
    //!!!!
    print(">MiscMarkers.initSync(${openedPath})");
  
    // 直前の変更通知リスナーを停止
    releaseSync();

    _openedPath = openedPath;

    // Firestore のコレクションへの参照を取得
    final dbDocId = _openedPath.split("/").last;
    final docRef = FirebaseFirestore.instance.collection("assign").doc(dbDocId);
    _colRef = docRef.collection("misc_markers");

    //!!!! Firestore にデータがなければ、RealtimeDatabase から取得して作成
    bool existData = false;
    try {
      var cnt = await _colRef!.count().get();
      existData = (0 < (cnt.count ?? 0));
    } catch(e) { /**/ }
    if(!existData){
      try {
        final String path = "assign" + _openedPath + "/misc_markers/markers";
        final DatabaseReference ref = FirebaseDatabase.instance.ref(path);
        final DataSnapshot snapshot = await ref.get();
        if(snapshot.exists){
          print(">  MiscMarkers data was duplicated from RealtimeDatabase to Firestore.");
          final data = snapshot.value as List<dynamic>;
          data.forEach((map){
            _colRef!.doc().set(map);
          });
        }
      } catch(e) { /**/ }
    }

    // Firestore から変更通知を受け取るリスナーを設定
    _isFirstSyncEvent = true;
    _syncListener = _colRef!.where("iconType", isGreaterThanOrEqualTo: 0).snapshots().listen(
      (event){
        _onSync(event, openedPath);
      }
    );
  }

  // 同期リスナーを停止
  void releaseSync()
  {
    _openedPath = "";
    _syncListener?.cancel();
    _syncListener = null;
  }

  // 変更通知受けたときの処理
  void _onSync(QuerySnapshot<Map<String, dynamic>> event, String uidPath)
  {
    print(">MiscMarkers._onSync(): count=${event.docs.length}, local=${event.metadata.hasPendingWrites}, first=${_isFirstSyncEvent}");

    // 現在開いているファイルと異なるファイルの変更通知は無視
    // ファイルの切り替え時に、前のファイルの変更通知が遅れてくることがあるため
    if(_openedPath != uidPath){
      return;
    }
  
    // ローカルの変更による通知では何もしない
    // ただし、マーカーを初期化するために、ファイルを開いた直後のデータ変更通知は拾う
    final first = _isFirstSyncEvent;
    _isFirstSyncEvent = false;
    if(!first && event.metadata.hasPendingWrites){
      return;
    }

    // マーカーリストを全て再構築
    try {
      _markers.clear();
      _mapOption.markers.clear();
      event.docs.forEach((doc){
        final marker = MiscMarker.fromMapData(doc.data(), doc.id);
        addMarker(marker);
      });
    } catch(e) { /**/ }

    // 再描画
    updateMapView();
  }

  //----------------------------------------------------------------------------
  // マーカーをタップして編集
  void onMapMarkerTap(BuildContext context, LatLng position, int index)
  {
    //!!!!
    var marker = _markers[index];
    print(">MiscMarkers.onMapMarkerTap(${marker.id})");

    // タツマ名の変更ダイアログ
    _showMiscMarkerDialog(context, marker).then((res){
      if(res != null){
        if(res.containsKey("delete")){
          // 削除
          print(">MiscMarkers.onMapMarkerTap(${marker.id}) ... delete");
          // 同期
          _syncDelete(marker);
          // NOTE: Firestore からの削除がリモート扱いになり、_onSync() でリストが
          // 更新されるため、ここでのリストの更新は不要。
        }else{
          // 変更
          print(">MiscMarkers.onMapMarkerTap(${marker.id}) ... modify");
          // 変更
          marker.iconType = res["iconType"] as int;
          marker.memo     = res["memo"] as String;
          _mapOption.markers[index] = marker.makeMapMarker(index);
          // 同期
          _syncModify(marker);
        }
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