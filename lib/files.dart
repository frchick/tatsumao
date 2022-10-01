import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

//----------------------------------------------------------------------------
// グローバル変数

// アイコンボタン共通のスタイル
final ButtonStyle _appIconButtonStyle = ElevatedButton.styleFrom(
  foregroundColor: Colors.orange.shade900,
  backgroundColor: Colors.transparent,
  shadowColor: Colors.transparent,
  fixedSize: Size(80,80),
);


//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// ファイル一覧

class FileItem {
  FileItem({
    required this.name,
    this.child,
  });
  // ファイル/ディレクトリ名
  String name;
  // 子階層
  List<FileItem>? child;

  // ファイルか？
  bool isFile(){ return (name != "..") && (child == null); }
  // フォルダか？
  bool isFolder(){ return (name == "..") || (child != null); }
}

// ルートノード
FileItem _fileRoot = FileItem(name:"");

// ルートから現在のディレクトリまでのスタック
List<FileItem> _directoryStack = [ _fileRoot ];

//ファイルツリーの共有(Firebase RealtimeDataBase)
FirebaseDatabase database = FirebaseDatabase.instance;

// Firebase RealtimeDataBase の参照パス
final _fileRootPath = "fileTree/";

//----------------------------------------------------------------------------
// 汎用
class FileResult
{
  FileResult({ this.res=true, this.message="", this.path="" }){}

  bool res;
  String message;
  String path;
}

//----------------------------------------------------------------------------
// 初期化
Future initFileTree() async
{
  // データベースにルートディレクトリが記録されていなければ、
  // デフォルトのファイル(default_data)と共に登録。
  final DatabaseReference ref = database.ref(_fileRootPath + "~");
  final DataSnapshot snapshot = await ref.get();
  if(!snapshot.exists){
    List<String> files = [ "default_data" ];
    ref.set(files);
  }
  // ルートディレクトリをデータベースから読み込み
  moveDir(FileItem(name:"."));
}

//----------------------------------------------------------------------------
// ファイル追加
FileResult createNewFile(String fileName)
{
  return addFileItem(fileName, false);
}

// フォルダ追加
FileResult createNewFolder(String folderName)
{
  return addFileItem(folderName, true);
}

// ファイル/フォルダ追加の共通処理
FileResult addFileItem(String name, bool folder)
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

  // 新しいファイル/フォルダーを、カレントディレクトリに追加
  FileItem newItem = FileItem(name:name);
  if(folder){
    // フォルダを作成する場合には、子階層をぶら下げておく。
    newItem.child = [ FileItem(name:"..") ];
  }
  currentDir.add(newItem);

  // 並びをソートする
  sortDir(currentDir);

  // ディレクトリツリーのデータベースを更新
  updateFileListToDB(getCurrentPath(), currentDir);

  // 作成されたファイルパスを返す
  String newPath = getCurrentPath() + name;

  return FileResult(path:newPath);
}

// ディレクトリ内の並びをソート
void sortDir(List<FileItem> dir)
{
  dir.sort((a, b){
    // 「階層を戻る」が先頭
    if(a.name == "..") return -1;
    // フォルダが前
    if(a.isFolder() && !b.isFolder()) return -1;
    if(!a.isFolder() && b.isFolder()) return 1;
    // ファイル名で比較
    return a.name.compareTo(b.name);
  });
}

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

