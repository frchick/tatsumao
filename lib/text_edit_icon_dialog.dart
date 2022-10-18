import 'package:flutter/material.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// 汎用テキスト入力ダイアログ

class TextEditIconDialog extends StatefulWidget
{
  TextEditIconDialog({
    super.key,
    required this.icon,
    required this.onIconTap,
    this.titleText = "",
    this.hintText,
    this.defaultText,
    this.okText = "決定",
  }){}

  final IconData icon;
  String titleText = "";
  String? hintText;
  String? defaultText;
  String okText;
  late Future<String?> Function(BuildContext) onIconTap;

  @override
  State createState() => _TextEditIconDialogState();
}

class _TextEditIconDialogState extends State<TextEditIconDialog>
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
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(widget.titleText),
          IconButton(
            icon: Icon(widget.icon),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: (){
              widget.onIconTap(context).then((text){
                if(text != null){
                  setState((){
                    _dateTextController.text = text;
                  });
                }
              });
            },
          ),
        ],
      ),
      content: TextField(
        controller: _dateTextController,
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
            Navigator.pop<String>(context, _dateTextController.text);
          },
        ),
      ],
    );
  }
}
