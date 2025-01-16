import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';  // 年月日のフォーマット
import 'ok_cancel_dialog.dart';
import 'text_edit_dialog.dart';
import 'text_edit_icon_dialog.dart';
import 'text_ballon_widget.dart';
import 'text_item_list_dialog.dart';
import 'members.dart';
import 'gps_log.dart';
import 'responsiveAppBar.dart';
import 'globals.dart';
import 'password.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// グローバル

// ファイル名作成機能で選択できる、エリア名
// NOTE: ダイアログから文字列を返すので、この一覧を変更しても既存のデータには影響しない。
List<String> _areaFileNames = const [
  "暗闇沢", "ホンダメ", "苅野上", "笹原林道",
  "桧山", "桧山下",
  "中尾沢", "858", "第一解体場", "最乗寺", "水源の碑",
  
  "裏山", "小土肥9号鉄塔", "小土肥6号鉄塔", "小土肥水車",

  "マムシ沢", "中道",
];

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// ファイル/フォルダを表すアイテム
class FileItem {
  FileItem({
    required this.uid,
    required this.isFolder,
    String name = "",
  }) : _name = name
  {
    // ユニークIDとファイル名/ディレクトリ名の対応を確実に更新する
    _uid2name[uid] = _name;
  }

  factory FileItem.fromMap(Map<String, dynamic> map)
  {
    return FileItem(
      uid: map["uid"],
      name: map["name"],
      isFolder: map["folder"],
    );
  }

  // ユニークID(UID)
  final int uid;

  // ファイル/ディレクトリ名
  String _name = "";
  String get name => _name;
  set name(String name)
  {
    // ユニークIDとファイル名/ディレクトリ名の対応を確実に更新する
    _name = name;
    _uid2name[uid] = _name;
  }

  // ファイルかフォルダか？
  final bool isFolder;
  bool get isFile => !isFolder;

  // GPSログがあるか
  bool gpsLog = false;

  // データベースに格納するMapを取得
  Map<String,dynamic> getDBData()
  {
    return { "uid": uid, "name": _name, "folder": isFolder };
  }

