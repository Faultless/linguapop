import '../../data/models/jp_token.dart';

/// Post-processing pass over raw MeCab output that merges a verb/adjective
/// stem with the auxiliary chain conjugated onto it, producing one token per
/// grammatical phrase instead of one per morpheme.
///
///   食べ / て / い / まし / た   →   食べていました
///     (base 食べる, forms: progressive · polite · past)
///
/// Three kinds of phrase get a head:
///   * 動詞,自立 / 形容詞,自立 — plain verbs and i-adjectives.
///   * 名詞,サ変接続 + する    — suru-verbs (発表する), so 発表しました is one
///     token whose base is 発表する rather than a bare noun plus an unrelated
///     verb.
///   * 名詞,形容動詞語幹 + だ  — na-adjectives (静かだった), which MeCab
///     otherwise leaves as a noun stem plus a copula.
///
/// This keeps JLPT coloring on the dictionary form of the actual word, makes
/// tap-for-dictionary hit the right headword, and lets the popover explain
/// which conjugation the reader is looking at.
///
/// The merged surfaces always concatenate to exactly the original text, so
/// render-time span building is unaffected.
class ConjugationMerger {
  /// Merge conjugation chains in [tokens]. Tokens not part of a chain pass
  /// through unchanged.
  static List<JpToken> merge(List<JpToken> tokens) {
    final out = <JpToken>[];
    var i = 0;
    while (i < tokens.length) {
      final head = tokens[i];
      final after = i + 1 < tokens.length ? tokens[i + 1] : null;
      final kind = _headKind(head, after);
      if (kind == _HeadKind.none) {
        out.add(head);
        i++;
        continue;
      }
      // Compound heads (suru-verb, na-adjective) span two morphemes.
      final headLen = kind == _HeadKind.simple ? 1 : 2;
      final chain = <JpToken>[head, if (headLen == 2) after!];
      var j = i + headLen;
      while (j < tokens.length) {
        final next = j + 1 < tokens.length ? tokens[j + 1] : null;
        if (!_continuesChain(tokens[j], chain, next)) break;
        chain.add(tokens[j]);
        j++;
      }
      out.add(_fuse(chain, kind, headLen));
      i = j;
    }
    return out;
  }

  static bool _posStartsWith(JpToken t, String prefix) =>
      t.pos == prefix || t.pos.startsWith('$prefix,');

  /// What kind of phrase head, if any, starts at this morpheme.
  static _HeadKind _headKind(JpToken t, JpToken? next) {
    if (t.isFiller) return _HeadKind.none;
    if (_posStartsWith(t, '動詞,自立') || _posStartsWith(t, '形容詞,自立')) {
      return _HeadKind.simple;
    }
    if (next == null || next.isFiller) return _HeadKind.none;
    // 発表 + する
    if (_posStartsWith(t, '名詞,サ変接続') &&
        _posStartsWith(next, '動詞,自立') &&
        (next.base == 'する' || next.base == '為る')) {
      return _HeadKind.suru;
    }
    // 静か + だ / です / な
    if (_posStartsWith(t, '名詞,形容動詞語幹') &&
        _posStartsWith(next, '助動詞') &&
        (next.base == 'だ' || next.base == 'です')) {
      return _HeadKind.na;
    }
    return _HeadKind.none;
  }

  /// Connector particles that glue the chain together (te-form and friends,
  /// the ば/と conditionals, and the ながら/たり/つつ/し clause-internal forms).
  static const _connectorSurfaces = {
    'て', 'で', 'ちゃ', 'じゃ', 'ば', 'たり', 'だり',
    'ながら', 'つつ', 'し', 'と',
  };

  /// Auxiliary-like surfaces that a bare て/ば/は/も can attach to and that we
  /// still want inside the same phrase: the obligation and permission
  /// patterns (〜なければならない, 〜てはいけない, 〜てもいい).
  static bool _completesObligation(JpToken t) {
    if (_posStartsWith(t, '動詞,自立')) {
      return t.base == 'いける' || t.base == 'なる' || t.base == '成る';
    }
    if (_posStartsWith(t, '形容詞,自立')) {
      return t.base == 'ない' ||
          t.base == 'いい' ||
          t.base == 'よい' ||
          t.base == '良い';
    }
    if (_posStartsWith(t, '名詞,形容動詞語幹')) {
      return t.base == 'だめ' || t.base == '駄目';
    }
    return false;
  }

  static bool _opensObligation(JpToken prev) =>
      prev.surface == 'ば' ||
      prev.surface == 'は' ||
      prev.surface == 'も' ||
      prev.surface == 'たら';

