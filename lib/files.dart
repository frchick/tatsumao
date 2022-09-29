import 'package:flutter/material.dart';

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
// ファイル一覧画面

class FileItem {
  FileItem({
    required this.name,
    this.child,
  });
  // ファイル/ディレクトリ名
  String name;
  // 子階層
  List<FileItem>? child;
}

List<FileItem> _file202211 = [
  FileItem(name:"上階層へ戻る"),
  FileItem(name:"11月1日R1 ホンダメ"),
  FileItem(name:"11月1日R2 暗闇沢"),
  FileItem(name:"11月2日R1 笹原林道"),
  FileItem(name:"11月2日R2 桧山"),
  FileItem(name:"11月8日R1 金太郎上"),
  FileItem(name:"11月8日R2 金太郎571"),
];

List<FileItem> _file202212 = [
  FileItem(name:"上階層へ戻る"),
  FileItem(name:"12月3日R1 マムシ沢"),
  FileItem(name:"12月3日R2 ミョウガ谷"),
  FileItem(name:"12月10日R1 苅野上"),
  FileItem(name:"12月10日R2 暗闇沢"),
  FileItem(name:"12月11日R1 桧山下"),
  FileItem(name:"12月11日R2 桧山"),
];

List<FileItem> _file202301 = [
  FileItem(name:"上階層へ戻る"),
  FileItem(name:"1月3日R1 狩猟初め！"),
  FileItem(name:"1月3日R2 ジビエBBQ"),
  FileItem(name:"1月6日R1 21世紀の森遠征"),
  FileItem(name:"1月7日R1 グリーンヒル"),
  FileItem(name:"1月7日R2 ガマハウスBBQ"),
];

List<FileItem> _file202302 = [
  FileItem(name:"上階層へ戻る"),
  FileItem(name:"2月3日R1 ホンダメ"),
  FileItem(name:"2月3日R2 苅野上"),
  FileItem(name:"2月6日R1 暗闇沢"),
  FileItem(name:"2月6日R2 桧山下"),
  FileItem(name:"2月28日R1 狩猟納！"),
  FileItem(name:"2月28日R2 打ち上げBBQ"),
];

List<FileItem> _file2022 = [
  FileItem(name:"上階層へ戻る"),
  FileItem(name:"2022年11月", child:_file202211),
  FileItem(name:"2022年12月", child:_file202212),
  FileItem(name:"2023年1月", child:_file202301),
  FileItem(name:"2023年2月", child:_file202302),
];

List<FileItem> _file202311 = [
  FileItem(name:"上階層へ戻る"),
  FileItem(name:"11月1日R1 小土肥1"),
  FileItem(name:"11月1日R2 小土肥2"),
  FileItem(name:"11月2日R1 未定"),
  FileItem(name:"11月2日R2 未定"),
  FileItem(name:"11月8日R1 未定"),
  FileItem(name:"11月8日R2 未定"),
];

List<FileItem> _file202312 = [
  FileItem(name:"上階層へ戻る"),
  FileItem(name:"12月3日R1 未定"),
  FileItem(name:"12月3日R2 未定"),
  FileItem(name:"12月10日R1 未定"),
  FileItem(name:"12月10日R2 未定"),
  FileItem(name:"12月11日R1 未定"),
  FileItem(name:"12月11日R2 未定"),
];

List<FileItem> _file202401 = [
  FileItem(name:"上階層へ戻る"),
  FileItem(name:"1月3日R1 狩猟初め！"),
  FileItem(name:"1月3日R2 ジビエBBQ"),
  FileItem(name:"1月6日R1 未定"),
  FileItem(name:"1月7日R1 未定"),
  FileItem(name:"1月7日R2 未定"),
];

List<FileItem> _file202402 = [
  FileItem(name:"上階層へ戻る"),
  FileItem(name:"2月3日R1 未定"),
  FileItem(name:"2月3日R2 未定"),
  FileItem(name:"2月6日R1 未定"),
  FileItem(name:"2月6日R2 未定"),
  FileItem(name:"2月28日R1 狩猟納！"),
  FileItem(name:"2月28日R2 打ち上げBBQ"),
];

List<FileItem> _file2023 = [
  FileItem(name:"上階層へ戻る"),
  FileItem(name:"2023年11月", child:_file202311),
  FileItem(name:"2023年12月", child:_file202312),
  FileItem(name:"2024年1月", child:_file202401),
  FileItem(name:"2024年2月", child:_file202402),
];

List<FileItem> _fileRoot = [
  FileItem(name:"2022シーズン", child:_file2022),
  FileItem(name:"2023シーズン", child:_file2023),
  FileItem(name:"default_data"),
  FileItem(name:"11月1日R1 ホンダメ"),
];

// ルートから現在のディレクトリまでのスタック
List<FileItem> _directoryStack = [];

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
            if((0 < stackDepth) && (index == 0)){
              //「上階層に戻る」
              icon = Icons.drive_file_move_rtl;
            }else{
              // ファイルかフォルダ
              icon = (file.child == null)? Icons.description: Icons.folder;
            }
            return _menuItem(context, index, file.name, Icon(icon));
          }
        ),        

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
                onPressed: () async {
                  // ファイル作成
                  String? path = await showCreateFileDialog(context);
                  print("showCreateFileDialog() -> $path");
                },
              ),
              // フォルダ作成ボタン
              ElevatedButton(
                child: Icon(Icons.create_new_folder, size: 50),
                style: _appIconButtonStyle,
                onPressed: () async {
                  // フォルダ作成
                  String? path = await showCreateFolderDialog(context);
                  print("showCreateFolderDialog() -> $path");
                }
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
          if((0 < _directoryStack.length) && (index == 0)){
            // 親階層に戻る
            setState((){
              _directoryStack.removeLast();
            });
            return;
          }
          var currentDir = getCurrentDir();
          if(currentDir == null) return;  // ありえない
          if(currentDir[index].child == null){
            // ファイルを切り替える
            String path = getCurrentPath() + currentDir[index].name;
            if(widget.onSelectFile != null){
              widget.onSelectFile!(path);
            }
            Navigator.pop(context);
          }else{
            // ディレクトリを下る
            setState((){
              _directoryStack.add(currentDir[index]);
            });
          }
        },
      ),
    );
  }

  // カレントディレクトリを参照
  List<FileItem>? getCurrentDir()
  {
    final int stackDepth = _directoryStack.length;
    return (stackDepth == 0)? _fileRoot: _directoryStack[stackDepth-1].child;
  }

  // カレントディレクトリへのフルパスを取得
  String getCurrentPath()
  {
    String path = "";
    _directoryStack.forEach((folder){
      path += folder.name + "/";
    });
    return path;
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