import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../data/places.dart';
import '../../data/settings.dart';

/// Common time zones, minutes east of UTC.
const _zones = <(int, String)>[
  (330, 'India (UTC+5:30)'),
  (345, 'Nepal (UTC+5:45)'),
  (360, 'Bangladesh, Bhutan (UTC+6)'),
  (300, 'Pakistan, Maldives (UTC+5)'),
  (270, 'Afghanistan (UTC+4:30)'),
  (240, 'UAE, Oman, Mauritius (UTC+4)'),
  (210, 'Iran (UTC+3:30)'),
  (180, 'Saudi Arabia, Qatar, Kenya (UTC+3)'),
  (120, 'Central Europe summer, South Africa (UTC+2)'),
  (60, 'UK summer / Central Europe (UTC+1)'),
  (0, 'UK, Ireland, Portugal winter (UTC+0)'),
  (420, 'Thailand, Indonesia (UTC+7)'),
  (480, 'Singapore, Malaysia, China (UTC+8)'),
  (540, 'Japan, Korea (UTC+9)'),
  (570, 'Adelaide, winter (UTC+9:30)'),
  (600, 'Sydney, winter (UTC+10)'),
  (720, 'New Zealand, Fiji winter (UTC+12)'),
  (-180, 'Brazil, Argentina (UTC−3)'),
  (-240, 'New York summer, Caribbean (UTC−4)'),
  (-300, 'New York, Toronto winter (UTC−5)'),
  (-360, 'Chicago, winter (UTC−6)'),
  (-420, 'Denver, winter / California summer (UTC−7)'),
  (-480, 'California, Vancouver winter (UTC−8)'),
];

String _zoneLabel(int m) {
  final sign = m >= 0 ? '+' : '−';
  return 'UTC$sign${m.abs() ~/ 60}:${(m.abs() % 60).toString().padLeft(2, '0')}';
}

/// Sheet to set name, birth date, time, place and time zone. With
/// [prompt] it is shown before a reading and offers to skip. Returns
/// true when the details were saved.
Future<bool> showBirthEditor(BuildContext context, {bool prompt = false}) async {
  final saved = await UiSheet.show<bool>(
    context,
    title: prompt ? 'Add your birth details' : 'Birth details',
    subtitle: prompt
        ? 'Your palm is read together with your birth chart. Stays on this phone.'
        : 'For your birth chart, birth star and name sign. Stays on this phone.',
    expand: true,
    child: _BirthForm(prompt: prompt),
  );
  return saved ?? false;
}

class _BirthForm extends StatefulWidget {
  const _BirthForm({required this.prompt});
  final bool prompt;

  @override
  State<_BirthForm> createState() => _BirthFormState();
}