  static bool _continuesChain(JpToken t, List<JpToken> chain, JpToken? next) {
    if (t.isFiller) return false;
    if (_posStartsWith(t, '助動詞')) return true;
    if (_posStartsWith(t, '動詞,接尾')) return true;
    if (_posStartsWith(t, '動詞,非自立')) return true;
    if (_posStartsWith(t, '形容詞,非自立')) return true;
    if (_posStartsWith(t, '形容詞,接尾')) return true;
    // そう / よう in 〜そうだ / 〜ようだ, tagged as an auxiliary noun stem.
    if (_posStartsWith(t, '名詞,接尾,助動詞語幹')) return true;
    if (_posStartsWith(t, '名詞,非自立,助動詞語幹')) return true;
    if ((_posStartsWith(t, '助詞,接続助詞') ||
            _posStartsWith(t, '助詞,並立助詞')) &&
        _connectorSurfaces.contains(t.surface)) {
      return true;
    }
    // 〜ては / 〜ても / 〜なければ — only swallow the topic/inclusive particle
    // when the word that completes the pattern actually follows.
    if (_posStartsWith(t, '助詞,係助詞') &&
        (t.surface == 'は' || t.surface == 'も') &&
        next != null &&
        _completesObligation(next)) {
      return true;
    }
    if (_completesObligation(t) &&
        chain.isNotEmpty &&
        _opensObligation(chain.last)) {
      return true;
    }
    return false;
  }

  static JpToken _fuse(List<JpToken> chain, _HeadKind kind, int headLen) {
    final head = chain.first;
    final base = switch (kind) {
      _HeadKind.suru => '${head.base}する',
      _HeadKind.na => head.base,
      _HeadKind.simple => head.base,
      _HeadKind.none => head.base,
    };
    final pos = switch (kind) {
      _HeadKind.suru => '動詞,自立',
      _HeadKind.na => '形容詞,自立',
      _ => head.pos,
    };

    if (chain.length == 1) {
      // Single morpheme — only annotate the standalone notable forms.
      final label = _headFormLabel(head);
      if (label == null) return head;
      return head.copyWith(
        conjugation: ConjugationInfo(
          forms: [label],
          parts: [
            ConjPart(surface: head.surface, base: head.base, role: 'stem'),
          ],
        ),
      );
    }

    final surface = chain.map((t) => t.surface).join();
    final reading = chain.every((t) => t.reading != null)
        ? chain.map((t) => t.reading).join()
        : null;

    final parts = <ConjPart>[
      ConjPart(surface: head.surface, base: head.base, role: 'stem'),
    ];
    final forms = <String>[];

    void addForm(String f) {
      if (f.isNotEmpty && (forms.isEmpty || forms.last != f)) forms.add(f);
    }

    final headLabel = _headFormLabel(head);
    if (headLabel != null) addForm(headLabel);
    if (kind == _HeadKind.suru) {
      parts.add(ConjPart(
          surface: chain[1].surface, base: chain[1].base, role: 'suru-verb'));
    } else if (kind == _HeadKind.na) {
      parts.add(ConjPart(
          surface: chain[1].surface, base: chain[1].base, role: 'copula'));
      final copulaRole = _roleFor(chain[1], head, null);
      if (copulaRole != 'copula') addForm(copulaRole);
    }

    for (var k = headLen; k < chain.length; k++) {
      final t = chain[k];
      final next = k + 1 < chain.length ? chain[k + 1] : null;
      final role = _roleFor(t, head, next);
      parts.add(ConjPart(surface: t.surface, base: t.base, role: role));
      // A connector て followed by a helper verb is subsumed by that helper's
      // label (ている = progressive, not "te-form + progressive"). The same
      // goes for the は/も of てはいけない / てもいい.
      final isSubsumedConnector = (_posStartsWith(t, '助詞,接続助詞') &&
              (t.surface == 'て' ||
                  t.surface == 'で' ||
                  t.surface == 'ちゃ' ||
                  t.surface == 'じゃ') &&
              next != null) ||
          _posStartsWith(t, '助詞,係助詞');
      if (!isSubsumedConnector && role.isNotEmpty && role != 'copula') {
        addForm(role);
      }
    }

    return JpToken(
      surface: surface,
      base: base,
      reading: reading,
      pos: pos,
      isFiller: false,
      inflectionType: head.inflectionType,
      inflectionForm: head.inflectionForm,
      conjugation: ConjugationInfo(forms: forms, parts: parts),
    );
  }

  /// Notable forms carried by the head morpheme's own 活用形.
  static String? _headFormLabel(JpToken head) {
    switch (head.inflectionForm) {
      case '命令ｅ':
      case '命令ｉ':
      case '命令ｒｏ':
      case '命令ｙｏ':
      case '命令形':
        return 'imperative';
      default:
        return null;
    }
  }

