import '../kb/knowledge_base.dart';
import 'chart.dart';
import 'name_sign.dart';
import 'palm_features.dart';

/// One planet as both the palm and the birth chart show it.
class PlanetVerdict {
  PlanetVerdict({
    required this.planet,
    required this.palm,
    required this.chart,
    required this.palmScore,
    required this.chartScore,
    required this.palmReasons,
    required this.chartReasons,
  });

  final String planet;
  final Strength palm;
  final Strength chart;
  final double palmScore;
  final double chartScore;
  final List<LText> palmReasons;
  final List<LText> chartReasons;

  /// Both readings together; the chart counts a little more because it
  /// is computed, while the palm is estimated from a photo.
  double get combined => palmScore * 0.8 + chartScore;
}

/// The palm reading and the birth chart read together: where they agree,
/// where they differ, the rising sign against the hand type, the name
/// sign against the Moon sign, and the planetary period running now.
class UnifiedReading {
  UnifiedReading._(this.verdicts, this.summary, this.planetInsights);

  /// All nine planets, strongest combined first.
  final List<PlanetVerdict> verdicts;

  /// The headline results (rising sign, strongest and weakest planet,
  /// current period, name sign).
  final List<KbRule> summary;

  /// One card per planet where palm or chart says something clear.
  final List<KbRule> planetInsights;