  @override
  String toString ()
  {
    return "$uid:$_name:${isFolder?"Folder":"File"}";
  }
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------

// ルートノードのユニークID
const int _rootDirId = 0;
// 親ディレクトリを表すユニークID
const int _parentDirId = -1;
// 無効なユニークID
const int _invalidUID = -3;
// 削除不可のデフォルトデータを示すユニークID
const int _defaultFileUID = 1;
// 最初に作成されるユーザーファイルのユニークID
// 初回のファイル/ディレクトリ作成で使われ、以降はこの数値からインクリメントされる
const int _firstUserFileID = _defaultFileUID + 1;

// リネーム可能か判定
bool _canRename(int uid)
{
  return (_defaultFileUID < uid);
}

// 削除可能か判定
bool _canDelete(int uid)
{
  return (_defaultFileUID < uid);
}

// NOTE:
// 「現在のディレクトリ」と「現在開いているファイル」は独立した別の概念
// ・「現在のディレクトリ」は、ファイル選択画面で表示しているディレクトリ
// ・「現在開いているファイル」は、マップ画面で表示しているファイル
// 　(必ずなんらかのファイルを開いている設計)
// 「現在のディレクトリ」は「現在開いているファイル」とは別のパスになれる

// ルートから現在のディレクトリまでのスタック(ファイル一覧画面でのカレント)
// NOTE:
// _directoryStack[0] がルートディレクトリにあるファイル/フォルダの一覧
// _directoryStack.last が現在のディレクトリの一覧
List<List<FileItem>> _directoryStack = [ [ ] ];

// ルートから現在のディレクトリまでの、フォルダUIDのリスト
// NOTE:
// _directoryUIDStack[0] は、ルートから一つ下のディレクトリに降りたときのUID
// したがって、_directoryUIDStack.length = (_directoryStack.length - 1) となる
// ルートディレクトリにいるときには、このリストは空となる
// _directoryStack = [
//   [ { uid:2, name:"aaa"}, { uid:3, name:"bbb"} ],  // ルートディレクトリ
//   [ { uid:4, name:"xxx"}, { uid:5, name:"yyy"} ],  // ルートから1つ下のディレクトリ
//   [ { uid:6, name:"foo"}, { uid:7, name:"bar"} ],  // 現在のディレクトリ
// ];
// _directoryUIDStack = [ 3, 4 ];
// の場合、現在のディレクトリは "/3/4/" = "/bbb/xxx/" となる
List<int> _directoryUIDStack = [ ];


// 現在開いているファイルへのUIDパス(必ずなんらかのファイルを開いている設計)
// NOTE:
// ルートディレクトリを表す"/0"は含まない
// 上の例で "bbb/xxx/bar" がファイルで、それを開いているとすると、"/3/4/7" となる
String _openedFileUIDPath = "/$_defaultFileUID";

// 現在開いているファイルのUIDを取得
int get _openedFileUID {
  try{
    return int.parse(_openedFileUIDPath.split("/").last);
  }catch(e){
    return _invalidUID;
  }
}

// ユニークIDと名前の対応表
Map<int, String> _uid2name = {
  _rootDirId: "root",
  _parentDirId: "..",
  _invalidUID: "",
  _defaultFileUID: "デフォルトデータ",
};

// 各ディレクトリにある「親ディレクトリ」を表すアイテム(ルートディレクトリを除く)
final _parentFolder = FileItem(uid:_parentDirId, name:"..", isFolder:true);  

// 現在のディレクトリを参照
List<FileItem> getCurrentDir()
{
  assert(_directoryStack.isNotEmpty);
  return _directoryStack.last;
}

// 現在のディレクトリへのフルパスを取得
// NOTE:
// "/bbb/xxx/" 形式
// 先頭は"/"から始まり、最後のディレクトリ名の後ろは"/"で終わる。
String getCurrentDirPath()
{
  String path = "/";
  for(final uid in _directoryUIDStack){
    final name = _uid2name[uid] ?? uid.toString();
    path += "$name/";
  }
  return path;
}

// 現在のディレクトリのUIDを取得(ルートからのパスではない)
int getCurrentDirUID()
{
  int uid = _rootDirId;
  if(_directoryUIDStack.isNotEmpty){
    uid = _directoryUIDStack.last;
  }
  return uid;
}

// 現在のディレクトへのUIDフルパスを取得
// "/3/4/" 形式
// 先頭は"/"から始まり、最後のディレクトリUIDの後ろは"/"で終わる。
String getCurrentDirUIDPath()
{
  // ディレクトリにあるフォルダから、スタックの次のディレクトリを探しながらたどる
  String path = "/";
  for(final uid in _directoryUIDStack){
    path += "$uid/";
  }
  return path;
}

// 現在開いているファイルのフルパスを取得
// NOTE:
// "/bbb/xxx/bar" 形式
// 先頭は"/"から始まり、最後はファイル名
String getOpenedFilePath()
{
  String namePath = convertUIDPath2NamePath(_openedFileUIDPath);
  return namePath;
}

// 現在開いているファイルへのUIDパスを取得
// NOTE:
// "/3/4/7" 形式
// 先頭は"/"から始まり、最後はファイルのUID
String getOpenedFileUIDPath()
{
  return _openedFileUIDPath;
}

// UIDパスから表示名パスへ変換
// NOTE:
// パスの最後に"/"があれば残すし、なければないまま
// 要は、ファイルへのパスでも、ディレクトリへのパスでも、どちらでも利用可能
String convertUIDPath2NamePath(String uidPath)
{
  // カラ文字列や、先頭が"/"でない場合はエラー
  if(uidPath.isEmpty || (uidPath[0] != "/")) return "";

  // UIDを名前に変換
  List<String> uidsText = uidPath.split("/");
  String namePath = "";
  for(String uidText in uidsText){
    if(uidText != ""){
      final int uid = int.parse(uidText);
      final String name = _uid2name[uid] ?? uid.toString();
      namePath += "/$name";
    }
  }

  // パスの最後が"/"なら残す
  if(uidPath.endsWith("/")){
    namePath += "/";
  }

  return namePath;
}

// 現在開いているファイル名を取得
String getOpenedFileName()
{
  int uid = _openedFileUID;
  return _uid2name[uid] ?? "";
}

// 開いたファイルへのUIDフルパスを設定
// NOTE:
// ファイルの存在や、パスが正しいかのチェックはしない
bool setOpenedFileUIDPath(String uidPath)
{
  // パスの形式をチェック
  bool ok = _checkFileUIDPathFormat(uidPath);

  // OKなら代入
  if(ok){
    _openedFileUIDPath = uidPath;
  }

  print(">FileTree.setOpenedFileUIDPath($uidPath) ok=$ok");

  return ok;
}

bool _checkFileUIDPathFormat(String uidPath)
{
  // カラ文字列や、先頭が"/"でない場合はエラー
  if(uidPath.isEmpty || (uidPath[0] != "/")) return false;
  // パスの最後がファイルでない("/"で終わる)場合はエラー
  if(uidPath.endsWith("/")) return false;
  // uidPath の最後が、UIDであることを確認
  bool ok = false;
  try{
    int.parse(uidPath.split("/").last);
    ok = true;
  }catch(e){ /**/ }

  return ok;
}

//----------------------------------------------------------------------------
// 汎用
class FileResult
{
  FileResult({ this.res=true, this.message="", this.path="", this.uidPath="" }){}

  bool res;
  String message;
  String path;
  String uidPath;