  /// Grammatical role of one auxiliary in the chain.
  static String _roleFor(JpToken t, JpToken head, JpToken? next) {
    final base = t.base;
    final surface = t.surface;

    if (_posStartsWith(t, '助動詞')) {
      switch (base) {
        case 'た':
        case 'だ':
          // たら / だら — the conditional use of た (仮定形).
          if (surface == 'たら' ||
              surface == 'だら' ||
              t.inflectionForm == '仮定形') {
            return 'conditional (tara)';
          }
          // IPADIC separates the past marker (活用型 特殊・タ, voiced to だ
          // after ん/い stems) from the copula (特殊・ダ / 特殊・デス).
          if (t.inflectionType?.startsWith('特殊・ダ') ?? false) return 'copula';
          return 'past';
        case 'ます':
          return 'polite';
        case 'ない':
        case 'ぬ':
        case 'ん':
          return 'negative';
        case 'う':
        case 'よう':
          return 'volitional';
        case 'まい':
          return 'negative volitional';
        case 'たい':
          return 'desiderative (want to)';
        case 'らしい':
          return 'hearsay (seems)';
        case 'です':
          return 'polite';
        case 'べし':
          return 'should';
        case 'そうだ':
          return 'appearance (looks like)';
        case 'ようだ':
          return 'appearance (ようだ)';
        case 'みたいだ':
          return 'similarity (みたいだ)';
      }
      return '';
    }

    if (_posStartsWith(t, '名詞,接尾,助動詞語幹') ||
        _posStartsWith(t, '名詞,非自立,助動詞語幹')) {
      switch (base) {
        case 'そう':
          return 'appearance (looks like)';
        case 'よう':
          return 'appearance (ようだ)';
        case 'みたい':
          return 'similarity (みたいだ)';
      }
      return '';
    }

    if (_posStartsWith(t, '動詞,接尾')) {
      switch (base) {
        case 'れる':
          return 'passive';
        case 'られる':
          // For 一段 verbs られる is also the potential form.
          final ichidan = head.inflectionType?.startsWith('一段') ?? false;
          return ichidan ? 'passive / potential' : 'passive';
        case 'せる':
        case 'させる':
          return 'causative';
        case 'がる':
          return 'outward sign (~garu)';
      }
      return '';
    }

    if (_posStartsWith(t, '動詞,非自立')) {
      switch (base) {
        case 'いる':
        case 'てる':
          return 'progressive (ている)';
        case 'ある':
          return 'resultative (てある)';
        case 'おく':
        case 'とく':
          return 'preparatory (ておく)';
        case 'しまう':
        case 'ちゃう':
        case 'じゃう':
          return 'completive (てしまう)';
        case 'みる':
          return 'attemptive (てみる)';
        case 'いく':
        case '行く':
          return 'progressing away (ていく)';
        case 'くる':
        case '来る':
          return 'progressing toward (てくる)';
        case 'もらう':
        case 'いただく':
        case '頂く':
          return 'benefactive (receive)';
        case 'くれる':
        case 'くださる':
        case '下さる':
          return 'benefactive (done for me)';
        case 'あげる':
        case 'やる':
        case 'さしあげる':
          return 'benefactive (give)';
        case '始める':
        case 'はじめる':
          return 'inchoative (start to)';
        case '続ける':
        case 'つづける':
          return 'continuative (keep on)';
        case '出す':
        case 'だす':
          return 'sudden start (~dasu)';
        case '過ぎる':
        case 'すぎる':
          return 'excessive (too much)';
        case 'なる':
          return 'become';
        case 'できる':
          return 'potential';
      }
      return '';
    }

    // The verb/adjective that completes an obligation or permission pattern.
    if (_posStartsWith(t, '動詞,自立')) {
      switch (base) {
        case 'いける':
          return 'prohibition (てはいけない)';
        case 'なる':
        case '成る':
          return 'obligation (なければならない)';
      }
      return '';
    }

    if (_posStartsWith(t, '形容詞,自立')) {
      switch (base) {
        case 'ない':
          return 'obligation (なければならない)';
        case 'いい':
        case 'よい':
        case '良い':
          return 'permission (てもいい)';
      }
      return '';
    }

    if (_posStartsWith(t, '形容詞,非自立') || _posStartsWith(t, '形容詞,接尾')) {
      switch (base) {
        case 'ほしい':
        case '欲しい':
          return 'desiderative (てほしい)';
        case 'やすい':
          return 'facilitative (easy to)';
        case 'にくい':
        case 'がたい':
          return 'difficult to';
        case 'ない':
          return 'negative';
        case 'よい':
        case 'いい':
          return 'permission (てもいい)';
      }
      return '';
    }

    if (_posStartsWith(t, '助詞,接続助詞') ||
        _posStartsWith(t, '助詞,並立助詞')) {
      switch (surface) {
        case 'て':
        case 'で':
          return 'te-form';
        case 'ちゃ':
        case 'じゃ':
          return 'contracted te-form';
        case 'ば':
          return 'conditional (ba)';
        case 'と':
          return 'conditional (to)';
        case 'たり':
        case 'だり':
          return 'listing (tari)';
        case 'ながら':
          return 'simultaneous (nagara)';
        case 'つつ':
          return 'simultaneous (tsutsu)';
        case 'し':
          return 'listing (shi)';
      }
      return '';
    }

    return '';
  }
}

enum _HeadKind { none, simple, suru, na }
