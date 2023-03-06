import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';  // 年月日のフォーマット
import 'ok_cancel_dialog.dart';
import 'text_edit_dialog.dart';
import 'text_edit_icon_dialog.dart';
import 'text_ballon_widget.dart';
import 'text_item_list_dialog.dart';
import 'tatsumas.dart';
import 'gps_log.dart';
import 'responsiveAppBar.dart';
import 'globals.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// グローバル

// ファイル名作成機能で選択できる、エリア名
List<String> _areaFileNames = const [
  "暗闇沢", "ホンダメ", "苅野上", "笹原林道",
  "桧山", "桧山下",
  "中尾沢", "858", "マルオ",

  "水源の碑", "桧山ゲート上", "桧山ゲート下",
  
  "裏山", "小土肥9号鉄塔", "小土肥6号鉄塔", "小土肥水車",

  "マムシ沢", "中道",
];

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// ファイル/ディレクトリ階層構造

class FileItem {
  FileItem({
    required this.uid,
    String name = "",
    this.child,
  }) : _name = name
  {
    // ユニークIDとファイル名/ディレクトリ名の対応を確実に更新する
    _uid2name[uid] = _name;
  }

  // ユニークID
  final int uid;
  // ファイル/ディレクトリ名
  String _name;
  // GPSログがあるか
  bool gpsLog = false;

  // 子階層
  // ディレクトリの場合、このディレクトリ内のファイル/ディレクトリの一覧
  List<FileItem>? child;

  String get name => _name;

  set name(String name)
  {
    // ユニークIDとファイル名/ディレクトリ名の対応を確実に更新する
    _name = name;
    _uid2name[uid] = _name;
  }

  // ファイルか？
  bool isFile(){ return (0 < uid) && (child == null); }
  // フォルダか？
  bool isFolder(){ return (uid <= 0) || (child != null); }

  // データベースに格納するMapを取得
  Map<String,dynamic> getDBData()
  {
    return { "uid": uid, "name": _name, "folder": isFolder() };
  }

  @override
  String toString ()
  {
    return "${uid}:${_name}";
  }
}

// ルートノードのユニークID
const int _rootDirId = 0;
// 親ディレクトリを表すユニークID
const int _parentDirId = -1;
// カレントディレクトリを表すユニークID
const int _currentDirId = -2;
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

// ルートノード
FileItem _fileRoot = FileItem(uid:_rootDirId, name:"");

// ルートから現在のディレクトリまでのスタック(ファイル一覧画面でのカレント)
// _directoryStack.last がカレントディレクトリのフォルダで、
// _directoryStack.last.child がカレントディレクトリのファイル一覧
List<FileItem> _directoryStack = [ _fileRoot ];

// 現在開いているファイルまでのスタック
List<int> _openedUIDPathStack = [ _rootDirId ];

// ユニークIDと名前の対応表
Map<int, String> _uid2name = {
  _rootDirId: "",
  _parentDirId: "..",
  _currentDirId: ".",
  _invalidUID: "",
  _defaultFileUID: "デフォルトデータ",
};

//ファイルツリーの共有(Firebase RealtimeDataBase)
FirebaseDatabase database = FirebaseDatabase.instance;

// カレントディレクトリの変更通知
StreamSubscription<DatabaseEvent>? _currentDirChangeListener;
// カレントディレクトリの変更通知があったときのファイルツリー画面の再描画
Function? _onCurrentDirChangedForFilesPage;

// Firebase RealtimeDataBase の参照パス
final _fileRootPath = "fileTree2/";

// UIDパスから Firebase RealtimeDataBase の参照パスを取得
DatabaseReference getDatabaseRef(String uidPath)
{
  // ディレクトリの階層構造をDBの階層構造として扱わない！
  // そのためパスセパレータ'/'を、セパレータではない文字'~'に置き換えて、階層構造を作らせない。
  // DatabaseReference.get() でのデータ転送量をケチるため。
  final String databasePath = uidPath.replaceAll("/", "~");
  return database.ref(_fileRootPath + databasePath);
}

//----------------------------------------------------------------------------
// カレント

// カレントディレクトリを参照
List<FileItem> getCurrentDir()
{
  assert((0 < _directoryStack.length) && (_directoryStack.last.child != null));
  return _directoryStack.last.child!;
}