  @override
  String toString ()
  {
    return
      "{ res:" + res.toString() + ", message:" + message +
      ", path:" + path + ", uidPath:" + uidPath + " }";
  }
}

//----------------------------------------------------------------------------
// 初期化
Future initFileTree() async
{
  // データベースにルートディレクトリが記録されていなければ、
  // "デフォルトデータ"と共に登録。
  final colRef = FirebaseFirestore.instance.collection("directories");
  final rootDocRef = colRef.doc("0"); // ルートディレクトリ
  {
    final rootDoc = await rootDocRef.get();
    //!!!! ルートディレクトリがなければ、RealtimeDatabase から取得して初期化
    if(!rootDoc.exists){
      FirebaseDatabase.instance.ref("fileTree2").get().then((value){
        if(value.exists){
          Map<String, String> nameTable = { "0": "root" };
          final items = value.value as Map<String, dynamic>;
          for(var item in items.entries){
            print("Path=${item.key}");
            final list = item.value as List<dynamic>;
            int i = 0;
            for(var data in list){
              print("  [$i]: uid=${data["uid"]}, name=${data["name"]}, folder=${data["folder"]}");
              nameTable[data["uid"].toString()] = data["name"];
              i++;
            }

            String id = "0";
            final path = item.key.split("~");
            if(3 <= path.length){
              id = path[path.length - 2];
            }
            colRef.doc(id).set({
              "items": list,
            });
          }
        }
      });
    }
    {
      final docRef = FirebaseFirestore.instance.collection("misc").doc("fileItemNextUID");
      final doc = await docRef.get();
      if(!doc.exists){
        FirebaseDatabase.instance.ref("fileTreeNextUID").get().then((value){
          if(value.exists){
            final uid = value.value as int;
            print("fileItemNextUID=${uid}");
            docRef.set({ "uid": uid });
          }
        });
      }
    }
  }

  // データベースにルートディレクトリが記録されていなければ、
  // "デフォルトデータ"と共に登録。
  final rootDoc = await rootDocRef.get();
  if(!rootDoc.exists){
    var defaultFile = FileItem(uid:_defaultFileUID, name:"デフォルトデータ", isFolder:false);
    final List<Map<String,dynamic>> files = [ defaultFile.getDBData() ];
    rootDocRef.set({
      "items": files,
    });
  }
  // ファイル/フォルダのユニークIDを発行するためのパスも作成
  final nextUIDdocRef = FirebaseFirestore.instance.collection("misc").doc("fileItemNextUID");
  final nextUIDdoc = await nextUIDdocRef.get();
  if(!nextUIDdoc.exists){
    nextUIDdocRef.set({ "uid": _firstUserFileID });
  }

  // ルートディレクトリをデータベースから読み込み
  await _moveDir(_rootDirId);
}

//----------------------------------------------------------------------------
// 新しいユニークIDを発行
Future<int> _getUniqueID() async
{
  final nextUIDdocRef = FirebaseFirestore.instance.collection("misc").doc("fileItemNextUID");
  final nextUIDdoc = await nextUIDdocRef.get();
  int newUID = _invalidUID;
  if(nextUIDdoc.exists){
    try {
      final data = nextUIDdoc.data();
      newUID = data!["uid"] as int;
    } catch(e) { /**/ }

    // データベース上のユニークIDを新しい値にしておく
    nextUIDdocRef.update({ 'uid': FieldValue.increment(1) });
  }

  return newUID;
}

//----------------------------------------------------------------------------
// 現在のディレクトリにファイル追加
Future<FileResult> createNewFile(String fileName) async
{
  print(">FileTree.createNewFile($fileName)");

  FileResult res = await _addFileItem(fileName, false);

  print(">FileTree.createNewFile($fileName) $res");

  return res;
}

// 現在のディレクトリにフォルダ追加
Future<FileResult> createNewFolder(String folderName) async
{
  print(">FileTree.createNewFolder($folderName)");

  FileResult res = await _addFileItem(folderName, true);

  print(">FileTree.createNewFolder($folderName) $res");

  return res;
}

// ファイル/フォルダ追加の共通処理
Future<FileResult> _addFileItem(String name, bool folder) async
{
  // ファイル名のチェック
  FileResult res = _checkFileName(name);
  if(!res.res) return res;

  // 新しいユニークIDを取得
  int uid = await _getUniqueID();
  if(uid == _invalidUID){
    return FileResult(res:false, message:"内部エラー: ファイルUIDの取得に失敗");
  }

  // 新しいファイル/フォルダーを、現在のディレクトリに追加
  FileItem newItem = FileItem(uid:uid, name:name, isFolder:folder);
  List<FileItem> currentDir = getCurrentDir();
  currentDir.add(newItem);

  // 並びをソートする
  sortDir(currentDir);

  // ディレクトリツリーのデータベースを更新
  _updateFileListToDB(getCurrentDirUID(), currentDir);

  // フォルダを作成した場合は、データベースに空のディレクトリを作成
  if(folder){
    _updateFileListToDB(uid, []);
  }

  // 作成されたファイルパスを返す
  final String newPath = getCurrentDirPath() + name + (folder?"/":"");
  final String newUIDPath = getCurrentDirUIDPath() + uid.toString() + (folder?"/":"");

  return FileResult(path:newPath, uidPath:newUIDPath);
}

// 現在のディレクトリのファイル名変更
FileResult renameFile(FileItem item, String newName)
{
  print(">FileTree.renameFile($item newName:$newName)");

  FileResult res = _renameFile(item, newName);

  print(">FileTree.renameFile($item) newName:$newName $res");

  return res;
}

FileResult _renameFile(FileItem item, String newName)
{
  // ファイル名に変更がなければ成功
  if(item.name == newName) return FileResult();

  // リネーム禁止のファイル
  if(!_canRename(item.uid)){
    return FileResult(res:false, message:"'デフォルトデータ'等はリネームできません");
  }

  // ファイル名のチェック
  FileResult res = _checkFileName(newName);
  if(!res.res) return res;

  // item が現在のディレクトリにあることをチェック
  List<FileItem> currentDir = getCurrentDir();
  bool ok = false;
  for(final i in currentDir){
    ok = (i.uid == item.uid);
    if(ok) break;
  }
  if(!ok){
    return FileResult(res:false, message:"内部エラー: 現在のディレクトリに無いアイテムのリネーム");
  }

  // データの変更
  item.name = newName;

  // 並びをソートする
  sortDir(currentDir);

  // ディレクトリツリーのデータベースを更新
  _updateFileListToDB(getCurrentDirUID(), currentDir);

  // ファイルの場合、配置データ側にあるファイル名も変更
  if(item.isFile){
    final dbDocId = "${item.uid}";
    final assignDocRef = FirebaseFirestore.instance.collection("assign").doc(dbDocId);
    assignDocRef.update({ "name": newName });
  }

  // 変更されたファイルパスを返す
  final String newPath = getCurrentDirPath() + newName;
  final String newUIDPath = getCurrentDirUIDPath() + item.uid.toString();

  return FileResult(path:newPath, uidPath:newUIDPath);
}

// ファイル名のチェック
FileResult _checkFileName(String name)
{
  if(name == ""){
    return FileResult(res:false, message:"ファイル名が指定されていません");
  }
  if((name == ".") || (name == "..")){
    return FileResult(res:false, message:"'.'および'..'はファイル名に使えません");
  }
  if(name.contains("/")){
    return FileResult(res:false, message:"'/'はファイル名に使えません");
  }
  if(name.contains("~")){
    return FileResult(res:false, message:"'~'はファイル名に使えません");
  }
  List<FileItem> currentDir = getCurrentDir();
  bool res = true;
  currentDir.forEach((item){
    if(item.name == name) res = false;
  });
  if(!res){
    return FileResult(res:false, message:"既にあるファイル名は使えません");
  }

  // OK
  return FileResult();
}

// 現在のディレクトリのファイル削除
FileResult deleteFile(FileItem item)
{
  print(">FileTree.deleteFile($item)");

  FileResult res = _deleteFile(item);

  print(">FileTree.deleteFile($item) $res");

  return res;
}

FileResult _deleteFile(FileItem item)
{
  // エラーチェック
  if(!item.isFile){
    return FileResult(res:false, message:"内部エラー: deleteFile()にフォルダを指定");
  }
  if(!_canDelete(item.uid)){
    return FileResult(res:false, message:"'デフォルトデータ'等は削除できません");
  }
  if(item.uid == _openedFileUID){
    return FileResult(res:false, message:"開いているファイルは削除できません");
  }

  // 現在のディレクトリから要素を削除
  List<FileItem> currentDir = getCurrentDir();
  if(!currentDir.remove(item)){
    return FileResult(res:false, message:"内部エラー: 現在のディレクトリに無いファイルの削除");
  }

  // ディレクトリツリーのデータベースを更新
  _updateFileListToDB(getCurrentDirUID(), currentDir);

  // 配置データやGPSログは削除せずに放っておく(サルベージ可能なように)

  print(">FileTree._deleteFile($item)");

  return FileResult();
}

// フォルダ削除
Future<FileResult> deleteFolder(FileItem folder) async
{
  print(">FileTree.deleteFolder($folder)");

  FileResult res = await _deleteFolder(folder);

  print(">FileTree.deleteFolder($folder) $res");

  return res;
}

Future<FileResult> _deleteFolder(FileItem folder) async
{
  // エラーチェック
  if(!folder.isFolder){
    return FileResult(res:false, message:"内部エラー: deleteFolder()にファイルを指定");
  }
  if(folder.uid == _parentDirId){
    return FileResult(res:false, message:"'上階層に戻る'は削除できません");
  }
  final String folderUID = "/${folder.uid}/";
  if(getOpenedFileUIDPath().contains(folderUID)){
    return FileResult(res:false, message:"開いているファイルを含むフォルダは削除できません");
  }

  // item が現在のディレクトリにあることをチェック
  var currentDir = getCurrentDir();
  int index = -1;
  for(int i = 0; i < currentDir.length; i++){
    final item = currentDir[i];
    if(item.isFolder && (item.uid == folder.uid)){
      index = i;
      break;
    }
  }
  if(index == -1){
    return FileResult(res:false, message:"内部エラー: 現在のディレクトリに無いフォルダの削除");
  }

  // フォルダ削除の再帰処理
  await _deleteFolderRecursive(folder);

  // 現在のディレクトリから要素を削除
  // NOTE: _deleteFolderRecursive() でディレクトが再構築されているので、currentDir を参照しなおす
  currentDir = getCurrentDir();
  for(int i = 0; i < currentDir.length; i++){
    final item = currentDir[i];
    if(item.isFolder && (item.uid == folder.uid)){
      currentDir.removeAt(i);
      // ディレクトリツリーのデータベースを更新
      _updateFileListToDB(getCurrentDirUID(), currentDir);
      break;
    }
  }

  // 配置データやGPSログは削除せずに放っておく(サルベージ可能なように)

  return FileResult();
}

// フォルダ削除の再帰処理
Future _deleteFolderRecursive(FileItem folder) async
{
  // 指定されたフォルダに降りて、
  bool res = await _moveDir(folder.uid);
  if(!res) return;

  // その中のディレクトリに再帰しながら削除
  // NOTE: forEach() 使うと await で処理止められない…
  final List<FileItem> currentDir = getCurrentDir();
  for(int i = 0; i < currentDir.length; i++){
    final FileItem item = currentDir[i];
    if(item.isFolder && (item.uid != _parentDirId)){
      // フォルダを再帰的に削除
      await _deleteFolderRecursive(item);
    }
  }

  // データベースから自分自身を削除
  final docRef = FirebaseFirestore.instance.collection("directories").doc("${folder.uid}");
  docRef.delete();

  // 親ディレクトリへ戻る
  await _moveDir(_parentDirId);
}

// ディレクトリ内の並びをソート
void sortDir(List<FileItem> dir)
{
  dir.sort((a, b){
    // 「階層を戻る」が先頭
    if(a.uid == _parentDirId) return -1;
    // フォルダが前
    if(a.isFolder && !b.isFolder) return -1;
    if(!a.isFolder && b.isFolder) return 1;
    // ファイル名で比較
    return a.name.compareTo(b.name);
  });
}

// 直前の moveDir() が完了するまで、次の処理を破棄するフラグ
bool _blockingMoveDir = false;

// ディレクトリを移動
// 現在のディレクトリから1階層の移動のみ。
Future<bool> moveDir(int uid) async
{
  print(">FileTree.moveDir($uid)");

  // 直前の _moveDir() が終わってなかったら何もしない
  bool res = false;
  if(!_blockingMoveDir){
    _blockingMoveDir = true;
    res = await _moveDir(uid);
    _blockingMoveDir = false;
    print(">FileTree.moveDir($uid) $res " + getCurrentDirUIDPath());
  }else{
    print("  Blocking!");
  }
  return res;
}

Future<bool> _moveDir(int uid) async
{
  print(">FileTree._moveDir($uid)");

  // 次に現在のディレクトリとなるフォルダのUIDを決定
  int nextUID = uid;
  if(uid == _rootDirId){
    // ルートディレクトリに戻る
  }else if(uid == _parentDirId){
    // 親ディレクトリに戻る
    final n = _directoryUIDStack.length;
    if(n == 0){
      // ルートにいて、更に親はない
      print(">FileTree._moveDir(): Error: No parent directory of the root.");
      return false;
    }else if(n == 1){
      // (結果として)ルートディレクトリに戻る
      nextUID = _rootDirId;
    }else{
      // 親ディレクトリに戻る
      nextUID = _directoryUIDStack[n - 2];
    }
  }else{ 
    // 現在のディレクトリの一つ下のフォルダに入る
    // 指定されたフォルダが存在しなければエラー
    bool ok = false;
    for(final item in getCurrentDir()){
      ok = (item.uid == uid) && item.isFolder;
      if(ok) break;
    }
    if(!ok){
      print(">FileTree._moveDir(): Error: Folder(uid:$uid) is not in current directory.");
      return false;
    }
  }

  // 移動先ディレクトリの構成をデータベースから取得
  final docRef = FirebaseFirestore.instance.collection("directories").doc("$nextUID");
  final doc = await docRef.get();
  if(!doc.exists){
    print(">FileTree._moveDir(): Error: Doc of directory(uid:$nextUID) does not exist in DB.");
    return false;
  }
  // ルート階層以外なら、「親ディレクトリ」を追加
  List<FileItem> directory = [];
  if(nextUID != _rootDirId){
    directory.add(_parentFolder);
  }
  final data = doc.data();
  for(var item in data!["items"] as List<dynamic>){
    directory.add(FileItem.fromMap(item));
  }
  // ソートしておく
  sortDir(directory);

  // ディレクトリスタックに追加
  if(nextUID == _rootDirId){
    // ルートディレクトリに戻るので、スタックをクリア
    _directoryStack.clear();
    _directoryUIDStack.clear();
  }else if(uid == _parentDirId){
    // 親ディレクトリに戻るので、現在のディレクトリを削除
    _directoryStack.removeLast();
    _directoryStack.removeLast();
    _directoryUIDStack.removeLast();
  }else{
    // 一つ下に降りる場合は、現在のスタックに追加するだけ
    _directoryUIDStack.add(nextUID);
  }
  _directoryStack.add(directory);

  // GPSログファイルの一覧をクラウドストレージから取得する
  // ファイルに対応するGPSログがあるかどうかをチェック
  final uidPath = getCurrentDirUIDPath();
  final gpsFileList = await gpsLog.getFileList(uidPath);
  for(var item in directory){
    if(item.isFile){
      final String gpxFileName = "${item.uid}.gpx";
      item.gpsLog = gpsFileList.contains(gpxFileName);
    }
  }

  return true;
}

// 現在開いているファイルのGPSログの有無フラグを変更
void setOpenedFileGPSLogFlag(bool gpsLog)
{
  // 現在のディレクトリに開いているファイルがあれば、フラグをセットする
  // 現在のディレクトリが開いているファイルと別の位置なら、moveDir() でセットされる
  final currentFileUID = _openedFileUID;
  List<FileItem> files = getCurrentDir();
  files.forEach((file){
    if(file.uid == currentFileUID){
      file.gpsLog = gpsLog;
      return;
    }
  });
}

// UIDパスで指定されたディレクトリへ移動
// uidPath の最後が"/"ならディレクトリ、そうでなければファイルとみなし、最後のディレクトリまで移動
Future<bool> moveAbsUIDPathDir(String uidPath) async
{
  print(">FileTree.moveAbsUIDPathDir(${uidPath})");

  bool res = await _moveAbsUIDPathDir(uidPath);

  print(">FileTree.moveAbsUIDPathDir(${uidPath}) ${res} " + getCurrentDirUIDPath());

  return res;
}

Future<bool> _moveAbsUIDPathDir(String uidPath) async
{
  // 先頭にパス文字がないのは文字列がおかしい
  if(!uidPath.startsWith("/")) return false;

  // 現在のディレクトリをルートに戻す
  bool res = await _moveDir(_rootDirId);
  if(!res) return false;

  // UIDを分解
  List<int> uidList = [];
  for(final uid in uidPath.split("/")){
    if(uid == "") continue;
    uidList.add(int.parse(uid));
  }
  // パスの最後が"/"でないなら、最後のUIDはファイルなので取り除く
  if(!uidPath.endsWith("/") && uidList.isNotEmpty){
    uidList.removeLast();
  }

  // 指定されたパスから1階層ずつ入っていく
  for(final uid in uidList){
    final bool res = await _moveDir(uid);
    if(!res) return false;
  }

  return true;
}

// ディレクトリツリーのデータベースを更新
void _updateFileListToDB(int dirUID, final List<FileItem> dir)
{
  // フォルダのIDが、Firestore のドキュメントIDになる
  final ref = FirebaseFirestore.instance.collection("directories").doc("$dirUID");

  List<Map<String,dynamic>> items = [];
  for(final item in dir){
    // 「親階層に戻る」は除外
    if(item.uid != _parentDirId){
      items.add(item.getDBData());
    }
  }
  ref.set({ "items": items });
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// ファイル一覧画面
class FilesPage extends StatefulWidget
{
  FilesPage({
    super.key,
    required this.onSelectFile,
    required this.onChangeState,
    this.readOnlyMode = false,
    this.referGPSLogMode = false,
  }){}

  // ファイル選択決定時のコールバック
  final Function(String) onSelectFile;

  // 何らかの変更コールバック(ファイル選択にまでは至らない、主にリネーム時)
  final Function() onChangeState;

  // 読み取り専用モード(作成や削除、リネームはできない)
  final bool readOnlyMode;

  // GPSファイル参照モード
  final bool referGPSLogMode;

  @override
  FilesPageState createState() => FilesPageState();
}

class FilesPageState extends State<FilesPage>
{
  TextStyle _textStyle = const TextStyle(
    color:Colors.black, fontSize:18.0
  );
  TextStyle _textStyleBold = const TextStyle(
    color:Colors.black, fontSize:18.0, fontWeight:FontWeight.bold
  );
  TextStyle _textStyleDisable = const TextStyle(
    color:Color(0xFFBDBDBD)/*Colors.grey[400]*/, fontSize:18.0
  );
  Border _borderStyle = const Border(
    bottom: BorderSide(width:1.0, color:Colors.grey)
  );

  @override
  initState() {
    super.initState();
  }

  var _responsiveAppBar = ResponsiveAppBar();

  @override
  Widget build(BuildContext context)
  {
    // 幅が狭ければ、文字を小さくする
    var screenSize = MediaQuery.of(context).size;
    final bool narrowWidth = (screenSize.width < 640);

    final List<FileItem> currentDir = getCurrentDir();

    return WillPopScope(
      // ページ閉じる際の処理
      onWillPop: (){
        Navigator.pop(context);
        return Future.value(false);
      },
      child: Scaffold(
        appBar: _responsiveAppBar.makeAppBar(
          context,
          titleLine: [
            Text(
              getCurrentDirPath(),
              textScaleFactor: (narrowWidth? 0.8: null),
            ),
          ],
          actionsLine: [
            // (左)フォルダ作成ボタン
            if(!widget.readOnlyMode) IconButton(
              icon: Icon(Icons.create_new_folder),
              onPressed:() {
                createNewFolderSub(context);
              },
            ),
            // (右)ファイル作成ボタン
            if(!widget.readOnlyMode) IconButton(
              icon: Icon(Icons.note_add),
              onPressed:() {
                createNewFileSub(context);
              },
            ),
          ],
          setState: setState,
        ),
        // 現在のディレクトリのファイル/ディレクトリを表示
        body: ListView.builder(
          itemCount: currentDir.length,
          itemBuilder: (context, index){
            return _menuItem(context, index);
          }
        ),        
      ),
    );
  }

  // ファイル一覧アイテムの作成
  Widget _menuItem(BuildContext context, int index)
  {
    // アイコンを選択
    final int stackDepth = _directoryStack.length;
    final List<FileItem> currentDir = getCurrentDir();
    var file = currentDir[index];
    IconData icon;
    late String name;
    bool goParentDir;
    bool enable = true;
    if((1 < stackDepth) && (index == 0)){
      //「上階層に戻る」
      goParentDir = true;
      name = "上階層に戻る";
      icon = Icons.drive_file_move_rtl;
    }else{
      // ファイルかフォルダ
      goParentDir = false;
      name = file.name;
      if(file.isFile){
        if(!widget.referGPSLogMode){
          icon = Icons.description;
        }else{
          // GPSログ参照モードでは、GPSログの有無
          if(file.gpsLog){
            icon = Icons.timeline;
          }else{
            icon = Icons.horizontal_rule; // 意味のない無難なアイコン
            enable = false; // 選択不可
          }
        }
      }else{
        icon = Icons.folder;
      }
    }

    // 現在開いているファイルとその途中のフォルダは強調表示する。
    // 削除も禁止
    late bool isOpenedFile;
    if(currentDir[index].isFile){
      // ファイルの場合はIDの一致で判定
      isOpenedFile = (_openedFileUID == currentDir[index].uid);
    }else{
      // フォルダの場合は、パスにIDが含まれるかで判定
      final String uid = currentDir[index].uid.toString();
      isOpenedFile = _openedFileUIDPath.contains("/$uid/");
    }

    // アイコンボタンの座標を取得するため
    GlobalKey iconGlobalKey = GlobalKey();

    // メニュードット「…」を表示するか？
    final bool showMenuDot = !goParentDir && !widget.readOnlyMode;

    return Container(
      // ファイル間の境界線
      decoration: BoxDecoration(border:_borderStyle),
      // アイコンとファイル名
      child:ListTile(
        // (左側)ファイル/フォルダーアイコン
        leading: Icon(icon),
        iconColor: (isOpenedFile?
          Colors.black:
          (enable? null: Colors.grey[400])),

        // ファイル名
        title: Text(name,
          style: (isOpenedFile?
            _textStyleBold:
            (enable? _textStyle: _textStyleDisable)),
        ),

        // (右側)メニューボタン
        // 「親階層に戻る」では非表示
        trailing: showMenuDot? IconButton(
          icon: Icon(Icons.more_horiz, key:iconGlobalKey),
          onPressed:() {
            // ボタンの座標を取得してメニューを表示
            RenderBox box = iconGlobalKey.currentContext!.findRenderObject() as RenderBox;
            var offset = box.localToGlobal(Offset.zero);
            showFileItemMenu(context, currentDir[index], offset, !isOpenedFile);
          },
        ) : null,

        // タップでファイルを切り替え
        onTap: () {
          if(currentDir[index].isFile){
            if(enable){
              Navigator.pop(context);
              // ファイルを切り替える
              final String thisUIDPath = getCurrentDirUIDPath() + currentDir[index].uid.toString();
              widget.onSelectFile(thisUIDPath);
            }
          }else{
            // ディレクトリ移動
            moveDir(currentDir[index].uid).then((_){
              setState((){});
            });
          }
        },
      ),
    );
  }

  // ファイルメニューを開く
  void showFileItemMenu(
    BuildContext context, FileItem item, Offset offset, bool enableDelete)
  {
    // メニューの位置をちょい左に
    // NOTE: メニュー右端の座標指定の方法を見つけたい…
    offset = offset - Offset(180, 0);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx, offset.dy, offset.dx, offset.dy),
      elevation: 8.0,
      items: [
        makePopupMenuItem(0, "リネーム", Icons.drive_file_rename_outline,
          enabled: _canRename(item.uid)),
        makePopupMenuItem(1, "削除", Icons.delete,
          enabled: enableDelete && _canDelete(item.uid)),
      ],
    ).then((value) async {
      // ファイル操作にはパスワードが必要
      bool authenOk = await askAndCheckPassword(context,
        "ファイル操作パスワード", lockEditingPasswordHash, lockEditingPasswordKey);
      // ハズレ
      if(!authenOk){
        showTextBallonMessage("ハズレ...");
        return;
      }

      switch(value ?? -1){
      case 0:
        // リネーム
        showRenameFileDialog(context, item.name).then((String? newName){
          if(newName != null){
            var res = renameFile(item, newName);
            if(res.res){
              setState((){});
              // AppBar の更新しておく
              widget.onChangeState();
            }else{
              // エラーメッセージ
              showDialog(
                context: context,
                builder: (_){ return AlertDialog(content: Text(res.message)); });
            }
          }
        });
        break;
      case 1:
        // ファイルを削除
        deleteFileSub(context, item);
        break;
      }
    });
  }

