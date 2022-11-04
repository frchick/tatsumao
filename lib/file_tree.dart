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

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// ファイル/ディレクトリ階層構造

class FileItem {
  FileItem({
    required this.uid,
    this.name = "",
    this.child,
  });
  // ユニークID
  final int uid;
  // ファイル/ディレクトリ名
  String name;
  // 子階層
  List<FileItem>? child;

  // ファイルか？
  bool isFile(){ return (0 < uid) && (child == null); }
  // フォルダか？
  bool isFolder(){ return (uid <= 0) || (child != null); }

  // データベースに格納するMapを取得
  Map<String,dynamic> getDBData()
  {
    return { "uid": uid, "name": name, "folder": isFolder() };
  }

  @override
  String toString ()
  {
    return "${uid}:${name}";
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

// ルートノード
FileItem _fileRoot = FileItem(uid:_rootDirId, name:"");

// ルートから現在のディレクトリまでのスタック
List<FileItem> _directoryStack = [ _fileRoot ];

// 現在開いているファイル
// カレントディレクトリ内のファイルであるはず。
FileItem? _openedFile;

// 現在開いているディレクトリへのユニークIDでのフルパス
// ファイルを開いた時点で確定
// ファイル一覧画面でのディレクトリ移動では変更されない
String _openedUIDPath = "/";

// 現在開いているディレクトリへのフルパス
// _openedUIDPath と同じパスを表示名で表したデータ
String _openedPath = "/";

//ファイルツリーの共有(Firebase RealtimeDataBase)
FirebaseDatabase database = FirebaseDatabase.instance;

// Firebase RealtimeDataBase の参照パス
final _fileRootPath = "fileTree2/";

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
  var path = _openedPath + (_openedFile?.name ?? "");
  return path;
}

// 現在開かれているファイルへのUIDフルパスを取得
// 先頭は"/"から始まり、最後はファイルのユニークID
String getOpenedFileUIDPath()
{
  var path = _openedUIDPath + (_openedFile?.uid.toString() ?? "");
  return path;
}

// 現在開かれているファイル名を取得
String getCurrentFileName()
{
  return (_openedFile?.name ?? "");
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
  FileItem? openFile;
  currentDir.forEach((item){
    if(item.isFile() && (item.uid == fileUID)){
      openFile = item;
      return;
    }
  });
  if(openFile == null) return false;

  // OK
  _openedUIDPath = uidDirPart;
  _openedPath = getCurrentPath();
  _openedFile = openFile;

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
  final DatabaseReference ref = database.ref(_fileRootPath + "~");
  final DataSnapshot snapshot = await ref.get();
  var defaultFile = FileItem(uid:_defaultFileUID, name:"デフォルトデータ");
  if(!snapshot.exists){
    final List<Map<String,dynamic>> files = [ defaultFile.getDBData() ];
    ref.set(files);
    // ファイル/フォルダのユニークIDを発行するためのパスも作成
    final DatabaseReference refNextUID = database.ref("fileTreeNextUID");
    refNextUID.set(2);
  }
  // ルートディレクトリをデータベースから読み込み
  await moveDir(FileItem(uid:_currentDirId));
  // とりあえず、ルートのデフォルトデータを開いたことにしておく
  _openedUIDPath = "/";
  _openedPath = "/";
  _openedFile = defaultFile;
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
  List<FileItem> currentDir = getCurrentDir();

  // エラーチェック
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
  bool res = true;
  currentDir.forEach((item){
    if(item.name == name) res = false;
  });
  if(!res){
    return FileResult(res:false, message:"既にあるファイル名は使えません");
  }

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
  if((_directoryStack.length == 1) && (item.uid == _defaultFileUID)){
    return FileResult(res:false, message:"'デフォルトデータ'は削除できません");
  }
  if(item.uid == (_openedFile?.uid ?? _invalidUID)){
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
  final String databasePath = _fileRootPath + path.replaceAll("/", "~");
  final DatabaseReference ref = database.ref(databasePath);
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

// ディレクトリを移動
// カレントディレクトリから1階層の移動のみ。
Future<bool> moveDir(FileItem folder) async
{
  print(">moveDir(${folder.uid}:${folder.name})");
  bool res = await _moveDir(folder);

  print(">moveDir(${folder.uid}:${folder.name}) ${res} " + getCurrentUIDPath());

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
  List<FileItem> currentDir = await getFileListFromDB(getCurrentUIDPath());
  // ルート以外(より下階層)なら「親階層に戻る」を追加
  if(1 < _directoryStack.length){
    currentDir.add(FileItem(uid:_parentDirId));
  }
  // 並びをソートする
  sortDir(currentDir);

  // カレントディレクトリのデータを置き換え
  _directoryStack[_directoryStack.length-1].child = currentDir;

  return true;
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
void updateFileListToDB(String uidPath, List<FileItem> dir)
{
  // ディレクトリの階層構造をDBの階層構造として扱わない！
  // そのためパスセパレータ'/'を、セパレータではない文字'~'に置き換えて、階層構造を作らせない。
  // DatabaseReference.get() でのデータ転送量をケチるため。
  final String databasePath = uidPath.replaceAll("/", "~");
  final DatabaseReference ref = database.ref(_fileRootPath + databasePath);
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
  // ディレクトリの階層構造をDBの階層構造として扱わない！
  // そのためパスセパレータ'/'を、セパレータではない文字'~'に置き換えて、階層構造を作らせない。
  // DatabaseReference.get() でのデータ転送量をケチるため。
  final String databasePath = path.replaceAll("/", "~");
  final DatabaseReference ref = database.ref(_fileRootPath + databasePath);
  List<dynamic> items = [];
  try{
    final DataSnapshot snapshot = await ref.get();
    items = snapshot.value as List<dynamic>;
  }catch(e){
    // 移動先のディレクトリがなくてもなにもしない。
    // 後でファイル/ディレクトリを追加したときに作成される。
  }

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
    required this.onSelectFile
  }){}

  // ファイル選択決定時のコールバック
  final Function(String)? onSelectFile;

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
  Border _borderStyle = const Border(
    bottom: BorderSide(width:1.0, color:Colors.grey)
  );

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final List<FileItem> currentDir = getCurrentDir();
    return Scaffold(
      appBar: AppBar(
        title: Text("ファイル：" + getCurrentPath()),
        actions: [
          // (左)フォルダ作成ボタン
          IconButton(
            icon: Icon(Icons.create_new_folder),
            onPressed:() async {
              createNewFolderSub(context);
            },
          ),
          // (右)ファイル作成ボタン
          IconButton(
            icon: Icon(Icons.note_add),
            onPressed:() async {
              createNewFileSub(context);
            },
          ),
        ],
      ),
      // カレントディレクトリのファイル/ディレクトリを表示
      body: ListView.builder(
        itemCount: currentDir.length,
        itemBuilder: (context, index){
          return _menuItem(context, index);
        }
      ),        
    );
  }

  // ファイル一覧アイテムの作成
  Widget _menuItem(BuildContext context, int index) {
    // アイコンを選択
    final int stackDepth = _directoryStack.length;
    final List<FileItem> currentDir = getCurrentDir();
    var file = currentDir[index];
    IconData icon;
    late String name;
    bool goParentDir;
    if((1 < stackDepth) && (index == 0)){
      //「上階層に戻る」
      goParentDir = true;
      name = "上階層に戻る";
      icon = Icons.drive_file_move_rtl;
    }else{
      // ファイルかフォルダ
      goParentDir = false;
      name = file.name;
      icon = (file.child == null)? Icons.description: Icons.folder;
    }

    // 現在開いているファイルとその途中のフォルダは、強調表示する。
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

    // 「上階層に戻る」と、現在開いているファイルの途中は、削除アイコン表示しない。
    final bool showDeleteIcon = !(goParentDir || isOpenedFile);

    return Container(
      // ファイル間の境界線
      decoration: BoxDecoration(border:_borderStyle),
      // アイコンとファイル名
      child:ListTile(
        // (左側)ファイル/フォルダーアイコン
        leading: Icon(icon),
        iconColor: (isOpenedFile? Colors.black: null),

        // ファイル名
        title: Text(name,
          style: (isOpenedFile? _textStyleBold: _textStyle),
        ),

        // (右側)削除ボタン
        trailing: !showDeleteIcon? null: IconButton(
          icon: Icon(Icons.delete),
          onPressed:() {
            deleteFileSub(context, currentDir[index]).then((_){
              setState((){});
            });
          },
        ),

        // タップでファイルを切り替え
        onTap: () {
          if(currentDir[index].isFile()){
            // ファイルを切り替える
            if(widget.onSelectFile != null){
              widget.onSelectFile!(thisUIDPath);
            }
            Navigator.pop(context);
          }else{
            // ディレクトリ移動
            moveDir(currentDir[index]).then((_){
              setState((){});
            });
          }
        },
      ),
    );
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
      // 作成が成功したら、切り替えてマップに戻る
      if(widget.onSelectFile != null){
        widget.onSelectFile!(res.uidPath);
      }
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
  final areaNames = getAreaNames();
  String? areaName = await showDialog<String>(
    context: context,
    builder: (context) {
      return TextItemListDialog(title: "エリア", items: areaNames);
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