// カレントディレクトリへのフルパスを取得
// 先頭は"/"から始まり、最後のディレクトリ名の後ろは"/"で終わる。
String getCurrentPath()
{
  String path = "";
  _directoryStack.forEach((folder){
    path += folder.name + "/";
  });
  return path;
}

// カレントディレクトへのUIDフルパスを取得
// 先頭は"/"から始まり、最後のディレクトリ名の後ろは"/"で終わる。
String getCurrentUIDPath()
{
  // ルートディレクトリのユニークID'0'は含まない
  String path = "/";
  for(int d = 1; d < _directoryStack.length; d++){
    path += _directoryStack[d].uid.toString() + "/";
  }
  return path;
}

// 現在開かれているファイルのフルパスを取得
// 先頭は"/"から始まり、最後はファイル名
String getOpenedFilePath()
{
  String uidPath = getOpenedFileUIDPath();
  String namePath = convertUIDPath2NamePath(uidPath);
  return namePath;
}

// 現在開かれているファイルへのUIDフルパスを取得
// 先頭は"/"から始まり、最後はファイルのユニークID
String getOpenedFileUIDPath()
{
  // ルートディレクトリのユニークID'0'は含まない
  String uidPath = "";
  for(int d = 1; d < _openedUIDPathStack.length; d++){
    final int uid = _openedUIDPathStack[d];
    uidPath = uidPath + "/" + uid.toString();
  }
  if(uidPath == "") uidPath = "/";

  return uidPath;
}

// UIDパスから表示名パスへ変換
String convertUIDPath2NamePath(String uidPath)
{
  List<String> uidsText = uidPath.split("/");
  String namePath = "";
  uidsText.forEach((uidText){
    if(uidText != ""){
      final int uid = int.parse(uidText);
      final String name = _uid2name[uid] ?? uid.toString();
      namePath = namePath + "/" + name;
    }
  });
  return namePath;
}

// 現在開かれているファイル名を取得
String getOpenedFileName()
{
  String name = _uid2name[_openedUIDPathStack.last] ?? "";
  return name;
}

// 開いたファイルへのUIDフルパスを設定
bool setOpenedFileUIDPath(String uidPath)
{
  print(">setOpenedFileUIDPath(${uidPath})");
  bool res = _setOpenedFileUIDPath(uidPath);

  print(">setOpenedFileUIDPath(${uidPath}) ${res}");

  return res;
}

bool _setOpenedFileUIDPath(String uidPath)
{
  // 指定されたパスががカレントディレクトリでなければエラー
  int i = uidPath.lastIndexOf("/");
  if(i < 0) return false;
  var uidDirPart = uidPath.substring(0, i+1);
  final int fileUID = int.parse(uidPath.substring(i+1));
  if(getCurrentUIDPath() != uidDirPart) return false;

  // 指定されたファイルがカレントディレクトリになければエラー
  List<FileItem> currentDir = getCurrentDir();
  FileItem? openedFile;
  currentDir.forEach((item){
    if(item.isFile() && (item.uid == fileUID)){
      openedFile = item;
      return;
    }
  });
  if(openedFile == null) return false;

  // OK
  _openedUIDPathStack.clear();
  _directoryStack.forEach((item){ _openedUIDPathStack.add(item.uid); });
  _openedUIDPathStack.add(openedFile!.uid);

  return true;
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
  final DatabaseReference ref = getDatabaseRef("/");
  final DataSnapshot snapshot = await ref.get();
  var defaultFile = FileItem(uid:_defaultFileUID, name:"デフォルトデータ");
  if(!snapshot.exists){
    final List<Map<String,dynamic>> files = [ defaultFile.getDBData() ];
    ref.set(files);
    // ファイル/フォルダのユニークIDを発行するためのパスも作成
    final DatabaseReference refNextUID = database.ref("fileTreeNextUID");
    refNextUID.set(_firstUserFileID);
  }
  // ルートディレクトリをデータベースから読み込み
  await moveDir(FileItem(uid:_currentDirId));
}

//----------------------------------------------------------------------------
// 新しいユニークIDを発行
Future<int> _getUniqueID() async
{
  // データベースから次のユニークIDを取得
  final DatabaseReference refNextUID = database.ref("fileTreeNextUID");
  final DataSnapshot snapshot = await refNextUID.get();
  int uid = _invalidUID;
  if(snapshot.exists){
    try {
      uid = snapshot.value as int;
    }
    catch(e){}
    // データベース上のユニークIDを新しい値にしておく
    if(uid != _invalidUID){
      refNextUID.set(ServerValue.increment(1));
    }
  }
  return uid;
}

