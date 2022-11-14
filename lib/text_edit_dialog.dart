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
    this.cancelText = "キャンセル",
  }){}

  String titleText = "";
  String? hintText;
  String? defaultText;
  String okText;
  String? cancelText;

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
        if(widget.cancelText != null) ElevatedButton(
          child: Text(widget.cancelText!),
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
