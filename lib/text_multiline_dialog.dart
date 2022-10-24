import 'package:flutter/material.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 複数行テキストを表示するダイアログ
class TextMultilineDialog extends StatelessWidget
{
  TextMultilineDialog({
    super.key,
    required this.title,
    required this.text,
    double? width,
  }) : _width = (width ?? 300)
  {
  }

  // タイトル
  final String title;
  // 文字列(改行コード使った複数行)
  final String text;
  // ダイアログ幅
  final double _width;

  // スクロールバー
  // NOTE: 常にスクロールバーを表示する場合には、外から指定する必要あり
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context)
  {
    // 改行コードで区切られたテキスト行を、それぞれ Text Widget として登録する。
    // 単一の Text Widget だと、長い文字列の右端を「...」で消すと、それ以降の行が消えてしまうため。
    List<Text> textLines = [];
    int sp = 0;
    while(true)
    {
      int p = text.indexOf("\n", sp);
      late String line;
      if(p < 0){
        line = text.substring(sp);
      }else{
        line = text.substring(sp, p);
        sp = p + 1;
      }
      textLines.add(Text(line, overflow: TextOverflow.ellipsis));
      if(p < 0) break;
    }

    return AlertDialog(
      title: Text(title),
      content: Container(
        width: _width,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: textLines,
            )
          )
        )
      ),
      actions: [
        ElevatedButton(
          child: Text("キャンセル"),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(
          child: Text("OK"),
          onPressed: () {
            // 選択された文字列を返す
            Navigator.pop<bool>(context, true);
          },
        ),
      ],
    );
  }
}

//----------------------------------------------------------------------------
// 複数行テキストダイアログを表示
Future<bool?> showMultilineTextDialog(
  BuildContext context, String title, String text, [ double? width ])
{
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return TextMultilineDialog(title:title, text:text, width:width);
    },
  );
}