//----------------------------------------------------------------------------
// カレントディレクトリにファイル追加
Future<FileResult> createNewFile(String fileName) async
{
  print(">createNewFile(${fileName})");
  FileResult res = await _addFileItem(fileName, false);

  print(">createNewFile(${fileName}) ${res}");

  return res;
}

// カレントディレクトリにフォルダ追加
Future<FileResult> createNewFolder(String folderName) async
{
  print(">createNewFolder(${folderName})");

  FileResult res = await _addFileItem(folderName, true);

  print(">createNewFolder(${folderName}) ${res}");

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

  // 新しいファイル/フォルダーを、カレントディレクトリに追加
  FileItem newItem = FileItem(uid:uid, name:name);
  if(folder){
    // フォルダを作成する場合には、子階層をぶら下げておく。
    newItem.child = [ FileItem(uid:_parentDirId) ];
  }
  List<FileItem> currentDir = getCurrentDir();
  currentDir.add(newItem);

  // 並びをソートする
  sortDir(currentDir);

  // ディレクトリツリーのデータベースを更新
  updateFileListToDB(getCurrentUIDPath(), currentDir);

  // 作成されたファイルパスを返す
  final String newPath = getCurrentPath() + name;
  final String newUIDPath = getCurrentUIDPath() + uid.toString();

  return FileResult(path:newPath, uidPath:newUIDPath);
}

