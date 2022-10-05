import 'package:flutter/material.dart';

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------
// はい/いいえダイアログ
class OkCancelDialog extends StatefulWidget
{
  OkCancelDialog({
    super.key,
    this.titleText,
    this.contentText,
    this.showCancelButton = true,
  });

  String? titleText;
  String? contentText;
  bool showCancelButton;

  @override
  State createState() => _OkCancelDialogState();
}

class _OkCancelDialogState extends State<OkCancelDialog>
{
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: (widget.titleText != null)? Text(widget.titleText!): null,
      content: (widget.contentText != null)? Text(widget.contentText!): null,
      actions: [
        if(widget.showCancelButton) ElevatedButton(
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
Future<bool?> showOkCancelDialog(
  BuildContext context, { String? title, String? text })
{
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return OkCancelDialog(titleText:title, contentText:text);
    },
  );
}

//----------------------------------------------------------------------------
// OKダイアログを表示
Future<bool?> showOkDialog(
  BuildContext context, { String? title, String? text })
{
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return OkCancelDialog(
        titleText:title, contentText:text, showCancelButton:false);
    },
  );
}
