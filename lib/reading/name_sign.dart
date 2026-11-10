import 'astro.dart';

/// The name sign (nāma rāśi): the nakshatra pada, and so the rashi, that
/// the first syllable of a name belongs to, from the traditional table of
/// 108 syllables (4 per nakshatra).
class NameSign {
  const NameSign({required this.syllable, required this.nakshatra, required this.pada});

  /// The syllable that matched, as written in the table (Latin).
  final String syllable;

  /// 1..27 (Ashwini = 1).
  final int nakshatra;

  /// 1..4.
  final int pada;

  int get rashiIndex => ((nakshatra - 1) * 4 + pada - 1) ~/ 9;
  String get rashi => Astro.rashiKeys[rashiIndex];

  /// Lord of the name sign.
  String get ruler => const [
        'mars', 'venus', 'mercury', 'moon', 'sun', 'mercury',
        'venus', 'mars', 'jupiter', 'saturn', 'saturn', 'jupiter',
      ][rashiIndex];

  /// Syllables per nakshatra pada, in order from Ashwini. Upper-case
  /// T, Th, D, N mark the retroflex consonants (ट ठ ड ण); lower-case are
  /// dental (त थ द न). Latin input is matched as dental, the more common
  /// reading in names. "sha" is ष; श is read with स.
  static const table = <List<List<String>>>[
    [['chu'], ['che'], ['cho'], ['la']], // Ashwini
    [['li'], ['lu'], ['le'], ['lo']], // Bharani
    [['a'], ['i'], ['u'], ['e']], // Krittika
    [['o'], ['va', 'ba'], ['vi', 'bi'], ['vu', 'bu']], // Rohini
    [['ve', 'be'], ['vo', 'bo'], ['ka'], ['ki']], // Mrigashira
    [['ku'], ['gha'], ['nga'], ['chha']], // Ardra
    [['ke'], ['ko'], ['ha'], ['hi']], // Punarvasu
    [['hu'], ['he'], ['ho'], ['Da']], // Pushya
    [['Di'], ['Du'], ['De'], ['Do']], // Ashlesha
    [['ma'], ['mi'], ['mu'], ['me']], // Magha
    [['mo'], ['Ta'], ['Ti'], ['Tu']], // Purva Phalguni
    [['Te'], ['To'], ['pa'], ['pi']], // Uttara Phalguni
    [['pu'], ['sha'], ['Na'], ['Tha']], // Hasta
    [['pe'], ['po'], ['ra'], ['ri']], // Chitra
    [['ru'], ['re'], ['ro'], ['ta']], // Swati
    [['ti'], ['tu'], ['te'], ['to']], // Vishakha
    [['na'], ['ni'], ['nu'], ['ne']], // Anuradha
    [['no'], ['ya'], ['yi'], ['yu']], // Jyeshtha
    [['ye'], ['yo'], ['bha'], ['bhi']], // Mula
    [['bhu'], ['dha'], ['pha', 'fa'], ['Dha']], // Purva Ashadha
    [['bhe'], ['bho'], ['ja', 'za'], ['ji', 'zi']], // Uttara Ashadha
    [['ju', 'khi'], ['je', 'khu'], ['jo', 'khe'], ['kho', 'kha']], // Shravana
    [['ga'], ['gi'], ['gu'], ['ge']], // Dhanishta
    [['go'], ['sa'], ['si'], ['su']], // Shatabhisha
    [['se'], ['so'], ['da'], ['di']], // Purva Bhadrapada
    [['du'], ['tha'], ['jha'], ['tra', 'jna']], // Uttara Bhadrapada
    [['de'], ['do'], ['cha'], ['chi']], // Revati
  ];

  static Map<String, (int, int)>? _index;

  static Map<String, (int, int)> get _lookup {
    final cached = _index;
    if (cached != null) return cached;
    final m = <String, (int, int)>{};
    for (var n = 0; n < table.length; n++) {
      for (var p = 0; p < 4; p++) {
        for (final s in table[n][p]) {
          m.putIfAbsent(s, () => (n + 1, p + 1));
        }
      }
    }
    return _index = m;
  }

  /// Name sign of [name], or null when no syllable matches.
  static NameSign? of(String name) {
    final s = _firstSyllable(name.trim());
    if (s == null) return null;
    final hit = _lookup[s];
    if (hit == null) return null;
    return NameSign(syllable: s.toLowerCase(), nakshatra: hit.$1, pada: hit.$2);
  }