  static UnifiedReading build({
    required PalmFeatures palm,
    required BirthChart chart,
    required KnowledgeBase kb,
    NameSign? nameSign,
    DateTime? now,
  }) {
    final verdicts = [
      for (final p in Ephemeris.planets) _verdict(p, palm, chart, kb),
    ]..sort((a, b) => b.combined.compareTo(a.combined));
    LText pName(String p) => kb.placeName(p);
    LText sName(String r) => kb.nameOf(r);
    LText? theme(String p, String field) => kb.planetThemes[p]?.text(field);

    final summary = <KbRule>[];

    // Rising sign and hand type.
    final lagna = chart.lagna;
    if (lagna != null) {
      final rashi = kb.rashis[lagna];
      final signElement = rashi?.str('element') ?? 'fire';
      final dosha = const {'fire': 'fire', 'air': 'air', 'water': 'water', 'earth': 'water'}[signElement]!;
      final agree = dosha == palm.element;
      final el = kb.elements[palm.element]?.name ?? LText(palm.element);
      final traits = rashi?.text('traits');
      summary.add(_rule(
        'unified.lagna',
        area: 'personality',
        tone: agree ? 'positive' : 'neutral',
        weight: 3,
        title: _t('Rising sign ${sName(lagna).en}', 'लग्न ${sName(lagna).hi}'),
        text: _t(
          '${traits?.en ?? ''} ${agree ? 'Your ${el.en} hand agrees with this rising sign, so the temperament your chart describes shows plainly in how you act.' : 'Your hand is ${el.en} while this rising sign leans ${_elementEn[signElement]}: you blend both natures, and can call on either when life needs it.'}'
              .trim(),
          '${traits?.hi ?? ''} ${agree ? 'आपका ${el.hi} हाथ इस लग्न से मेल खाता है, इसलिए कुंडली में बताया स्वभाव आपके व्यवहार में साफ़ दिखता है।' : 'आपका हाथ ${el.hi} है जबकि यह लग्न ${_elementHi[signElement]} की ओर झुका है: आपमें दोनों का मेल है, और ज़रूरत के अनुसार आप दोनों को काम में ला सकते हैं।'}'
              .trim(),
        ),
      ));
    }

    // Strongest and weakest planet across both.
    final best = verdicts.first;
    final worst = verdicts.last;
    final bestTheme = theme(best.planet, 'strong');
    if (bestTheme != null && best.combined > 0.5) {
      summary.add(_rule(
        'unified.best',
        area: 'personality',
        tone: 'positive',
        weight: 3,
        planet: best.planet,
        title: _t('Your strongest planet: ${pName(best.planet).en}', 'आपका सबसे प्रबल ग्रह: ${pName(best.planet).hi}'),
        text: _withReasons(bestTheme, best),
      ));
    }
    final worstTheme = theme(worst.planet, 'weak');
    if (worstTheme != null && worst.combined < -0.5 && worst.planet != best.planet) {
      summary.add(_rule(
        'unified.nurture',
        area: 'health',
        tone: 'caution',
        weight: 2,
        planet: worst.planet,
        title: _t('Planet to nurture: ${pName(worst.planet).en}', 'ध्यान देने योग्य ग्रह: ${pName(worst.planet).hi}'),
        text: _withReasons(
          _t('${worstTheme.en} The Remedies tab has more for ${pName(worst.planet).en}.',
              '${worstTheme.hi} ${pName(worst.planet).hi} के लिए और उपाय \'उपाय\' टैब में देखें।'),
          worst,
        ),
      ));
    }

    // Planetary period running now.
    final at = now ?? DateTime.now();
    final d = chart.dashaAt(at);
    if (d != null) {
      final v = verdicts.firstWhere((e) => e.planet == d.main.lord);
      final md = pName(d.main.lord), ad = pName(d.sub.lord);
      final dt = theme(d.main.lord, 'dasha');
      final level = v.combined >= 1 ? 'strong' : (v.combined <= -1 ? 'weak' : 'mixed');
      summary.add(_rule(
        'unified.dasha',
        area: 'life_events',
        tone: level == 'strong' ? 'positive' : (level == 'weak' ? 'caution' : 'neutral'),
        weight: 3,
        planet: d.main.lord,
        title: _t('Now: ${md.en} period (${d.main.start.year}–${d.main.end.year})',
            'अभी: ${md.hi} की महादशा (${d.main.start.year}–${d.main.end.year})'),
        text: _t(
          'Your chart is in the main period of ${md.en}, with the sub-period of ${ad.en} until '
              '${_monthEn[d.sub.end.month - 1]} ${d.sub.end.year}. This is ${dt?.en ?? 'a time shaped by this planet.'} '
              '${switch (level) {
            'strong' => '${md.en} is strong in both your palm and chart, so this period should bring its best.',
            'weak' => '${md.en} needs care in both your palm and chart; its remedies help most during these years.',
            _ => 'Palm and chart show ${md.en} as balanced, so what you put in shapes what this period gives back.',
          }}',
          'आपकी कुंडली में ${md.hi} की महादशा चल रही है, और ${_monthHi[d.sub.end.month - 1]} ${d.sub.end.year} तक '
              '${ad.hi} की अंतर्दशा। यह ${dt?.hi ?? 'इस ग्रह से प्रभावित समय है।'} '
              '${switch (level) {
            'strong' => '${md.hi} हथेली और कुंडली दोनों में प्रबल है, इसलिए यह दशा अपना अच्छा फल दे सकती है।',
            'weak' => '${md.hi} हथेली और कुंडली दोनों में कमज़ोर है; इन वर्षों में इसके उपाय सबसे अधिक लाभ देंगे।',
            _ => 'हथेली और कुंडली में ${md.hi} संतुलित है, इसलिए यह दशा कितना फल देगी, यह आपकी मेहनत पर निर्भर है।',
          }}',
        ),
      ));
    }

    // Name sign and Moon sign.
    if (nameSign != null) {
      final moonSign = chart.moon.rashi;
      final same = nameSign.rashi == moonSign;
      final ruler = pName(nameSign.ruler);
      summary.add(_rule(
        'unified.name',
        area: 'personality',
        tone: same ? 'positive' : 'neutral',
        weight: 1,
        planet: nameSign.ruler,
        title: _t('Name sign ${sName(nameSign.rashi).en}', 'नाम राशि ${sName(nameSign.rashi).hi}'),
        text: same
            ? _t(
                'The first sound of your name ("${nameSign.syllable}") falls in ${sName(nameSign.rashi).en}, the same sign as your birth Moon. How people know you and how you feel inside are in tune.',
                'आपके नाम का पहला अक्षर ("${nameSign.syllable}") ${sName(nameSign.rashi).hi} राशि में आता है, जो आपकी जन्म चंद्र राशि भी है। लोग आपको जैसा जानते हैं और आप भीतर से जैसे हैं, दोनों में अच्छा तालमेल है।')
            : _t(
                'The first sound of your name ("${nameSign.syllable}") falls in ${sName(nameSign.rashi).en}, ruled by ${ruler.en}, while your birth Moon is in ${sName(moonSign).en}. Your name adds a touch of ${ruler.en} to how others see you.',
                'आपके नाम का पहला अक्षर ("${nameSign.syllable}") ${sName(nameSign.rashi).hi} राशि में आता है, जिसका स्वामी ${ruler.hi} है, जबकि आपकी जन्म चंद्र राशि ${sName(moonSign).hi} है। इसलिए दूसरों की नज़र में आपके व्यक्तित्व पर ${ruler.hi} की भी छाप दिखती है।'),
      ));
    }

    // Per planet.
    final planetInsights = <KbRule>[];
    for (final v in verdicts) {
      final strong = theme(v.planet, 'strong'), weak = theme(v.planet, 'weak');
      if (strong == null || weak == null) continue;
      final name = pName(v.planet);
      final (Strength p, Strength c) = (v.palm, v.chart);
      KbRule? r;
      if (p == Strength.strong && c == Strength.strong) {
        r = _rule('unified.${v.planet}', area: 'personality', tone: 'positive', weight: 3, planet: v.planet,
            title: _t('${name.en}: strong in palm and chart', '${name.hi}: हथेली और कुंडली दोनों में प्रबल'),
            text: _withReasons(strong, v));
      } else if (p == Strength.weak && c == Strength.weak) {
        r = _rule('unified.${v.planet}', area: 'health', tone: 'caution', weight: 2, planet: v.planet,
            title: _t('${name.en}: give it care', '${name.hi}: इसका ध्यान रखें'), text: _withReasons(weak, v));
      } else if (p == Strength.strong && c != Strength.strong) {
        r = _rule('unified.${v.planet}', area: 'personality', tone: 'positive', weight: 2, planet: v.planet,
            title: _t('${name.en}: built by your own effort', '${name.hi}: आपकी अपनी मेहनत से निखरा'),
            text: _withReasons(
              _t('Your palm shows ${name.en} better developed than your chart alone would suggest. Lines and mounds change with how you live, so you have grown these qualities yourself: ${strong.en}',
                  'आपकी हथेली में ${name.hi} कुंडली की तुलना में अधिक विकसित दिखता है। रेखाएँ और पर्वत आपके जीने के ढंग के साथ बदलते हैं, इसलिए ये गुण आपने ख़ुद विकसित किए हैं: ${strong.hi}'),
              v,
            ));
      } else if (c == Strength.strong && p != Strength.strong) {
        r = _rule('unified.${v.planet}', area: 'personality', tone: 'neutral', weight: 2, planet: v.planet,
            title: _t('${name.en}: a gift still to unfold', '${name.hi}: प्रतिभा जो अभी निखरनी है'),
            text: _withReasons(
              _t('Your chart gives ${name.en} real strength, while your palm shows it quieter for now. The promise is there to draw on: ${strong.en}',
                  'आपकी कुंडली में ${name.hi} बलवान है, जबकि हथेली में यह अभी शांत दिखता है। यह क्षमता आपके भीतर है, बस उसे काम में लाना है: ${strong.hi}'),
              v,
            ));
      } else if (p == Strength.weak || c == Strength.weak) {
        r = _rule('unified.${v.planet}', area: 'health', tone: 'caution', weight: 1, planet: v.planet,
            title: _t('${name.en}: room to grow', '${name.hi}: बढ़ने की गुंजाइश'), text: _withReasons(weak, v));
      }
      if (r != null) planetInsights.add(r);
    }

    return UnifiedReading._(verdicts, summary, planetInsights);
  }

  static PlanetVerdict _verdict(String p, PalmFeatures f, BirthChart chart, KnowledgeBase kb) {
    final (palmScore, palmReasons) = _palmScore(p, f, kb);
    final chartScore = chart.strengthScore(p);
    return PlanetVerdict(
      planet: p,
      palm: palmScore >= 1 ? Strength.strong : (palmScore <= -1 ? Strength.weak : Strength.moderate),
      chart: chart.strength(p),
      palmScore: palmScore,
      chartScore: chartScore,
      palmReasons: palmReasons,
      chartReasons: _chartReasons(p, chart, kb),
    );
  }

  /// Palm evidence for a planet: its mound, and the lines that carry it.
  static (double, List<LText>) _palmScore(String p, PalmFeatures f, KnowledgeBase kb) {
    var s = 0.0;
    final why = <LText>[];
    final name = kb.placeName(p);
    switch (f.mounds[p] ?? 'normal') {
      case 'raised':
        s += 1;
        why.add(_t('the ${name.en} mound is raised', '${name.hi} पर्वत उभरा हुआ है'));
      case 'flat':
        s -= 1;
        why.add(_t('the ${name.en} mound is flat', '${name.hi} पर्वत सपाट है'));
    }
    if (f.crossedMounds.contains(p)) {
      s -= 0.5;
      why.add(_t('fine lines cross the ${name.en} mound', '${name.hi} पर्वत पर कई बारीक रेखाएँ कटती हैं'));
    }
    bool has(String line) => f.lines[line]?.present ?? false;
    LineFeature? line(String k) => has(k) ? f.lines[k] : null;
    LText ln(String k) => kb.lineName(k);
    switch (p) {
      case 'sun':
        final l = line('sun');
        if (l != null) {
          s += l.depth == 'faint' ? 0.5 : 1;
          why.add(_t('you have a ${ln('sun').en}', 'आपके हाथ में ${ln('sun').hi} है'));
        }
      case 'saturn':
        final l = line('fate');
        if (l != null && l.depth != 'faint') {
          s += 0.5;
          why.add(_t('your ${ln('fate').en} is clear', 'आपकी ${ln('fate').hi} स्पष्ट है'));
        }
      case 'jupiter':
        if (has('jupiter_ring')) {
          s += 0.5;
          why.add(_t('you have a ${ln('jupiter_ring').en}', 'आपके हाथ में ${ln('jupiter_ring').hi} है'));
        }
        if (line('heart')?.end == 'jupiter' || line('head')?.start == 'jupiter') {
          s += 0.5;
          why.add(_t('a main line reaches the Jupiter mound', 'एक मुख्य रेखा गुरु पर्वत तक पहुँचती है'));
        }
      case 'mercury':
        final l = line('mercury');
        if (l != null && l.breaks == 'none') {
          s += 0.5;
          why.add(_t('your ${ln('mercury').en} is unbroken', 'आपकी ${ln('mercury').hi} कहीं टूटी नहीं है'));
        }
      case 'venus':
        final l = line('life');
        if (l != null && l.length == 'long' && l.depth != 'faint') {
          s += 0.5;
          why.add(_t('a long, clear ${ln('life').en} circles the Venus mound', 'लंबी, साफ़ ${ln('life').hi} शुक्र पर्वत को घेरे हुए है'));
        }
      case 'mars':
        if (has('mars_line')) {
          s += 0.5;
          why.add(_t('you have a ${ln('mars_line').en}', 'आपके हाथ में ${ln('mars_line').hi} है'));
        }
      case 'moon':
        if (line('head')?.end == 'moon') {
          s += 0.5;
          why.add(_t('your ${ln('head').en} slopes toward the Moon mound', 'आपकी ${ln('head').hi} चंद्र पर्वत की ओर झुकती है'));
        }
    }
    return (s, why);
  }

  static List<LText> _chartReasons(String p, BirthChart chart, KnowledgeBase kb) {
    final pl = chart.planets[p]!;
    final sign = kb.nameOf(pl.sign);
    final why = <LText>[];
    switch (pl.dignity) {
      case Dignity.exalted:
        why.add(_t('exalted in ${sign.en}', '${sign.hi} में उच्च का'));
      case Dignity.own:
        why.add(_t('in its own sign ${sign.en}', 'अपनी राशि ${sign.hi} में'));
      case Dignity.debilitated:
        why.add(_t('debilitated in ${sign.en}', '${sign.hi} में नीच का'));
      case Dignity.friendly:
        why.add(_t('in friendly ${sign.en}', 'मित्र राशि ${sign.hi} में'));
      case Dignity.enemy:
        why.add(_t('in unfriendly ${sign.en}', 'शत्रु राशि ${sign.hi} में'));
      case Dignity.neutral:
        why.add(_t('in ${sign.en}', '${sign.hi} में'));
    }
    final h = pl.house;
    if (h != null) {
      final house = kb.houses['$h']?.name;
      why.add(house == null ? _t('in house $h', 'भाव $h में') : _t('in the ${house.en}', '${house.hi} में'));
    }
    if (pl.combust) why.add(_t('close to the Sun (combust)', 'सूर्य के पास (अस्त)'));
    if (pl.retrograde && p != 'rahu' && p != 'ketu') why.add(_t('retrograde', 'वक्री'));
    return why;
  }

  /// "[theme] In your chart X is …; on your palm …."
  static LText _withReasons(LText theme, PlanetVerdict v) {
    String join(List<String> parts, String and) => parts.length <= 1
        ? parts.join()
        : '${parts.sublist(0, parts.length - 1).join(', ')} $and ${parts.last}';
    final c = v.chartReasons, p = v.palmReasons;
    final en = StringBuffer(theme.en);
    final hi = StringBuffer(theme.hi);
    if (c.isNotEmpty) {
      en.write(' Chart: ${join([for (final e in c) e.en], 'and')}.');
      hi.write(' कुंडली: ${join([for (final e in c) e.hi], 'और')}।');
    }
    if (p.isNotEmpty) {
      en.write(' Palm: ${join([for (final e in p) e.en], 'and')}.');
      hi.write(' हथेली: ${join([for (final e in p) e.hi], 'और')}।');
    }
    return LText(en.toString(), hi.toString());
  }

  static KbRule _rule(
    String id, {
    required String area,
    required String tone,
    required int weight,
    required LText title,
    required LText text,
    String? planet,
  }) =>
      KbRule(id: id, when: const {}, area: area, tone: tone, weight: weight, title: title, text: text, planet: planet);

  static const _elementEn = {'fire': 'Fire', 'air': 'Air', 'water': 'Water', 'earth': 'Earth'};
  static const _elementHi = {'fire': 'अग्नि', 'air': 'वायु', 'water': 'जल', 'earth': 'पृथ्वी'};
  static const _monthEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _monthHi = ['जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून', 'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर'];
}

/// Short constructor for a bilingual text.
LText _t(String en, String hi) => LText(en, hi);
