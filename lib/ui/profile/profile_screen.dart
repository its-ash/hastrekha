import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../kb/knowledge_base.dart';
import '../library/entry_detail_screen.dart';
import 'birth_editor.dart';

/// Birth details, preferences, privacy and about.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final p = app.profile;
    final moon = p.moon;
    final chart = p.chart;
    return Scaffold(
      appBar: const UiAppBar(title: 'Profile'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(UiContent.pagePadding(context), UiSpace.sm, UiContent.pagePadding(context), UiSpace.xxxl),
        children: [
          UiListGroup(
            header: 'You',
            children: [
              UiListTile(
                p.name.isEmpty ? 'Add your name' : p.name,
                subtitle: p.birthDate == null
                    ? 'Birth date not set'
                    : '${UiDateFormat.date(p.birthDate!)}${p.birthTime == null ? '' : ' · ${UiDateFormat.time(context, p.birthTime!)}'}'
                        '${p.place == null ? '' : ' · ${p.place!.name}'}',
                icon: Icons.cake_outlined,
                chevron: true,
                onTap: () => showBirthEditor(context),
              ),
              if (moon != null)
                UiListTile(
                  kb.nakshatras[moon.nakshatra - 1].name.of(app.lang),
                  subtitle: 'Birth star · Moon in ${kb.placeName(moon.rashi).of(app.lang)}',
                  icon: Icons.auto_awesome_outlined,
                  chevron: true,
                  onTap: () => openEntry(context, kb.nakshatras[moon.nakshatra - 1], kind: EntryKind.nakshatra),
                ),
              if (chart?.lagna != null)
                UiListTile(
                  kb.nameOf(chart!.lagna!).of(app.lang),
                  subtitle: 'Rising sign (lagna)',
                  icon: Icons.wb_twilight_rounded,
                  chevron: true,
                  onTap: () => openEntry(context, kb.rashis[chart.lagna!]!, kind: EntryKind.rashi),
                ),
            ],
          ),
          const UiGap(UiSpace.xl),
          UiListGroup(
            header: 'Preferences',
            children: [
              UiListTile(
                'Writing hand',
                icon: Icons.edit_outlined,
                trailing: UiSegmentedControl<String>(
                  const [UiSegment('left', label: 'Left'), UiSegment('right', label: 'Right')],
                  value: app.dominantHand,
                  size: UiSize.sm,
                  onChanged: (v) => context.appRead.dominantHand = v,
                ),
              ),
              UiListTile(
                'Reading language',
                icon: Icons.translate_rounded,
                trailing: UiSegmentedControl<Lang>(
                  [for (final l in Lang.values) UiSegment(l, label: l.label)],
                  value: app.lang,
                  size: UiSize.sm,
                  onChanged: (v) => context.appRead.lang = v,
                ),
              ),
            ],
          ),
          const UiGap(UiSpace.xl),
          const UiListGroup(
            header: 'Privacy',
            footer: 'Hastrekha has no internet access. Photos, readings and birth details never leave this phone.',
            children: [
              UiListTile('Works fully offline', icon: Icons.wifi_off_rounded, iconStatus: UiStatus.success),
            ],
          ),
          const UiGap(UiSpace.xl),
          UiListGroup(
            header: 'About',
            children: [
              UiListTile(
                'About Vedic palmistry',
                icon: Icons.info_outline_rounded,
                chevron: true,
                onTap: () {
                  final intro = kb.learn.firstOrNull;
                  if (intro != null) openEntry(context, intro, kind: EntryKind.article);
                },
              ),
              UiListTile(
                'How the camera reads your palm',
                icon: Icons.photo_camera_outlined,
                chevron: true,
                onTap: () => UiDialog.alert(
                  context,
                  title: 'How it works',
                  message: 'Hastrekha finds your hand by its skin tone, measures the palm and fingers, then traces '
                      'the creases as thin dark valleys in the skin. The camera takes a few quick photos and lines '
                      'them up, so faint lines stand out from skin texture and glare. Each line is then searched '
                      'for along the path it usually takes, which finds lines too faint to see at a glance. You can '
                      'check and correct every line before the reading.\n\nWith your birth details, the planets at '
                      'your birth are worked out on the phone and read together with your palm.',
                ),
              ),
            ],
          ),
          const UiGap(UiSpace.xl),
          const UiAppearanceSection(),
          const UiGap(UiSpace.xl),
          // No INTERNET permission: the row opens the latest APK download in the browser.
          const UiUpdateSection(storeId: 'hastrekha', checkForUpdates: false),
          const UiGap(UiSpace.xl),
          UiHoldButton(
            'Hold to erase all data',
            icon: Icons.delete_forever_outlined,
            expand: true,
            onConfirmed: () async {
              await context.appRead.eraseEverything();
              if (context.mounted) context.showToast('All readings and settings erased.', status: UiStatus.success);
            },
          ),
          const UiGap(UiSpace.xl),
          const UiDeveloperSection(),
        ],
      ),
    );
  }
}