  // ファイル作成
  void createNewFileSub(BuildContext context) async
  {
    // ファイル名入力ダイアログ
    String? name = await showCreateFileDialog(context);
    if(name == null) return;

    // 作成
    var res = await createNewFile(name);
    if(res.res){
      // 実際に配置ファイルを作成
      createNewAssignFile(res.uidPath, name);
      // 作成が成功したら、切り替えてマップに戻る
      widget.onSelectFile(res.uidPath);
      Navigator.pop(context);
    }else{
      // エラーメッセージ
      showDialog(
        context: context,
        builder: (_){ return AlertDialog(content: Text(res.message)); });
    }
  }

  // フォルダ作成
  void createNewFolderSub(BuildContext context) async
  {
    // ファイル名入力ダイアログ
    String? name = await showCreateFolderDialog(context);
    if(name == null) return;

    // 作成
    final res = await createNewFolder(name);
    if(res.res){
      // フォルダ作成が成功したら再描画
      setState((){});
    }else{
      // エラーメッセージ
      showDialog(
        context: context,
        builder: (_){ return AlertDialog(content: Text(res.message)); }
      );
    }
  }

  // ファイル/ディレクトリの削除
  Future deleteFileSub(BuildContext context, FileItem item) async
  {
    // ファイル削除ダイアログ
    final String typeText = item.isFile? "ファイル": "フォルダ";
    final String message = typeText + "「" + item.name + "」を削除しますか？";
    bool? ok = await showOkCancelDialog(context, text:message);
    if((ok != null)? !ok: true) return;

    // 削除処理
    late FileResult res;
    if(item.isFile){
      res = deleteFile(item);
    }else{
      res = await deleteFolder(item);
    }

    if(res.res){
      // 再描画
      setState((){});
    }else{
      // エラーメッセージ
      showDialog(
        context: context,
        builder: (_){ return AlertDialog(content: Text(res.message)); }
      );
    }
  }
}

