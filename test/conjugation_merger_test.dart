import 'package:flutter_test/flutter_test.dart';

import 'package:linguapop/data/models/jp_token.dart';
import 'package:linguapop/data/models/reader_prefs.dart' show JpPosCategory;
import 'package:linguapop/services/tokenizer/conjugation_merger.dart';

/// Helper replicating what MecabTokenizer emits for one IPADIC morpheme.
JpToken tk(
  String surface,
  String pos, {
  String? base,
  String? type,
  String? form,
  bool filler = false,
}) =>
    JpToken(
      surface: surface,
      base: base ?? surface,
      pos: pos,
      isFiller: filler,
      inflectionType: type,
      inflectionForm: form,
      reading: surface, // reading value irrelevant for merge logic
    );

void main() {
  group('ConjugationMerger', () {
    test('食べていました → one token, progressive polite past', () {
      // IPADIC: 食べ/て/い/まし/た
      final merged = ConjugationMerger.merge([
        tk('食べ', '動詞,自立', base: '食べる', type: '一段', form: '連用形'),
        tk('て', '助詞,接続助詞'),
        tk('い', '動詞,非自立', base: 'いる', type: '一段', form: '連用形'),
        tk('まし', '助動詞', base: 'ます', type: '特殊・マス', form: '連用形'),
        tk('た', '助動詞', base: 'た', type: '特殊・タ', form: '基本形'),
        tk('。', '記号,句点', filler: true),
      ]);
      expect(merged.length, 2);
      final v = merged.first;
      expect(v.surface, '食べていました');
      expect(v.base, '食べる');
      expect(v.conjugation, isNotNull);
      expect(v.conjugation!.forms,
          ['progressive (ている)', 'polite', 'past']);
      expect(v.conjugation!.parts.length, 5);
    });

    test('飲まなければ → negative + conditional', () {
      final merged = ConjugationMerger.merge([
        tk('飲ま', '動詞,自立', base: '飲む', type: '五段・マ行', form: '未然形'),
        tk('なけれ', '助動詞', base: 'ない', type: '特殊・ナイ', form: '仮定形'),
        tk('ば', '助詞,接続助詞'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.surface, '飲まなければ');
      expect(merged.first.base, '飲む');
      expect(merged.first.conjugation!.forms, ['negative', 'conditional (ba)']);
    });

    test('高くなかったら → adjective negative tara-conditional', () {
      final merged = ConjugationMerger.merge([
        tk('高く', '形容詞,自立',
            base: '高い', type: '形容詞・アウオ段', form: '連用テ接続'),
        tk('なかっ', '助動詞', base: 'ない', type: '特殊・ナイ', form: '連用タ接続'),
        tk('たら', '助動詞', base: 'た', type: '特殊・タ', form: '仮定形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.surface, '高くなかったら');
      expect(merged.first.base, '高い');
      expect(merged.first.conjugation!.forms,
          ['negative', 'conditional (tara)']);
    });

    test('読んでしまった → completive past', () {
      final merged = ConjugationMerger.merge([
        tk('読ん', '動詞,自立', base: '読む', type: '五段・マ行', form: '連用タ接続'),
        tk('で', '助詞,接続助詞'),
        tk('しまっ', '動詞,非自立',
            base: 'しまう', type: '五段・ワ行促音便', form: '連用タ接続'),
        tk('た', '助動詞', base: 'た', type: '特殊・タ', form: '基本形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.conjugation!.forms,
          ['completive (てしまう)', 'past']);
    });

    test('行きましょう → polite volitional', () {
      final merged = ConjugationMerger.merge([
        tk('行き', '動詞,自立', base: '行く', type: '五段・カ行促音便', form: '連用形'),
        tk('ましょ', '助動詞', base: 'ます', type: '特殊・マス', form: '未然ウ接続'),
        tk('う', '助動詞', base: 'う', type: '不変化型', form: '基本形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.conjugation!.forms, ['polite', 'volitional']);
    });

    test('食べろ → standalone imperative keeps annotation', () {
      final merged = ConjugationMerger.merge([
        tk('食べろ', '動詞,自立', base: '食べる', type: '一段', form: '命令ｒｏ'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.conjugation!.forms, ['imperative']);
    });

    test('食べられない → passive/potential negative', () {
      final merged = ConjugationMerger.merge([
        tk('食べ', '動詞,自立', base: '食べる', type: '一段', form: '未然形'),
        tk('られ', '動詞,接尾', base: 'られる', type: '一段', form: '未然形'),
        tk('ない', '助動詞', base: 'ない', type: '特殊・ナイ', form: '基本形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.conjugation!.forms,
          ['passive / potential', 'negative']);
    });

    test('learner request 見てください → benefactive', () {
      final merged = ConjugationMerger.merge([
        tk('見', '動詞,自立', base: '見る', type: '一段', form: '連用形'),
        tk('て', '助詞,接続助詞'),
        tk('ください', '動詞,非自立',
            base: 'くださる', type: '五段・ラ行特殊', form: '命令ｉ'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.surface, '見てください');
      expect(merged.first.conjugation!.forms, ['benefactive (done for me)']);
    });

    test('学生だった — copula after noun is NOT merged', () {
      final merged = ConjugationMerger.merge([
        tk('学生', '名詞,一般'),
        tk('だっ', '助動詞', base: 'だ', type: '特殊・ダ', form: '連用タ接続'),
        tk('た', '助動詞', base: 'た', type: '特殊・タ', form: '基本形'),
      ]);
      expect(merged.length, 3);
      expect(merged.every((t) => t.conjugation == null), isTrue);
    });

    test('plain dictionary form stays untouched', () {
      final merged = ConjugationMerger.merge([
        tk('猫', '名詞,一般'),
        tk('が', '助詞,格助詞'),
        tk('走る', '動詞,自立', base: '走る', type: '五段・ラ行', form: '基本形'),
      ]);
      expect(merged.length, 3);
      expect(merged[2].conjugation, isNull);
    });

    test('発表しました → suru-verb merged with its noun', () {
      final merged = ConjugationMerger.merge([
        tk('発表', '名詞,サ変接続'),
        tk('し', '動詞,自立', base: 'する', type: 'サ変・スル', form: '連用形'),
        tk('まし', '助動詞', base: 'ます', type: '特殊・マス', form: '連用形'),
        tk('た', '助動詞', base: 'た', type: '特殊・タ', form: '基本形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.surface, '発表しました');
      expect(merged.first.base, '発表する');
      expect(merged.first.posCategory, JpPosCategory.verb);
      expect(merged.first.conjugation!.forms, ['polite', 'past']);
    });

    test('静かでした → na-adjective merged with its copula', () {
      final merged = ConjugationMerger.merge([
        tk('静か', '名詞,形容動詞語幹'),
        tk('でし', '助動詞', base: 'です', type: '特殊・デス', form: '連用形'),
        tk('た', '助動詞', base: 'た', type: '特殊・タ', form: '基本形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.surface, '静かでした');
      expect(merged.first.base, '静か');
      expect(merged.first.posCategory, JpPosCategory.adjective);
      expect(merged.first.conjugation!.forms, ['polite', 'past']);
    });

    test('静かだった → copula is a part, not a listed form', () {
      final merged = ConjugationMerger.merge([
        tk('静か', '名詞,形容動詞語幹'),
        tk('だっ', '助動詞', base: 'だ', type: '特殊・ダ', form: '連用タ接続'),
        tk('た', '助動詞', base: 'た', type: '特殊・タ', form: '基本形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.conjugation!.forms, ['past']);
    });

    test('行かなければならない → obligation swallows the naru clause', () {
      final merged = ConjugationMerger.merge([
        tk('行か', '動詞,自立', base: '行く', type: '五段・カ行促音便', form: '未然形'),
        tk('なけれ', '助動詞', base: 'ない', type: '特殊・ナイ', form: '仮定形'),
        tk('ば', '助詞,接続助詞'),
        tk('なら', '動詞,自立', base: 'なる', type: '五段・ラ行', form: '未然形'),
        tk('ない', '助動詞', base: 'ない', type: '特殊・ナイ', form: '基本形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.surface, '行かなければならない');
      expect(merged.first.base, '行く');
      expect(merged.first.conjugation!.forms, [
        'negative',
        'conditional (ba)',
        'obligation (なければならない)',
        'negative',
      ]);
    });

    test('食べてはいけません → prohibition', () {
      final merged = ConjugationMerger.merge([
        tk('食べ', '動詞,自立', base: '食べる', type: '一段', form: '連用形'),
        tk('て', '助詞,接続助詞'),
        tk('は', '助詞,係助詞'),
        tk('いけ', '動詞,自立', base: 'いける', type: '一段', form: '未然形'),
        tk('ませ', '助動詞', base: 'ます', type: '特殊・マス', form: '未然形'),
        tk('ん', '助動詞', base: 'ん', type: '不変化型', form: '基本形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.surface, '食べてはいけません');
      expect(merged.first.conjugation!.forms,
          ['prohibition (てはいけない)', 'polite', 'negative']);
    });

    test('休んでもいい → permission', () {
      final merged = ConjugationMerger.merge([
        tk('休ん', '動詞,自立', base: '休む', type: '五段・マ行', form: '連用タ接続'),
        tk('で', '助詞,接続助詞'),
        tk('も', '助詞,係助詞'),
        tk('いい', '形容詞,自立', base: 'いい', type: '形容詞・イイ', form: '基本形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.surface, '休んでもいい');
      expect(merged.first.conjugation!.forms, ['permission (てもいい)']);
    });

    test('bare は after a verb does not get swallowed', () {
      final merged = ConjugationMerger.merge([
        tk('走る', '動詞,自立', base: '走る', type: '五段・ラ行', form: '基本形'),
        tk('は', '助詞,係助詞'),
        tk('猫', '名詞,一般'),
      ]);
      expect(merged.length, 3);
    });

    test('食べながら → simultaneous', () {
      final merged = ConjugationMerger.merge([
        tk('食べ', '動詞,自立', base: '食べる', type: '一段', form: '連用形'),
        tk('ながら', '助詞,接続助詞'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.conjugation!.forms, ['simultaneous (nagara)']);
    });

    test('読んだ → voiced past marker is still past, not a copula', () {
      final merged = ConjugationMerger.merge([
        tk('読ん', '動詞,自立', base: '読む', type: '五段・マ行', form: '連用タ接続'),
        tk('だ', '助動詞', base: 'だ', type: '特殊・タ', form: '基本形'),
      ]);
      expect(merged.length, 1);
      expect(merged.first.conjugation!.forms, ['past']);
    });

    test('surfaces always concatenate back to the original text', () {
      final tokens = [
        tk('彼', '名詞,代名詞'),
        tk('は', '助詞,係助詞'),
        tk('食べ', '動詞,自立', base: '食べる', type: '一段', form: '連用形'),
        tk('て', '助詞,接続助詞'),
        tk('い', '動詞,非自立', base: 'いる', type: '一段', form: '連用形'),
        tk('ない', '助動詞', base: 'ない', form: '基本形'),
        tk('。', '記号,句点', filler: true),
      ];
      final original = tokens.map((t) => t.surface).join();
      final merged = ConjugationMerger.merge(tokens);
      expect(merged.map((t) => t.surface).join(), original);
    });
  });
}
