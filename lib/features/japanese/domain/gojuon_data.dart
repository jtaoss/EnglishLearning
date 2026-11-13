import 'package:flutter/foundation.dart';

/// Single Kana entry representing a basic standard Seion (清音) or Hatsun (拨音).
@immutable
final class KanaItem {
  const KanaItem({
    required this.id,
    required this.hiragana,
    required this.katakana,
    required this.romaji,
    required this.rowName,
    required this.rowIndex,
    required this.colIndex,
    required this.mnemonicHint,
  });

  final String id;
  final String hiragana;
  final String katakana;
  final String romaji;
  final String rowName;
  final int rowIndex; // 0 to 10
  final int colIndex; // 0 to 4 (a, i, u, e, o)
  final String mnemonicHint;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KanaItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          hiragana == other.hiragana &&
          katakana == other.katakana;

  @override
  int get hashCode => Object.hash(id, hiragana, katakana);

  @override
  String toString() => '$hiragana / $katakana ($romaji)';
}

/// Standard Gojūon (五十音) verified dataset containing exactly the 46 modern basic kana.
abstract final class GojuonData {
  static const List<String> colVowels = ['a', 'i', 'u', 'e', 'o'];
  static const List<String> rowNames = [
    'あ行 (a)',
    'か行 (ka)',
    'さ行 (sa)',
    'た行 (ta)',
    'な行 (na)',
    'は行 (ha)',
    'ま行 (ma)',
    'や行 (ya)',
    'ら行 (ra)',
    'わ行 (wa)',
    '拨音 (n)',
  ];