// ディレクトリを移動
// カレントディレクトリから1階層の移動のみ。
Future<bool> moveDir(FileItem folder) async
{
  // "."はカレントディレクトリへの移動で、実際にはカレントディレクトリの再構築
  if(folder.name != "."){
    // 移動先は当然フォルダーのみ
    if(!folder.isFolder()) return false;

    if(folder.name == ".."){
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
  List<FileItem> currentDir = await getFileListFromDB(getCurrentPath());
  // ルート以外(より下階層)なら「親階層に戻る」を追加
  if(1 < _directoryStack.length){
    currentDir.add(FileItem(name:".."));
  }
  // 並びをソートする
  sortDir(currentDir);

  // カレントディレクトリのデータを置き換え
  _directoryStack[_directoryStack.length-1].child = currentDir;

  return true;
}

// ディレクトリツリーのデータベースを更新
void updateFileListToDB(String path, List<FileItem> dir)
{
  // ディレクトリの階層構造をDBの階層構造として扱わない！
  // そのためパスセパレータ'/'を、セパレータではない文字'~'に置き換えて、階層構造を作らせない。
  // DatabaseReference.get() でのデータ転送量をケチるため。
  String databasePath = path.replaceAll("/", "~");
  final DatabaseReference ref = database.ref(_fileRootPath + databasePath);
  List<String> names = [];
  dir.forEach((item){
    // 「親階層に戻る」は除外
    String name = item.name;
    if(name != ".."){
      // フォルダの場合には名前に"/"を追加
      names.add(name + ((item.child != null)? "/": ""));
    }
  });
  ref.set(names);
}

// ディレクトリツリーのデータベースから、ディレクトリ内のファイル/ディレクトリを取得
Future<List<FileItem>> getFileListFromDB(String path) async
{
  // ディレクトリの階層構造をDBの階層構造として扱わない！
  // そのためパスセパレータ'/'を、セパレータではない文字'~'に置き換えて、階層構造を作らせない。
  // DatabaseReference.get() でのデータ転送量をケチるため。
  String databasePath = path.replaceAll("/", "~");
  final DatabaseReference ref = database.ref(_fileRootPath + databasePath);
  List<dynamic> names = [];
  try{
    final DataSnapshot snapshot = await ref.get();
    names = snapshot.value as List<dynamic>;
  }catch(e){
    // 移動先のディレクトリがなくてもなにもしない。
    // 後でファイル/ディレクトリを追加したときに作成される。
  }

  // ディレクトリのファイル/ディレクトリ一覧を構築
  List<FileItem> dir = [];
  names.forEach((_name){
    // データベースから取得した名前でファイル/ディレクトリを作成
    // もし名前を取得できなければ破棄
    String name = "";
    try { name = _name as String; } catch(e){}
    if(name != ""){
      FileItem item = FileItem(name:"");
      // 名前の後ろに"/"が付いているのはディレクトリ
      if(name.substring(name.length-1) == "/"){
        item.child = [ FileItem(name:"..") ];
        name = name.substring(0, name.length-1);
      }
      item.name = name;
      dir.add(item);
    }
  });

  return dir;
}

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
  final _textStyle = TextStyle(
    color:Colors.black, fontSize:18.0
  );
  final _borderStyle = Border(
    bottom: BorderSide(width:1.0, color:Colors.grey)
  );

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // カレントディレクトリのファイル/ディレクトリを表示
    final int stackDepth = _directoryStack.length;
    final List<FileItem>? currentDir = getCurrentDir();

    return Scaffold(
      appBar: AppBar(
        title: Text('File and Folder'),
      ),
      body: Stack(children: [
        // ファイル/フォルダー一覧
        ListView.builder(
          itemCount: currentDir!.length,
          itemBuilder: (context, index){
            // アイコンを選択
            var file = currentDir[index];
            IconData icon;
            late String name;
            if((1 < stackDepth) && (index == 0)){
              //「上階層に戻る」
              name = "上階層に戻る";
              icon = Icons.drive_file_move_rtl;
            }else{
              // ファイルかフォルダ
              name = file.name;
              icon = (file.child == null)? Icons.description: Icons.folder;
            }
            return _menuItem(context, index, name, Icon(icon));
          }
        ),        

        // ファイル/フォルダー追加ボタン
        Align(
          // 画面右下に配置
          alignment: Alignment(1.0, 1.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
            // ファイル作成ボタン
              ElevatedButton(
                child: Icon(Icons.note_add, size: 50),
                style: _appIconButtonStyle,
                onPressed: () {
                  createNewFileSub(context);
                },
              ),
              // フォルダ作成ボタン
              ElevatedButton(
                child: Icon(Icons.create_new_folder, size: 50),
                style: _appIconButtonStyle,
                onPressed: () {
                  createNewFolderSub(context);
                },
              )
            ]
          ),
        ),
      ])
    );
  }

  // ファイル一覧アイテムの作成
  Widget _menuItem(BuildContext context, int index, String text, Icon icon) {
    return Container(
      // ファイル間の境界線
      decoration: BoxDecoration(border:_borderStyle),
      // アイコンとファイル名
      child:ListTile(
        leading: icon,
        title: Text(text, style:_textStyle),
        // タップでファイルを切り替え
        onTap: () {
          var currentDir = getCurrentDir();
          if(currentDir[index].isFile()){
            // ファイルを切り替える
            String path = getCurrentPath() + currentDir[index].name;
            if(widget.onSelectFile != null){
              widget.onSelectFile!(path);
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
    var res = createNewFile(name);
    if(res.res){
      // 作成が成功したら、切り替えてマップに戻る
      if(widget.onSelectFile != null){
        widget.onSelectFile!(res.path);
      }
      Navigator.pop(context);
    }else{
      // エラーメッセージ
      showDialog(
        context: context,
        builder: (_){ return AlertDialog(content: Text(res.message)); }
      );
    }
  }

  // フォルダ作成
  void createNewFolderSub(BuildContext context) async
  {
    // ファイル名入力ダイアログ
    String? name = await showCreateFolderDialog(context);
    if(name == null) return;

    // 作成
    var res = createNewFolder(name);
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
}

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 汎用テキスト入力ダイアログ

class TextEditDialog extends StatefulWidget
{
  TextEditDialog({
    super.key,
    this.titleText = "",
    this.hintText = "",
  }){}

  String titleText = "";
  String hintText = "";

  @override
  State createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<TextEditDialog>
{
  final dateTextController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titleText),
      content: TextField(
        controller: dateTextController,
        decoration: InputDecoration(
          hintText: widget.hintText,
        ),
        autofocus: true,
      ),
      actions: [
        ElevatedButton(
          child: Text("キャンセル"),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(
          child: Text("作成"),
          onPressed: () {
            int seconds = int.tryParse(dateTextController.text) ?? 0;
            Navigator.pop<String>(context, dateTextController.text);
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    dateTextController.dispose();
    super.dispose();
  }
}

//----------------------------------------------------------------------------
// ファイル名入力ダイアログ
Future<String?> showCreateFileDialog(BuildContext context)
{
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return TextEditDialog(titleText:"ファイルの作成", hintText:"新規ファイル名");
    },
  );
}

//----------------------------------------------------------------------------
// フォルダ名入力ダイアログ
Future<String?> showCreateFolderDialog(BuildContext context)
{
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return TextEditDialog(titleText:"フォルダの作成", hintText:"新規フォルダ名");
    },
  );
}