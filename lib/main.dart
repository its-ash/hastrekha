import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import 'app/app_state.dart';
import 'app/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fully offline: use the bundled platform font, never download fonts.
  UiTypography.useGoogleFonts = false;
  runApp(const HastrekhaApp());
}

/// Saffron, for a Vedic feel. The only brand color; everything else
/// comes from the shared theme.
const brandAccent = Color(0xFFC2410C);

class HastrekhaApp extends StatefulWidget {
  const HastrekhaApp({super.key});

  @override
  State<HastrekhaApp> createState() => _HastrekhaAppState();
}

class _HastrekhaAppState extends State<HastrekhaApp> {
  final _theme = UiThemeController(accent: brandAccent);
  late final Future<AppState> _load = AppState.load().then((s) {
    _theme.mode = s.settings.themeMode;
    return s;
  });

  @override
  void dispose() {
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AppScope must sit above the app's Navigator so pushed screens and
    // sheets can reach it.
    return FutureBuilder<AppState>(
      future: _load,
      builder: (context, snap) {
        final state = snap.data;
        if (state == null) {
          return UiApp(
            title: 'Hastrekha',
            controller: _theme,
            home: Scaffold(
              body: snap.hasError
                  ? UiErrorState(message: '${snap.error}')
                  : const Center(child: UiSpinner(size: 28)),
            ),
          );
        }
        return AppScope(
          state: state,
          child: UiApp(title: 'Hastrekha', controller: _theme, home: const HomeShell()),
        );
      },
    );
  }
}