// カレントディレクトリのファイル名変更
FileResult renameFile(FileItem item, String newName)
{
  print(">renameFile(${item} newName:${newName})");

  FileResult res = _renameFile(item, newName);

  print(">renameFile(${item}) newName:${newName} ${res}");

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

  // データの変更
  item.name = newName;

  // 並びをソートする
  List<FileItem> currentDir = getCurrentDir();
  sortDir(currentDir);

  // ディレクトリツリーのデータベースを更新
  updateFileListToDB(getCurrentUIDPath(), currentDir);

  // 変更されたファイルパスを返す
  final String newPath = getCurrentPath() + newName;
  final String newUIDPath = getCurrentUIDPath() + item.uid.toString();

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

// カレントディレクトリのファイル削除
FileResult deleteFile(FileItem item)
{
  print(">deleteFile(${item})");
  FileResult res = _deleteFile(item);

  print(">deleteFile(${item}) ${res}");

  return res;
}

FileResult _deleteFile(FileItem item)
{
  // エラーチェック
  if(!item.isFile()){
    return FileResult(res:false, message:"内部エラー: deleteFile()にフォルダを指定");
  }
  if(!_canDelete(item.uid)){
    return FileResult(res:false, message:"'デフォルトデータ'等は削除できません");
  }
  final int openedFileUID = _openedUIDPathStack.last;
  if(item.uid == openedFileUID){
    return FileResult(res:false, message:"開いているファイルは削除できません");
  }

  // カレントディレクトリから要素を削除
  List<FileItem> currentDir = getCurrentDir();
  if(!currentDir.remove(item)){
    return FileResult(res:false, message:"削除しようとしたフィルはありません");
  }

  // ディレクトリツリーのデータベースを更新
  updateFileListToDB(getCurrentUIDPath(), currentDir);

  // 配置データも削除する
  final String fileUIDPath = getCurrentUIDPath() + item.uid.toString();
  final String path = "assign" + fileUIDPath;
  final DatabaseReference ref = database.ref(path);
  try{ ref.remove(); } catch(e) {}
  // GPSログも削除する
  GPSLog.deleteFromCloudStorage(fileUIDPath);

  print(">_deleteFile(${item}) delete:${ref.path}");

  return FileResult();
}

// フォルダ削除
Future<FileResult> deleteFolder(FileItem folder) async
{
  print(">deleteFolder(${folder})");
  FileResult res = await _deleteFolder(folder);

  print(">deleteFolder(${folder}) ${res}");

  return res;
}

Future<FileResult> _deleteFolder(FileItem folder) async
{
  // エラーチェック
  if(!folder.isFolder()){
    return FileResult(res:false, message:"内部エラー: deleteFolder()にファイルを指定");
  }
  if(folder.uid == _parentDirId){
    return FileResult(res:false, message:"'上階層に戻る'は削除できません");
  }
  final String folderUID = "/" + folder.uid.toString() + "/";
  if(getOpenedFileUIDPath().indexOf(folderUID) == 0){
    return FileResult(res:false, message:"開いているファイルを含むフォルダは削除できません");
  }

  // フォルダ削除の再帰処理
  await deleteFolderRecursive(folder);

  // フォルダ以下の配置データを削除
  final String path = "assign" + folderUID;
  final DatabaseReference ref = database.ref(path);
  try{ ref.remove(); } catch(e) {}
  print(">_deleteFolder(${folder}) delete:${ref.path}");

  // カレントディレクトリから要素を削除
  List<FileItem> currentDir = getCurrentDir();
  for(int i = 0; i < currentDir.length; i++){
    var item = currentDir[i];
    if(item.isFolder() && (item.uid == folder.uid)){
      currentDir.removeAt(i);
      break;
    }
  }
  // ディレクトリツリーのデータベースを更新
  updateFileListToDB(getCurrentUIDPath(), currentDir);

  return FileResult();
}

// フォルダ削除の再帰処理
Future deleteFolderRecursive(FileItem folder) async
{
  // 指定されたフォルダに降りて、
  await moveDir(folder);

  // その中のディレクトリに再帰しながら削除
  // NOTE: forEach() 使うと await で処理止められない…
  final List<FileItem> currentDir = getCurrentDir();
  for(int i = 0; i < currentDir.length; i++){
    final FileItem item = currentDir[i];
    if(item.isFolder() && (item.uid != _parentDirId)){
      // フォルダを再帰的に削除
      await deleteFolderRecursive(item);
    }
  }

  // データベースから自分自身を削除
  final String path = getCurrentUIDPath();
  final DatabaseReference ref = getDatabaseRef(path);
  try { ref.remove(); } catch(e) {}
  print("deleteFolderRecursive(${folder}) delete:${ref.path}");

  // NOTE: 配置データは、呼び出し元でパスを削除することで、その子階層もまとめて削除される。

  // 親ディレクトリへ戻る
  await moveDir(FileItem(uid:_parentDirId));
}

// ディレクトリ内の並びをソート
void sortDir(List<FileItem> dir)
{
  dir.sort((a, b){
    // 「階層を戻る」が先頭
    if(a.uid == _parentDirId) return -1;
    // フォルダが前
    if(a.isFolder() && !b.isFolder()) return -1;
    if(!a.isFolder() && b.isFolder()) return 1;
    // ファイル名で比較
    return a.name.compareTo(b.name);
  });
}

// 直前の moveDir() が完了するまで、次の処理を破棄するフラグ
bool _blockingMoveDir = false;

// ディレクトリの移動において、処理の完了待ちをする場合の同期フラグ
Completer? _completerMoveDir;

// ディレクトリを移動
// カレントディレクトリから1階層の移動のみ。
Future<bool> moveDir(FileItem folder) async
{
  print(">moveDir(${folder.uid}:${folder.name})");

  // 直前の _moveDir() が終わってなかったら何もしない
  bool res = false;
  if(!_blockingMoveDir){
    _blockingMoveDir = true;
    res = await _moveDir(folder);
    _blockingMoveDir = false;
    print(">moveDir(${folder.uid}:${folder.name}) ${res} " + getCurrentUIDPath());
  }else{
    print(">  Blocking!");
  }
  return res;
}

Future<bool> _moveDir(FileItem folder) async
{
  if(folder.uid != _currentDirId){
    // 移動先は当然フォルダーのみ
    if(!folder.isFolder()) return false;

    if(folder.uid == _parentDirId){
      // 親階層に戻る
      // ルートディレクトリより上には戻れない
      if(_directoryStack.length <= 1) return false;
      _directoryStack.removeLast();
    }else{
      // 下階層に下る
      _directoryStack.add(folder);
    }
  }

  // 移動先ディレクトリの構成をデータベースから取得
  // 取得完了時のイベント内でデータ更新も行い、Completer 用いて同期処理する
  final String uidPath = getCurrentUIDPath();
  DatabaseReference ref = getDatabaseRef(uidPath);
  _completerMoveDir = Completer();
  _currentDirChangeListener?.cancel();
  _currentDirChangeListener = ref.onValue.listen((DatabaseEvent event){
    _onCurrentDirChange(event, uidPath);
  });
  await _completerMoveDir!.future;
  _completerMoveDir = null; 

  return true;
}

// カレントディレクトリの変更通知とデータ更新
void _onCurrentDirChange(DatabaseEvent event, String uidPath) async
{
  //!!!!
  print(">_onCurrentDirChange(${uidPath}) shapshot=${event.snapshot.value}");

  // ここでカレントディレクトリを更新する。
  // NOTE: もし今開いているファイルが削除された場合には、対応できないので何もしない。
  // ディレクトリごと削除される可能性もあり、難しい問題で、今は仕様バグで残してある…。
  List<dynamic> items = [];
  try{
    items = event.snapshot.value as List<dynamic>;
  }catch(e){
  }
  // 「親階層に戻る」を追加
  List<FileItem> receiveDir = _getFileListFromDB(items);
  if(1 < _directoryStack.length){
    receiveDir.add(FileItem(uid:_parentDirId));
  }
  // ソートしておく
  sortDir(receiveDir);

  // GPSログファイルの一覧をクラウドストレージから取得する
  // ファイルに対応するGPSログがあるかどうかをチェック
  final gpsFileList = await gpsLog.getFileList(uidPath);
  receiveDir.forEach((var file){
    if(file.isFile()){
      final String gpxFileName = file.uid.toString() + ".gpx";
      file.gpsLog = gpsFileList.contains(gpxFileName);
    }
  });

  // カレントディレクトリのデータを置き換え
  _directoryStack.last.child = receiveDir;

  // 処理の完了を通知
  _completerMoveDir?.complete();

  // ファイル一覧画面を表示していたら再描画
  _onCurrentDirChangedForFilesPage?.call();
}

// 現在開いているファイルのGPSログの有無フラグを変更
void setOpenedFileGPSLogFlag(bool gpsLog)
{
  // カレントディレクトリに開いているファイルがあれば、フラグをセットする
  // カレントディレクトリが開いているファイルと別の位置なら、moveDir() でセットされる
  List<FileItem> files = getCurrentDir();
  files.forEach((file){
    if(file.uid == _openedUIDPathStack.last){
      file.gpsLog = gpsLog;
      return;
    }
  });
}

// 絶対パスで指定されたディレクトリへ移動
Future<bool> moveFullPathDir(String fullUIDPath) async
{
  print(">moveFullPathDir(${fullUIDPath})");
  bool res = await _moveFullPathDir(fullUIDPath);

  print(">moveFullPathDir(${fullUIDPath}) ${res} " + getCurrentUIDPath());

  return res;
}

Future<bool> _moveFullPathDir(String fullUIDPath) async
{
  // カレントディレクトリをルートに戻す
  while(1 < _directoryStack.length){
    bool res = await moveDir(FileItem(uid:_parentDirId));
    if(!res) return false;
  }

  // 指定されたパスから1階層ずつ入っていく
  while(true){
    // 先頭にパス文字がないのは文字列がおかしい
    if(!fullUIDPath.startsWith("/")) return false;
    // ファイルが指定さてなかったらこれで終わり(成功)
    if(fullUIDPath.length == 1) return true;
    // パス文字で区切られたディレクトリを取り出す
    // ex) /2/9/13 → 2
    // 後ろにパス文字がなければ、残りはフィル名。
    int t = fullUIDPath.indexOf("/", 1);
    final bool isFile = (t < 0);
    if(isFile) t = fullUIDPath.length;
    final int itemUID = int.parse(fullUIDPath.substring(1, t));
    // ファイルが存在するか確認(名前一致の検索)
    final List<FileItem> currentDir = getCurrentDir();
    int i = 0;
    for(; i < currentDir.length; i++){
      if(currentDir[i].uid == itemUID) break;
    }
    if(i == currentDir.length) return false;
    if(isFile && currentDir[i].isFile()) return true;
    // ディレクトリに入る
    final bool res = await moveDir(currentDir[i]);
    if(!res) return false;
    // フルパスから先頭を除く
    // ex) /2/9/13 → /9/13
    fullUIDPath = fullUIDPath.substring(t);
  }

  // ここには来ないはず
  return false;
}

// ディレクトリツリーのデータベースを更新
void updateFileListToDB(String uidPath, final List<FileItem> dir)
{
  final DatabaseReference ref = getDatabaseRef(uidPath);
  List<Map<String,dynamic>> items = [];
  dir.forEach((item){
    // 「親階層に戻る」は除外
    if(item.uid != _parentDirId){
      items.add(item.getDBData());
    }
  });
  try {
    if(0 < items.length){
      ref.set(items);
    }else{
      // ディレクトリが空の場合にはデータベースからは削除
      ref.remove();
    }
  }catch(e){}
}

// ディレクトリツリーのデータベースから、ディレクトリ内のファイル/ディレクトリを取得
Future<List<FileItem>> getFileListFromDB(String path) async
{
  final DatabaseReference ref = getDatabaseRef(path);
  List<dynamic> items = [];
  try{
    final DataSnapshot snapshot = await ref.get();
    items = snapshot.value as List<dynamic>;
  }catch(e){
    // 移動先のディレクトリがなくてもなにもしない。
    // 後でファイル/ディレクトリを追加したときに作成される。
  }

  // ディレクトリのファイル/ディレクトリ一覧を構築
  return _getFileListFromDB(items);
}

List<FileItem> _getFileListFromDB(List<dynamic> items)
{
  // ディレクトリのファイル/ディレクトリ一覧を構築
  List<FileItem> dir = [];
  items.forEach((item){
    // データベースから取得したユニークIDと名前でファイル/ディレクトリを作成
    int uid = _invalidUID;
    try { uid = item["uid"] as int; } catch(e){}
    String name = "";
    try { name = item["name"] as String; } catch(e){}
    if((uid != _invalidUID) && (name != "")){
      // ディレクトリの場合は子階層を付ける
      List<FileItem>? child;
      if(item["folder"] as bool){
        child = [ FileItem(uid:_parentDirId) ];
      }
      dir.add(FileItem(uid:uid, name:name, child:child));
    }
  });
  return dir;
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

    // 他のユーザーによるカレントディレクトリ変更のコールバックを設定
    _onCurrentDirChangedForFilesPage = (){ setState((){}); };

    return WillPopScope(
      // ページ閉じる際の処理
      onWillPop: (){
        // 他のユーザーによる変更のコールバックをクリア
        _onCurrentDirChangedForFilesPage = null;
        Navigator.pop(context);
        return Future.value(false);
      },
      child: Scaffold(
        appBar: _responsiveAppBar.makeAppBar(
          context,
          titleLine: [
            Text(
              getCurrentPath(),
              textScaleFactor: (narrowWidth? 0.8: null),
            ),
          ],
          actionsLine: [
            // (左)フォルダ作成ボタン
            if(!widget.readOnlyMode) IconButton(
              icon: Icon(Icons.create_new_folder),
              onPressed:() async {
                createNewFolderSub(context);
              },
            ),
            // (右)ファイル作成ボタン
            if(!widget.readOnlyMode) IconButton(
              icon: Icon(Icons.note_add),
              onPressed:() async {
                createNewFileSub(context);
              },
            ),
          ],
          setState: setState,
        ),
        // カレントディレクトリのファイル/ディレクトリを表示
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
      if(file.isFile()){
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
    final String thisUIDPath = getCurrentUIDPath() + currentDir[index].uid.toString();
    final String openedUIDPath = getOpenedFileUIDPath();
    late bool isOpenedFile;
    if(currentDir[index].isFile()){
      // ファイルの場合はパスの完全一致で判定
      isOpenedFile = (openedUIDPath == thisUIDPath);
    }else{
      // フォルダの場合は、パスの先頭一致で判定
      isOpenedFile = (openedUIDPath.indexOf(thisUIDPath+"/") == 0);
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
          if(currentDir[index].isFile()){
            if(enable){
              // 他のユーザーによる変更のコールバックをクリア
              _onCurrentDirChangedForFilesPage = null;
              // ファイルを切り替える
              widget.onSelectFile(thisUIDPath);
              Navigator.pop(context);
            }
          }else{
            // ディレクトリ移動
            // NOTE: データベース読み込みの完了イベント内で setState() しているのでここでは不要。
            moveDir(currentDir[index]);
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
    ).then((value) {
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
        deleteFileSub(context, item).then((_){
          setState((){});
        });
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
      // 他のユーザーによる変更のコールバックをクリア
      _onCurrentDirChangedForFilesPage = null;
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
    var res = await createNewFolder(name);
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
    final String typeText = item.isFile()? "ファイル": "フォルダ";
    final String message = typeText + "「" + item.name + "」を削除しますか？";
    bool? ok = await showOkCancelDialog(context, text:message);
    if((ok != null)? !ok: true) return;

    // 削除処理
    late FileResult res;
    if(item.isFile()){
      res = deleteFile(item);
    }else{
      await deleteFolder(item).then((r){ res = r; });
    }

    if(res.res){
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
