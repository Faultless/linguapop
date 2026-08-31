import 'package:hive_ce_flutter/hive_flutter.dart';

/// Box names. Logical equivalents of the JS-era localStorage / IDB keys.
class Boxes {
  static const prefs = 'prefs';            // single key 'reader_prefs'
  static const novelsMeta = 'novels_meta'; // single key 'list' = List<json>
  static const novelBody = 'novel_body';   // key = novel id
  static const jpdict = 'jpdict';          // key = query
  static const vocab = 'vocab';            // single key 'list' = List<json>
  static const covers = 'covers';          // key = novel id, value = base64 image bytes
  static const newsImages = 'news_images'; // key = article key, value = image bytes
}

class Storage {
  static Future<void> init() async {
    await Hive.initFlutter('linguapop');
    await Future.wait([
      Hive.openBox<dynamic>(Boxes.prefs),
      Hive.openBox<dynamic>(Boxes.novelsMeta),
      Hive.openBox<dynamic>(Boxes.novelBody),
      Hive.openBox<dynamic>(Boxes.jpdict),
      Hive.openBox<dynamic>(Boxes.vocab),
      Hive.openBox<dynamic>(Boxes.covers),
      Hive.openBox<dynamic>(Boxes.newsImages),
    ]);
  }

  static Box<dynamic> prefs() => Hive.box<dynamic>(Boxes.prefs);
  static Box<dynamic> novelsMeta() => Hive.box<dynamic>(Boxes.novelsMeta);
  static Box<dynamic> novelBody() => Hive.box<dynamic>(Boxes.novelBody);
  static Box<dynamic> jpdict() => Hive.box<dynamic>(Boxes.jpdict);
  static Box<dynamic> vocab() => Hive.box<dynamic>(Boxes.vocab);
  static Box<dynamic> covers() => Hive.box<dynamic>(Boxes.covers);
  static Box<dynamic> newsImages() => Hive.box<dynamic>(Boxes.newsImages);
}
