import 'package:flutter/material.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 汎用テキスト入力ダイアログ

class TextEditDialog extends StatefulWidget
{
  TextEditDialog({
    super.key,
    this.titleText = "",
    this.hintText,
    this.defaultText,
    this.okText = "決定",
  }){}

  String titleText = "";
  String? hintText;
  String? defaultText;
  String okText;

  @override
  State createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<TextEditDialog>
{
  @override
  Widget build(BuildContext context) {
    final dateTextController = TextEditingController(text: widget.defaultText);

    return AlertDialog(
      title: Text(widget.titleText),
      content: TextField(
        controller: dateTextController,
        decoration: (widget.hintText != null)? InputDecoration(hintText: widget.hintText): null,
        autofocus: true,
      ),
      actions: [
        ElevatedButton(
          child: Text("キャンセル"),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(
          child: Text(widget.okText),
          onPressed: () {
            Navigator.pop<String>(context, dateTextController.text);
          },
        ),
      ],
    );
  }
}
