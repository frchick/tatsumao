import 'package:flutter/material.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// はい/いいえダイアログ
class OkCancelDialog extends StatefulWidget
{
  OkCancelDialog({
    super.key,
    this.titleText = "",
  }){}

  String titleText = "";

  @override
  State createState() => _OkCancelDialogState();
}

class _OkCancelDialogState extends State<OkCancelDialog>
{
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titleText),
      actions: [
        ElevatedButton(
          child: Text("キャンセル"),
          onPressed: (){
            Navigator.pop<bool>(context, false);
          }
        ),
        ElevatedButton(
          child: Text("OK"),
          onPressed: (){
            Navigator.pop<bool>(context, true);
          },
        ),
      ],
    );
  }
}

//----------------------------------------------------------------------------
// はい/いいえダイアログを表示
Future<bool?> showOkCancelDialog(BuildContext context, String text)
{
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return OkCancelDialog(titleText:text);
    },
  );
}
