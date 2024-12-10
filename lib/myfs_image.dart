import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mutex/mutex.dart';

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// 作成済みの Image Widget のキャッシュ
Map<String, Widget> _imageCache = {};

// Google Cloud Storage for firebase のバケットURL
String _bucketURL = "";
final _mutex = Mutex();


//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
// Firebase Storage からの画像取得
// 事前に Firebase Storage を構成して、クロスサイトオリジンを許可すること。
class MyFSImage extends StatefulWidget
{
  const MyFSImage(this.gsPath, { super.key, this.loadingIcon, this.errorIcon });

  final String gsPath;
  final Widget ?loadingIcon;
  final Widget ?errorIcon;

  @override
  State<MyFSImage> createState() => _MyFSImageState();
}

class _MyFSImageState extends State<MyFSImage>
{
  // 画像。読み込みが完了するまでは null。
  Widget ?_iconImage;

  @override
  void initState()
  {
    super.initState();
    getImage(widget.gsPath);
  }

  void getImage(String gsPath) async
  {
    // 読み込み済みキャッシュにあればそれを使う
    if(_imageCache.containsKey(gsPath))
    {
      _iconImage = _imageCache[gsPath];
      return;
    }
  
    await _mutex.acquire();
    try {
      // Firebase Storage のURIスキーム(gs://)からURLを取得し、HTTPリクエストで画像を取得
      // NOTE: ブラウザにキャッシュするために、
      // - Firebase Storate にCORSを設定する必要がある。
      // - Firebase Storage のURLはキャッシュされない。Google Cloud Storage の一般公開URLで参照する。

      // Google Cloud Storage の一般公開URLに変換。
      // 最初の一回だけ、バケットURLを取得するために、Firebase Storage を使う。
      // NOTE: 一般公開URLをハードコートすよりマシ。
      // NOTE: 並列して複数の画像が走るので、Mutexで最初の一つだけがバケットURLを取得する。
      if(_bucketURL.isEmpty)
      {
        final ref = FirebaseStorage.instance.ref().child(gsPath);
        final url = await ref.getDownloadURL();
        int i0 = url.indexOf("/b/");
        int i1 = url.indexOf("/o/");
        _bucketURL = url.substring(i0 + 3, i1);
        print("MyFSImage : _bucketURL = $_bucketURL");
      }
      _mutex.release();

      final publicURL = "https://storage.googleapis.com/" + _bucketURL + "/" + gsPath;
      final response = await http.get(Uri.parse(publicURL));

      // HTTPレスポンスを得られたら画像を作成
      setState(() {
        if(response.statusCode == 200)
        {
          final imageBytes = response.bodyBytes;
          _iconImage = Image.memory(imageBytes);
          // キャッシュに登録
          _imageCache[gsPath] = _iconImage!;
        }else{
          // 成功(200)以外ならエラーアイコン
          _iconImage = widget.errorIcon;
          _iconImage ??= const Icon(Icons.error, size:60);
          print("MyFSImage : Error : ${response.statusCode}");
        }
      });
    } catch (e) {
      // 例外が発生したらエラーアイコン
      setState(() {
        _iconImage = widget.errorIcon;
        _iconImage ??= const Icon(Icons.error, size:60);
        print("MyFSImage : Excepthon : $e");
      });
    }
    if(_mutex.isLocked) _mutex.release();
  }

  @override
  Widget build(BuildContext context)
  {
    // 画像が取得できるまでは、適当なアイコンを返す
    Widget? iconImage = _iconImage;
    iconImage ??= widget.loadingIcon;
    iconImage ??= const Icon(Icons.downloading, size:60);
    return iconImage;
  }
}
