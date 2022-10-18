import 'package:flutter/material.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// テキストのリストから選択するダイアログ
class TextItemListDialog extends StatefulWidget
{
  TextItemListDialog({
    super.key,
    required this.title,
    required this.items,
  });

  // タイトル
  final String title;
  // 選択肢
  final List<String> items;

  @override
  State createState() => _TextItemListDialogState();
}

class _TextItemListDialogState extends State<TextItemListDialog>
{
  // 選択されている項目番号
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context)
  {
    return AlertDialog(
      title: Text(widget.title),
      content: Container(
        width: 0,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.items.length,
          itemBuilder: (BuildContext context, int index)
          {
            final bool selected = (_selectedIndex == index);
            return Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(width: 1.0, color: Colors.grey))
              ),
              child: ListTile(
                leading: (selected?
                  const Icon(Icons.check_box_outlined): 
                  const Icon(Icons.check_box_outline_blank)),
                title: Text(widget.items[index]),
                selected: selected,
                // タップで選択
                onTap:(){
                  setState((){
                    _selectedIndex = index;
                  });
                },
              ),
            );
          },
        ),
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
            Navigator.pop<String>(context, widget.items[_selectedIndex]);
          },
        ),
      ],
    );
  }
}
