# IPADIC (bundled MeCab dictionary)

`sys.dic`, `matrix.bin`, `char.bin`, `unk.dic` and the `*.def` files are the
compiled form of **mecab-ipadic 2.7.0-20070801**, the standard IPA Japanese
morphological dictionary distributed with MeCab.

They are data, not code: MeCab's `mecab-dict-index` compiles the upstream
CSV lexicon into these tables, and the compiled tables are what MeCab loads
at runtime. They are checked in because the app needs the dictionary at
runtime on device and building it during the app build would mean shipping
the ~380 MB CSV lexicon plus a host build of `mecab-dict-index`.

* Upstream: https://taku910.github.io/mecab/
* Dictionary source: https://github.com/taku910/mecab/tree/master/mecab-ipadic
* Licence: see `COPYING` in this directory — a permissive BSD-style licence
  from the Nara Institute of Science and Technology.

The MeCab engine itself is vendored under `plugins/mecab_dart/` and is
tri-licensed GPL / LGPL / BSD; see `plugins/mecab_dart/COPYING.mecab`.