//----------------------------------------------------------------------------
// ファイル名入力ダイアログ
Future<String?> showCreateFileDialog(BuildContext context)
{
  // アイコンボタン押して、カレンダーWidgetで日付を指定できる。
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return TextEditIconDialog(
        icon: Icons.calendar_month,
        onIconTap: showCalendar,
        titleText:"ファイルの作成",
        hintText:"新規ファイル名",
        okText:"作成");
    },
  );
}

Future<String?> showRenameFileDialog(BuildContext context, String fileName)
{
  // アイコンボタン押して、カレンダーWidgetで日付を指定できる。
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return TextEditIconDialog(
        icon: Icons.calendar_month,
        onIconTap: showCalendar,
        titleText:"リネーム",
        defaultText:fileName,
        okText:"変更");
    },
  );
}

// カレンダーWidgetで月日を指定
Future<String?> showCalendar(BuildContext context) async
{
  // まずはカレンダーで日付を選択
  final DateTime today = DateTime.now();
  DateTime? date = await showDatePicker(
    context: context,
    locale: const Locale("ja"),
    initialDate: today,
    firstDate: DateTime(today.year-5, today.month),
    lastDate: DateTime(today.year+5, today.month),
    initialEntryMode: DatePickerEntryMode.calendarOnly);
  if(date == null) return null;

  // 次にラウンドを選択
  const List<String> rounds = [ "R1", "R2", "R3", "" ];
  String? round = await showDialog<String>(
    context: context,
    builder: (context) {
      return TextItemListDialog(title: "ラウンド", items: rounds);
    }
  );
  if(round == null) return null;

  // 最後にエリア名を選択
  String? areaName = await showDialog<String>(
    context: context,
    builder: (context) {
      return TextItemListDialog(title: "エリア", items: _areaFileNames);
    }
  );
  if(areaName == null) return null;

  // 最終的なファイル名を作成
  final String fileName =
    DateFormat("MM月dd日 ").format(date) + round + " " + areaName;
  return fileName;
}

//----------------------------------------------------------------------------
// フォルダ名入力ダイアログ
Future<String?> showCreateFolderDialog(BuildContext context)
{
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return TextEditDialog(
        titleText:"フォルダの作成",
        hintText:"新規フォルダ名",
        okText:"作成");
    },
  );
}
