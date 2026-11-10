import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../../app/app_state.dart';
import '../../../kb/knowledge_base.dart';
import '../../../reading/astro.dart';
import '../../../reading/rules_engine.dart';
import '../../widgets/remedy_card.dart';
import '../reading_screen.dart';

/// Remedies for the planets the reading asks to strengthen, plus the
/// ruler of the birth star when known.
class RemediesTab extends StatelessWidget {
  const RemediesTab({super.key, required this.reading});
  final Reading reading;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final hi = app.lang == Lang.hi;
    final planets = reading.planetsToStrengthen.take(3).toList();
    final moon = app.profile.moon;
    final starRuler = moon == null ? null : Astro.rulerOfNakshatra(moon.nakshatra);
    final today = Astro.weekdayRuler[DateTime.now().weekday]!;

    List<LText> reasons(String p) => [
          for (final r in reading.insights)
            if (r.planet == p && r.tone == 'caution' && r.title.en.isNotEmpty) r.title,
          if (reading.features.mounds[p] == 'flat') LText('Flat ${kb.placeName(p).en} mound', 'सपाट ${kb.placeName(p).hi} पर्वत'),
          if (reading.features.crossedMounds.contains(p))
            LText('Many lines on the ${kb.placeName(p).en} mound', '${kb.placeName(p).hi} पर्वत पर कई रेखाएँ'),
        ].take(3).toList();

    return TabBody(
      children: [
        Text(
          hi
              ? 'उपाय (उपाय) उन ग्रहों को संतुलित करने के पारंपरिक तरीके हैं जिन पर आपकी हथेली ध्यान देने को कहती है।'
              : 'Upayas are traditional ways to steady the planets your palm asks you to look after.',
          style: context.text.bodyMedium,
        ),
        const RemedyNote(),
        if (planets.isEmpty)
          UiEmptyState(
            compact: true,
            icon: Icons.verified_outlined,
            title: hi ? 'कोई ग्रह कमज़ोर नहीं दिखा' : 'No planet stands out as weak',
            message: hi
                ? 'आपकी हथेली संतुलित दिखती है। चाहें तो आज के ग्रह का उपाय करें।'
                : 'Your palm looks balanced. You can still follow the remedy for today’s planet.',
          )
        else ...[
          UiSectionHeader(hi ? 'आपकी हथेली के लिए' : 'For your palm'),
          for (final (i, p) in planets.indexed) RemedyCard(planet: p, reasons: reasons(p), initiallyOpen: i == 0),
        ],
        if (starRuler != null && !planets.contains(starRuler)) ...[
          UiSectionHeader(
            hi ? 'आपके जन्म नक्षत्र के लिए' : 'For your birth star',
            subtitle: kb.nakshatras[moon!.nakshatra - 1].name.of(app.lang),
          ),
          RemedyCard(planet: starRuler),
        ],
        if (!planets.contains(today) && today != starRuler) ...[
          UiSectionHeader(hi ? 'आज का ग्रह' : 'Today’s planet'),
          RemedyCard(planet: today),
        ],
      ],
    );
  }
}
