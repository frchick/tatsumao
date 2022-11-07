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
  late TextEditingController _dateTextController;

  @override
  void initState()
  {
    super.initState();

    _dateTextController = TextEditingController(text: widget.defaultText);
  }

  @override
  Widget build(BuildContext context) {

    return AlertDialog(
      title: Text(widget.titleText),
      content: TextField(
        controller: _dateTextController,
        decoration: InputDecoration(hintText: widget.hintText),
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
            Navigator.pop<String>(context, _dateTextController.text);
          },
        ),
      ],
    );
  }
}
