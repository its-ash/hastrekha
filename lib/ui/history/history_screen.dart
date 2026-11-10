import 'dart:io';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../app/home_shell.dart';
import '../../data/history_store.dart';
import '../reading/reading_screen.dart';
import '../widgets/common.dart';
import 'compare_screen.dart';

/// All saved readings, newest first.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final readings = app.readings;
    final pair = app.latestPair;
    return Scaffold(
      appBar: const UiAppBar(title: 'Readings'),
      body: readings.isEmpty
          ? UiEmptyState(
              icon: Icons.back_hand_outlined,
              title: 'No readings yet',
              message: 'Your palm readings are saved here, on this phone only.',
              action: UiButton('Read my palm', onPressed: () => HomeShell.goTo(context, HomeShell.home)),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(UiContent.pagePadding(context), UiSpace.sm, UiContent.pagePadding(context), UiSpace.xxxl),
              children: [
                if (pair.left != null && pair.right != null) ...[
                  UiCard(
                    variant: UiCardVariant.filled,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CompareScreen(left: pair.left!, right: pair.right!),
                    )),
                    child: const UiListTile(
                      'Compare left and right',
                      subtitle: 'See what you were born with next to what you are building.',
                      icon: Icons.compare_rounded,
                      chevron: true,
                    ),
                  ),
                  const UiGap(UiSpace.lg),
                ] else ...[
                  UiAlert(
                    'Read your ${pair.left == null ? 'left' : 'right'} hand too, to compare both hands.',
                    status: UiStatus.info,
                    icon: Icons.compare_rounded,
                  ),
                  const UiGap(UiSpace.lg),
                ],
                for (final r in readings) ...[
                  _ReadingTile(r),
                  const UiGap(UiSpace.md),
                ],
              ],
            ),
    );
  }
}

class _ReadingTile extends StatelessWidget {
  const _ReadingTile(this.r);
  final SavedReading r;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final el = app.kb.elements[r.features.element];
    final found = r.features.lines.values.where((l) => l.present).length;
    return Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => UiDialog.confirm(
        context,
        title: 'Delete this reading?',
        confirmLabel: 'Delete',
        destructive: true,
      ),
      onDismissed: (_) => context.appRead.deleteReading(r.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: UiSpace.xl),
        decoration: BoxDecoration(
          color: context.colors.danger,
          borderRadius: BorderRadius.circular(UiRadius.lg),
        ),
        child: Icon(Icons.delete_outline_rounded, color: context.colors.onDanger),
      ),
      child: UiCard(
        onTap: () => openSavedReading(context, r),
        padding: const EdgeInsets.all(UiSpace.md),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(UiRadius.sm),
              child: Image.file(File(r.photoPath), width: 64, height: 84, fit: BoxFit.cover, cacheWidth: 200),
            ),
            const UiGap(UiSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Labels.value(r.hand), style: context.text.titleSmall),
                  Text(
                    '${el?.name.of(app.lang) ?? r.features.element} · $found lines',
                    style: context.text.bodyMedium,
                  ),
                  const UiGap(UiSpace.xs),
                  Text(_date(r.createdAt), style: context.text.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime d) => '${UiDateFormat.date(d)} · ${UiFormat.relativeTime(d)}';
}