  static const _devConsonants = {
    'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'ng', 'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh',
    'ञ': 'jn', 'ट': 'T', 'ठ': 'Th', 'ड': 'D', 'ढ': 'Dh', 'ण': 'N', 'त': 't', 'थ': 'th', 'द': 'd',
    'ध': 'dh', 'न': 'n', 'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm', 'य': 'y', 'र': 'r',
    'ल': 'l', 'व': 'v', 'श': 's', 'ष': 'sh', 'स': 's', 'ह': 'h',
  };
  static const _devVowels = {
    'अ': 'a', 'आ': 'a', 'इ': 'i', 'ई': 'i', 'उ': 'u', 'ऊ': 'u', 'ए': 'e', 'ऐ': 'e', 'ओ': 'o', 'औ': 'o', 'ऋ': 'ri',
  };
  static const _devMatras = {
    'ा': 'a', 'ि': 'i', 'ी': 'i', 'ु': 'u', 'ू': 'u', 'े': 'e', 'ै': 'e', 'ो': 'o', 'ौ': 'o', 'ृ': 'ri',
  };

  /// First syllable as a table key: consonant (with retroflex marked)
  /// plus a simple vowel.
  static String? _firstSyllable(String name) {
    if (name.isEmpty) return null;
    final first = name[0];
    if (_devVowels.containsKey(first)) return _devVowels[first];
    final c = _devConsonants[first];
    if (c != null) {
      if (name.length > 1) {
        final next = name[1];
        if (next == '्' && name.length > 2) {
          // Conjunct: त्र is listed itself; otherwise use the first
          // consonant with the vowel that follows the cluster.
          if (first == 'त' && name[2] == 'र') return 'tra';
          if (first == 'ज' && name[2] == 'ञ') return 'jna';
          var i = 2;
          while (i < name.length && _devConsonants.containsKey(name[i])) {
            i++;
            if (i < name.length && name[i] == '्') i++;
          }
          final v = i < name.length ? _devMatras[name[i]] ?? 'a' : 'a';
          return _key(c, v);
        }
        return _key(c, _devMatras[next] ?? 'a');
      }
      return _key(c, 'a');
    }

    // Latin script.
    final s = name.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    if (s.isEmpty) return null;
    if (s.startsWith('tr')) return 'tra';
    if (s.startsWith('gy') || s.startsWith('jn')) return 'jna';
    const onsets = [
      'chh', 'ch', 'kh', 'gh', 'ng', 'jh', 'th', 'dh', 'ph', 'bh', 'sh',
      'k', 'g', 'c', 'j', 't', 'd', 'n', 'p', 'f', 'b', 'm', 'y', 'r', 'l', 'v', 'w', 's', 'h', 'z', 'q', 'x',
    ];
    var onset = '';
    for (final o in onsets) {
      if (s.startsWith(o)) {
        onset = o;
        break;
      }
    }
    var rest = s.substring(onset.length);
    // Skip a cluster (Pr-, Kr-, Shr-, Sv-, ...) up to the vowel.
    while (rest.isNotEmpty && !'aeiouy'.contains(rest[0])) {
      rest = rest.substring(1);
    }
    final vowel = _latinVowel(rest);
    onset = switch (onset) {
      'c' => 'k',
      'w' => 'v',
      'q' => 'k',
      'x' => 'k',
      _ => onset,
    };
    // Latin "sh" is almost always श, which the table groups with स
    // (Shatabhisha); ष (Hasta's "sha") only comes from Devanagari.
    if (onset == 'sh') onset = 's';
    if (onset == 'gh' && vowel == 'a') return 'gha';
    if (onset == 'ch' && (vowel == 'a' || vowel == 'i')) return 'ch$vowel';
    return _key(onset, vowel);
  }

  static String _latinVowel(String rest) {
    if (rest.isEmpty) return 'a';
    if (rest.startsWith('ee') || rest.startsWith('i') || rest.startsWith('y')) return 'i';
    if (rest.startsWith('oo') || rest.startsWith('u')) return 'u';
    if (rest.startsWith('ai') || rest.startsWith('ay') || rest.startsWith('e')) return 'e';
    if (rest.startsWith('au') || rest.startsWith('aw') || rest.startsWith('o')) return 'o';
    return 'a';
  }

  static String _key(String consonant, String vowel) {
    if (vowel == 'ri') return consonant.isEmpty ? 'ri' : '${consonant}i';
    final k = '$consonant$vowel';
    // Consonants the table lists only with some vowels: fall back to the
    // nearest listed sound (ब → व, फ → फ़, ...).
    if (_lookup.containsKey(k)) return k;
    final alt = switch (consonant) {
      'b' => 'v',
      'kh' => 'k',
      'gh' => 'g',
      'jh' => 'j',
      'Th' => 'T',
      'th' => 't',
      'Dh' => 'D',
      'dh' => 'd',
      'ph' => 'p',
      'f' => 'p',
      'z' => 'j',
      'sh' => 's',
      'bh' => 'b',
      'chh' => 'ch',
      'ch' => 'ch',
      'N' => 'n',
      'T' => 't',
      'D' => 'd',
      _ => consonant,
    };
    final k2 = '$alt$vowel';
    if (_lookup.containsKey(k2)) return k2;
    if (alt == 'v' || alt == 'b') return 'v$vowel';
    return k2;
  }
}