  static const List<KanaItem> basicKanaList = [
    // 0. あ行 (a, i, u, e, o)
    KanaItem(
      id: 'a',
      hiragana: 'あ',
      katakana: 'ア',
      romaji: 'a',
      rowName: 'あ行',
      rowIndex: 0,
      colIndex: 0,
      mnemonicHint: '平假名源自「安」的草书，片假名源自「阿」的左偏旁「阝」',
    ),
    KanaItem(
      id: 'i',
      hiragana: 'い',
      katakana: 'イ',
      romaji: 'i',
      rowName: 'あ行',
      rowIndex: 0,
      colIndex: 1,
      mnemonicHint: '平假名源自「以」的草书，片假名源自「伊」的单人旁「亻」',
    ),
    KanaItem(
      id: 'u',
      hiragana: 'う',
      katakana: 'ウ',
      romaji: 'u',
      rowName: 'あ行',
      rowIndex: 0,
      colIndex: 2,
      mnemonicHint: '平假名源自「宇」的草书，片假名源自「宇」的前三笔宝盖头',
    ),
    KanaItem(
      id: 'e',
      hiragana: 'え',
      katakana: 'エ',
      romaji: 'e',
      rowName: 'あ行',
      rowIndex: 0,
      colIndex: 3,
      mnemonicHint: '平假名源自「衣」的草书，片假名源自「江」的右半部「工」',
    ),
    KanaItem(
      id: 'o',
      hiragana: 'お',
      katakana: 'オ',
      romaji: 'o',
      rowName: 'あ行',
      rowIndex: 0,
      colIndex: 4,
      mnemonicHint: '平假名源自「於」的草书，片假名源自「於」的左半部',
    ),

    // 1. か行 (ka, ki, ku, ke, ko)
    KanaItem(
      id: 'ka',
      hiragana: 'か',
      katakana: 'カ',
      romaji: 'ka',
      rowName: 'か行',
      rowIndex: 1,
      colIndex: 0,
      mnemonicHint: '平假名源自「加」的草书，片假名源自「加」的左半部「力」',
    ),
    KanaItem(
      id: 'ki',
      hiragana: 'き',
      katakana: 'キ',
      romaji: 'ki',
      rowName: 'か行',
      rowIndex: 1,
      colIndex: 1,
      mnemonicHint: '平假名源自「幾」的草书，片假名源自「幾」的上半部',
    ),
    KanaItem(
      id: 'ku',
      hiragana: 'く',
      katakana: 'ク',
      romaji: 'ku',
      rowName: 'か行',
      rowIndex: 1,
      colIndex: 2,
      mnemonicHint: '平假名源自「久」的草书，片假名源自「久」的前两笔',
    ),
    KanaItem(
      id: 'ke',
      hiragana: 'け',
      katakana: 'ケ',
      romaji: 'ke',
      rowName: 'か行',
      rowIndex: 1,
      colIndex: 3,
      mnemonicHint: '平假名源自「計」的草书，片假名源自「介」的右半部',
    ),
    KanaItem(
      id: 'ko',
      hiragana: 'こ',
      katakana: 'コ',
      romaji: 'ko',
      rowName: 'か行',
      rowIndex: 1,
      colIndex: 4,
      mnemonicHint: '平假名源自「己」的草书，片假名源自「己」的上两笔',
    ),

    // 2. さ行 (sa, shi, su, se, so)
    KanaItem(
      id: 'sa',
      hiragana: 'さ',
      katakana: 'サ',
      romaji: 'sa',
      rowName: 'さ行',
      rowIndex: 2,
      colIndex: 0,
      mnemonicHint: '平假名源自「左」的草书，片假名源自「散」的起笔两画',
    ),
    KanaItem(
      id: 'shi',
      hiragana: 'し',
      katakana: 'シ',
      romaji: 'shi',
      rowName: 'さ行',
      rowIndex: 2,
      colIndex: 1,
      mnemonicHint: '平假名源自「之」的草书，片假名源自「之」的变体三点',
    ),
    KanaItem(
      id: 'su',
      hiragana: 'す',
      katakana: 'ス',
      romaji: 'su',
      rowName: 'さ行',
      rowIndex: 2,
      colIndex: 2,
      mnemonicHint: '平假名源自「寸」的草书，片假名源自「須」的右半部',
    ),
    KanaItem(
      id: 'se',
      hiragana: 'せ',
      katakana: 'セ',
      romaji: 'se',
      rowName: 'さ行',
      rowIndex: 2,
      colIndex: 3,
      mnemonicHint: '平假名源自「世」的草书，片假名源自「世」的简化两笔',
    ),
    KanaItem(
      id: 'so',
      hiragana: 'そ',
      katakana: 'ソ',
      romaji: 'so',
      rowName: 'さ行',
      rowIndex: 2,
      colIndex: 4,
      mnemonicHint: '平假名源自「曾」的草书，片假名源自「曾」的前两点',
    ),

    // 3. た行 (ta, chi, tsu, te, to)
    KanaItem(
      id: 'ta',
      hiragana: 'た',
      katakana: 'タ',
      romaji: 'ta',
      rowName: 'た行',
      rowIndex: 3,
      colIndex: 0,
      mnemonicHint: '平假名源自「太」的草书，片假名源自「多」的上半部',
    ),
    KanaItem(
      id: 'chi',
      hiragana: 'ち',
      katakana: 'チ',
      romaji: 'chi',
      rowName: 'た行',
      rowIndex: 3,
      colIndex: 1,
      mnemonicHint: '平假名源自「知」的草书，片假名源自「千」字',
    ),
    KanaItem(
      id: 'tsu',
      hiragana: 'つ',
      katakana: 'ツ',
      romaji: 'tsu',
      rowName: 'た行',
      rowIndex: 3,
      colIndex: 2,
      mnemonicHint: '平假名源自「川」的草书，片假名源自「川」的三笔变体',
    ),
    KanaItem(
      id: 'te',
      hiragana: 'て',
      katakana: 'テ',
      romaji: 'te',
      rowName: 'た行',
      rowIndex: 3,
      colIndex: 3,
      mnemonicHint: '平假名源自「天」的草书，片假名源自「天」的折笔',
    ),
    KanaItem(
      id: 'to',
      hiragana: 'と',
      katakana: 'ト',
      romaji: 'to',
      rowName: 'た行',
      rowIndex: 3,
      colIndex: 4,
      mnemonicHint: '平假名源自「止」的草书，片假名源自「止」的右半部',
    ),

    // 4. な行 (na, ni, nu, ne, no)
    KanaItem(
      id: 'na',
      hiragana: 'な',
      katakana: 'ナ',
      romaji: 'na',
      rowName: 'な行',
      rowIndex: 4,
      colIndex: 0,
      mnemonicHint: '平假名源自「奈」的草书，片假名源自「奈」的左上部',
    ),
    KanaItem(
      id: 'ni',
      hiragana: 'に',
      katakana: 'ニ',
      romaji: 'ni',
      rowName: 'な行',
      rowIndex: 4,
      colIndex: 1,
      mnemonicHint: '平假名源自「仁」的草书，片假名源自「二」字',
    ),
    KanaItem(
      id: 'nu',
      hiragana: 'ぬ',
      katakana: 'ヌ',
      romaji: 'nu',
      rowName: 'な行',
      rowIndex: 4,
      colIndex: 2,
      mnemonicHint: '平假名源自「奴」的草书，片假名源自「奴」的右半部「又」',
    ),
    KanaItem(
      id: 'ne',
      hiragana: 'ね',
      katakana: 'ネ',
      romaji: 'ne',
      rowName: 'な行',
      rowIndex: 4,
      colIndex: 3,
      mnemonicHint: '平假名源自「禰」的草书，片假名源自「禰」的偏旁「礻」',
    ),
    KanaItem(
      id: 'no',
      hiragana: 'の',
      katakana: 'ノ',
      romaji: 'no',
      rowName: 'な行',
      rowIndex: 4,
      colIndex: 4,
      mnemonicHint: '平假名源自「乃」的草书，片假名源自「乃」的起笔一撇',
    ),

    // 5. は行 (ha, hi, fu, he, ho)
    KanaItem(
      id: 'ha',
      hiragana: 'は',
      katakana: 'ハ',
      romaji: 'ha',
      rowName: 'は行',
      rowIndex: 5,
      colIndex: 0,
      mnemonicHint: '平假名源自「波」的草书，片假名源自「八」字',
    ),
    KanaItem(
      id: 'hi',
      hiragana: 'ひ',
      katakana: 'ヒ',
      romaji: 'hi',
      rowName: 'は行',
      rowIndex: 5,
      colIndex: 1,
      mnemonicHint: '平假名源自「比」的草书，片假名源自「比」的右半部',
    ),
    KanaItem(
      id: 'fu',
      hiragana: 'ふ',
      katakana: 'フ',
      romaji: 'fu',
      rowName: 'は行',
      rowIndex: 5,
      colIndex: 2,
      mnemonicHint: '平假名源自「不」的草书，片假名源自「不」的初两笔',
    ),
    KanaItem(
      id: 'he',
      hiragana: 'へ',
      katakana: 'ヘ',
      romaji: 'he',
      rowName: 'は行',
      rowIndex: 5,
      colIndex: 3,
      mnemonicHint: '平假名与片假名均源自「部」的草写折画',
    ),
    KanaItem(
      id: 'ho',
      hiragana: 'ほ',
      katakana: 'ホ',
      romaji: 'ho',
      rowName: 'は行',
      rowIndex: 5,
      colIndex: 4,
      mnemonicHint: '平假名源自「保」的草书，片假名源自「保」的右下四笔',
    ),

    // 6. ま行 (ma, mi, mu, me, mo)
    KanaItem(
      id: 'ma',
      hiragana: 'ま',
      katakana: 'マ',
      romaji: 'ma',
      rowName: 'ま行',
      rowIndex: 6,
      colIndex: 0,
      mnemonicHint: '平假名源自「末」的草书，片假名源自「末」的缩写',
    ),
    KanaItem(
      id: 'mi',
      hiragana: 'み',
      katakana: 'ミ',
      romaji: 'mi',
      rowName: 'ま行',
      rowIndex: 6,
      colIndex: 1,
      mnemonicHint: '平假名源自「美」的草书，片假名源自「三」字',
    ),
    KanaItem(
      id: 'mu',
      hiragana: 'む',
      katakana: 'ム',
      romaji: 'mu',
      rowName: 'ま行',
      rowIndex: 6,
      colIndex: 2,
      mnemonicHint: '平假名源自「武」的草书，片假名源自「牟」的上半部',
    ),
    KanaItem(
      id: 'me',
      hiragana: 'め',
      katakana: 'メ',
      romaji: 'me',
      rowName: 'ま行',
      rowIndex: 6,
      colIndex: 3,
      mnemonicHint: '平假名源自「女」的草书，片假名源自「女」的末两笔',
    ),
    KanaItem(
      id: 'mo',
      hiragana: 'も',
      katakana: 'モ',
      romaji: 'mo',
      rowName: 'ま行',
      rowIndex: 6,
      colIndex: 4,
      mnemonicHint: '平假名源自「毛」的草书，片假名源自「毛」的三笔简化',
    ),

    // 7. や行 (ya, yu, yo) - 3 basic
    KanaItem(
      id: 'ya',
      hiragana: 'や',
      katakana: 'ヤ',
      romaji: 'ya',
      rowName: 'や行',
      rowIndex: 7,
      colIndex: 0,
      mnemonicHint: '平假名源自「也」的草书，片假名源自「也」的前两笔',
    ),
    KanaItem(
      id: 'yu',
      hiragana: 'ゆ',
      katakana: 'ユ',
      romaji: 'yu',
      rowName: 'や行',
      rowIndex: 7,
      colIndex: 2,
      mnemonicHint: '平假名源自「由」的草书，片假名源自「由」的后两笔',
    ),
    KanaItem(
      id: 'yo',
      hiragana: 'よ',
      katakana: 'ヨ',
      romaji: 'yo',
      rowName: 'や行',
      rowIndex: 7,
      colIndex: 4,
      mnemonicHint: '平假名源自「与」的草书，片假名源自「与」的上半部',
    ),

    // 8. ら行 (ra, ri, ru, re, ro)
    KanaItem(
      id: 'ra',
      hiragana: 'ら',
      katakana: 'ラ',
      romaji: 'ra',
      rowName: 'ら行',
      rowIndex: 8,
      colIndex: 0,
      mnemonicHint: '平假名源自「良」的草书，片假名源自「良」的前两笔',
    ),
    KanaItem(
      id: 'ri',
      hiragana: 'り',
      katakana: 'リ',
      romaji: 'ri',
      rowName: 'ら行',
      rowIndex: 8,
      colIndex: 1,
      mnemonicHint: '平假名源自「利」的草书，片假名源自「利」的右立刀旁「刂」',
    ),
    KanaItem(
      id: 'ru',
      hiragana: 'る',
      katakana: 'ル',
      romaji: 'ru',
      rowName: 'ら行',
      rowIndex: 8,
      colIndex: 2,
      mnemonicHint: '平假名源自「留」的草书，片假名源自「流」的末尾两笔',
    ),
    KanaItem(
      id: 're',
      hiragana: 'れ',
      katakana: 'レ',
      romaji: 're',
      rowName: 'ら行',
      rowIndex: 8,
      colIndex: 3,
      mnemonicHint: '平假名源自「礼」的草书，片假名源自「礼」的右半部',
    ),
    KanaItem(
      id: 'ro',
      hiragana: 'ろ',
      katakana: 'ロ',
      romaji: 'ro',
      rowName: 'ら行',
      rowIndex: 8,
      colIndex: 4,
      mnemonicHint: '平假名源自「吕」的草书，片假名源自「吕」的上口「口」',
    ),

    // 9. わ行 (wa, wo) - 2 basic
    KanaItem(
      id: 'wa',
      hiragana: 'わ',
      katakana: 'ワ',
      romaji: 'wa',
      rowName: 'わ行',
      rowIndex: 9,
      colIndex: 0,
      mnemonicHint: '平假名源自「和」的草书，片假名源自「和」的右口「口」',
    ),
    KanaItem(
      id: 'wo',
      hiragana: 'を',
      katakana: 'ヲ',
      romaji: 'wo',
      rowName: 'わ行',
      rowIndex: 9,
      colIndex: 4,
      mnemonicHint: '平假名源自「遠」的草书，片假名源自「乎」的初两笔（现代多读作 o，常用作宾格助词）',
    ),

    // 10. 拨音 (n) - 1 basic
    KanaItem(
      id: 'n',
      hiragana: 'ん',
      katakana: 'ン',
      romaji: 'n',
      rowName: '拨音',
      rowIndex: 10,
      colIndex: 0,
      mnemonicHint: '平假名源自「无」的草书，片假名源自「尔」的草体（鼻音/拨音，不单独作音节首）',
    ),
  ];

  /// Total count of modern basic seion + hatsun, exactly 46.
  static int get totalCount => basicKanaList.length;

  /// Returns an 11 x 5 grid of `KanaItem?` for the standard 50-sound chart layout.
  static List<List<KanaItem?>> get grid {
    final result = List.generate(11, (_) => List<KanaItem?>.filled(5, null));
    for (final item in basicKanaList) {
      result[item.rowIndex][item.colIndex] = item;
    }
    return result;
  }

  /// Look up a kana by its ID, Hiragana, or Katakana.
  static KanaItem? find(String query) {
    for (final item in basicKanaList) {
      if (item.id == query ||
          item.hiragana == query ||
          item.katakana == query ||
          item.romaji == query) {
        return item;
      }
    }
    return null;
  }
}
