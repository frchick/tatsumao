import 'package:flutter/material.dart';

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
