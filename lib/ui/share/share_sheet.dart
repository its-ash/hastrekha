import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../data/history_store.dart';
import '../../kb/knowledge_base.dart';
import '../../reading/rules_engine.dart';
import '../widgets/common.dart';
import '../widgets/palm_view.dart';

/// Preview of a share card, with buttons to share it as an image or text.
Future<void> showShareSheet(BuildContext context, SavedReading saved, Reading reading) {
  final key = GlobalKey();
  return UiSheet.show<void>(
    context,
    title: 'Share your reading',
    expand: true,
    child: Column(
      children: [
        RepaintBoundary(key: key, child: ShareCard(saved: saved, reading: reading)),
        const UiGap(UiSpace.lg),
        Builder(
          builder: (context) => UiButtonBar(
            expand: true,
            [
              UiButton(
                'Share text',
                variant: UiButtonVariant.outline,
                icon: Icons.notes_rounded,
                onPressed: () => SharePlus.instance.share(ShareParams(text: _asText(context, saved, reading))),
              ),
              UiButton(
                'Share image',
                icon: Icons.image_outlined,
                onPressed: () => _shareImage(context, key),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> _shareImage(BuildContext context, GlobalKey key) async {
  try {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/hastrekha_reading.png');
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'My palm reading · Hastrekha'));
  } catch (e) {
    if (context.mounted) context.showToast('Could not create the image.', status: UiStatus.danger);
  }
}

String _asText(BuildContext context, SavedReading saved, Reading reading) {
  final app = context.appRead;
  final lang = app.lang;
  final kb = app.kb;
  final b = StringBuffer()
    ..writeln(lang == Lang.hi ? 'मेरी हस्तरेखा · Hastrekha' : 'My palm reading · Hastrekha')
    ..writeln(kb.elements[saved.features.element]?.name.of(lang) ?? saved.features.element)
    ..writeln();
  for (final r in reading.highlights.take(5)) {
    b.writeln('• ${r.title.of(lang)}: ${r.text.of(lang)}');
  }
  return b.toString();
}

/// The image that gets shared: photo with lines, hand type and the top
/// insights.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.saved, required this.reading});
  final SavedReading saved;
  final Reading reading;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final el = kb.elements[saved.features.element];
    return Container(
      padding: const EdgeInsets.all(UiSpace.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(UiRadius.lg),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.back_hand_rounded, color: context.colors.accent),
              const UiGap(UiSpace.sm),
              Text('Hastrekha', style: context.text.titleMedium),
              const Spacer(),
              Text(Labels.value(saved.hand, lang), style: context.text.bodySmall),
            ],
          ),
          const UiGap(UiSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 120, child: PalmView(overlay: saved.overlay, file: saved.photoPath, showMinor: false, radius: UiRadius.sm)),
              const UiGap(UiSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText2(el?.name ?? LText(saved.features.element), style: context.text.titleLarge),
                    if (el?.str('dosha') != null) Text('${el!.str('dosha')} · ${el.str('devanagari') ?? ''}', style: context.text.bodySmall),
                    const UiGap(UiSpace.sm),
                    for (final r in reading.highlights.take(4))
                      Padding(
                        padding: const EdgeInsets.only(bottom: UiSpace.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Labels.toneIcon(r.tone), size: 14, color: context.colors.tone(Labels.tone(r.tone)).color),
                            const UiGap(UiSpace.xs),
                            Expanded(child: LText2(r.title, style: context.text.bodySmall, maxLines: 2)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (reading.highlights.isNotEmpty) ...[
            const UiGap(UiSpace.md),
            LText2(reading.highlights.first.text, style: context.text.bodyMedium, maxLines: 4),
          ],
        ],
      ),
    );
  }
}