class _BirthFormState extends State<_BirthForm> {
  late BirthProfile _p = context.appRead.profile;
  late final _name = TextEditingController(text: _p.name);
  late final _place = TextEditingController(text: _p.place?.label ?? '');
  late final _lat = TextEditingController(text: _p.place?.latitude.toStringAsFixed(4) ?? '');
  late final _lon = TextEditingController(text: _p.place?.longitude.toStringAsFixed(4) ?? '');
  late bool _manual = _p.place != null && _p.place!.utcOffsetMinutes == null;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    Places.load(); // warm the city list
  }

  @override
  void dispose() {
    _name.dispose();
    _place.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  void _pickPlace(Place p) {
    setState(() {
      _p = _p.copyWith(place: p, utcOffsetMinutes: p.utcOffsetMinutes);
      _lat.text = p.latitude.toStringAsFixed(4);
      _lon.text = p.longitude.toStringAsFixed(4);
    });
  }

  void _manualChanged() {
    final lat = double.tryParse(_lat.text.trim()), lon = double.tryParse(_lon.text.trim());
    setState(() {
      if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
        _p = _p.copyWith(clearPlace: true);
      } else {
        final name = _place.text.trim();
        _p = _p.copyWith(place: Place(name: name.isEmpty ? 'Birth place' : name, region: '', latitude: lat, longitude: lon));
      }
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _p.birthDate == null) {
      setState(() => _tried = true);
      return;
    }
    context.appRead.profile = _p.copyWith(name: name);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final zones = [..._zones];
    if (!zones.any((z) => z.$1 == _p.utcOffsetMinutes)) {
      zones.insert(0, (_p.utcOffsetMinutes, _zoneLabel(_p.utcOffsetMinutes)));
    }
    final preview = _p.copyWith(name: _name.text);
    final chart = preview.chart;
    final nameSign = preview.nameSign;
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))];

    return UiColumn(
      gap: UiSpace.lg,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiTextField(
          label: 'Name',
          isRequired: true,
          controller: _name,
          size: UiSize.lg,
          hint: 'Your full name',
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.name],
          textCapitalization: TextCapitalization.words,
          helper: 'The first sound of your name gives your name sign (nāma rāśi). Hindi script works too.',
          error: _tried && _name.text.trim().isEmpty ? 'Enter your name' : null,
          onChanged: (_) => setState(() {}),
        ),
        UiDateField(
          label: 'Date of birth',
          isRequired: true,
          value: _p.birthDate,
          lastDate: DateTime.now(),
          error: _tried && _p.birthDate == null ? 'Choose your date of birth' : null,
          onChanged: (d) => setState(() => _p = _p.copyWith(birthDate: d, clearDate: d == null)),
        ),
        UiTimeField(
          label: 'Time of birth',
          helper: 'Needed for the rising sign (lagna) and houses. Leave empty if you do not know it.',
          value: _p.birthTime,
          onChanged: (t) => setState(() => _p = _p.copyWith(birthTime: t, clearTime: t == null)),
        ),
        UiAutocomplete<Place>(
          label: 'Place of birth',
          hint: 'Search a city',
          controller: _place,
          search: (q) async => (await Places.load()).search(q),
          displayString: (p) => p.name,
          subtitle: (p) => p.region,
          prefixIcon: Icons.location_on_outlined,
          emptyText: 'Not in the list. Enter the coordinates below.',
          helper: _p.place == null ? 'The nearest large city is close enough.' : _p.place!.coordinates,
          onSelected: _pickPlace,
        ),
        UiSwitch(
          _manual,
          label: 'Enter coordinates by hand',
          description: 'For a town not in the list. Decimal degrees; south and west are negative.',
          onChanged: (v) => setState(() => _manual = v),
        ),
        if (_manual)
          Row(
            children: [
              Expanded(
                child: UiTextField(
                  label: 'Latitude',
                  hint: 'e.g. 26.92',
                  controller: _lat,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  inputFormatters: numbers,
                  onChanged: (_) => _manualChanged(),
                ),
              ),
              const UiGap(UiSpace.md),
              Expanded(
                child: UiTextField(
                  label: 'Longitude',
                  hint: 'e.g. 75.79',
                  controller: _lon,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  inputFormatters: numbers,
                  onChanged: (_) => _manualChanged(),
                ),
              ),
            ],
          ),
        UiSelect<int>(
          label: 'Time zone at birth',
          helper: 'Set from the city. If summer time was in use at the birth, choose that offset.',
          value: _p.utcOffsetMinutes,
          options: [for (final z in zones) UiOption(z.$1, z.$2)],
          onChanged: (v) => setState(() => _p = _p.copyWith(utcOffsetMinutes: v)),
        ),
        if (chart != null)
          UiAlert(
            [
              if (chart.lagna != null) 'Rising sign: ${app.kb.nameOf(chart.lagna!).en}',
              'Moon sign: ${app.kb.nameOf(chart.moon.rashi).en}',
              'Birth star: ${app.kb.nakshatras[chart.moon.nakshatra - 1].name.en}, pada ${chart.moon.pada}',
              if (nameSign != null) 'Name sign: ${app.kb.nameOf(nameSign.rashi).en}',
              if (chart.lagna == null) 'Add the time and place of birth for the rising sign and houses.',
            ].join('\n'),
            title: 'Your chart',
            status: UiStatus.success,
            icon: Icons.auto_awesome_rounded,
          ),
        UiButton('Save', expand: true, onPressed: _save),
        if (widget.prompt)
          UiButton(
            'Skip for now',
            expand: true,
            variant: UiButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(false),
          ),
      ],
    );
  }
}
