import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kb/knowledge_base.dart';
import '../reading/astro.dart';
import '../reading/chart.dart';
import '../reading/name_sign.dart';
import 'places.dart';

/// Birth details for the birth chart (kundali) and the birth star.
class BirthProfile {
  const BirthProfile({
    this.name = '',
    this.birthDate,
    this.birthTime,
    this.utcOffsetMinutes = 330,
    this.place,
  });

  final String name;
  final DateTime? birthDate;

  /// Local time of birth. Null when unknown (noon is used).
  final TimeOfDay? birthTime;

  /// Time zone of the birth place, minutes east of UTC (India = 330).
  final int utcOffsetMinutes;

  /// Birth place. With the birth time it gives the ascendant and houses.
  final Place? place;

  bool get hasBirth => birthDate != null;

  /// Name and date are what the combined reading needs at least.
  bool get isComplete => name.trim().isNotEmpty && birthDate != null;

  /// The full chart, with lagna and houses when time and place are known.
  BirthChart? get chart {
    final utc = birthUtc;
    if (utc == null) return null;
    return BirthChart.compute(
      utc,
      timeKnown: birthTime != null,
      latitude: place?.latitude,
      longitude: place?.longitude,
    );
  }

  NameSign? get nameSign => name.trim().isEmpty ? null : NameSign.of(name);

  /// Birth moment in UTC.
  DateTime? get birthUtc {
    final d = birthDate;
    if (d == null) return null;
    final t = birthTime ?? const TimeOfDay(hour: 12, minute: 0);
    return DateTime.utc(d.year, d.month, d.day, t.hour, t.minute).subtract(Duration(minutes: utcOffsetMinutes));
  }

  MoonPlacement? get moon {
    final utc = birthUtc;
    return utc == null ? null : Astro.moonPlacement(utc);
  }

  BirthProfile copyWith({
    String? name,
    DateTime? birthDate,
    bool clearDate = false,
    TimeOfDay? birthTime,
    bool clearTime = false,
    int? utcOffsetMinutes,
    Place? place,
    bool clearPlace = false,
  }) =>
      BirthProfile(
        name: name ?? this.name,
        birthDate: clearDate ? null : (birthDate ?? this.birthDate),
        birthTime: clearTime ? null : (birthTime ?? this.birthTime),
        utcOffsetMinutes: utcOffsetMinutes ?? this.utcOffsetMinutes,
        place: clearPlace ? null : (place ?? this.place),
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'birthDate': birthDate?.toIso8601String(),
        'birthTime': birthTime == null ? null : '${birthTime!.hour}:${birthTime!.minute}',
        'utcOffsetMinutes': utcOffsetMinutes,
        'place': place?.toJson(),
      };

  factory BirthProfile.fromJson(Map<String, Object?> j) {
    TimeOfDay? time;
    final t = j['birthTime'] as String?;
    if (t != null) {
      final p = t.split(':');
      time = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }
    return BirthProfile(
      name: j['name'] as String? ?? '',
      birthDate: DateTime.tryParse(j['birthDate'] as String? ?? ''),
      birthTime: time,
      utcOffsetMinutes: (j['utcOffsetMinutes'] as num?)?.toInt() ?? 330,
      place: Place.fromJson(j['place']),
    );
  }
}

/// App preferences, stored in shared preferences.
class SettingsStore {
  SettingsStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<SettingsStore> open() async => SettingsStore(await SharedPreferences.getInstance());

  Lang get lang => _prefs.getString('lang') == 'hi' ? Lang.hi : Lang.en;
  set lang(Lang v) => _prefs.setString('lang', v.name);

  ThemeMode get themeMode => ThemeMode.values.firstWhere(
        (m) => m.name == _prefs.getString('themeMode'),
        orElse: () => ThemeMode.system,
      );
  set themeMode(ThemeMode v) => _prefs.setString('themeMode', v.name);

  /// The hand the user writes with: 'right' or 'left'.
  String get dominantHand => _prefs.getString('dominantHand') ?? 'right';
  set dominantHand(String v) => _prefs.setString('dominantHand', v);

  bool get onboarded => _prefs.getBool('onboarded') ?? false;
  set onboarded(bool v) => _prefs.setBool('onboarded', v);

  BirthProfile get profile {
    final s = _prefs.getString('profile');
    if (s == null) {
      return BirthProfile(utcOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes);
    }
    return BirthProfile.fromJson((jsonDecode(s) as Map).cast<String, Object?>());
  }

  set profile(BirthProfile p) => _prefs.setString('profile', jsonEncode(p.toJson()));

  Future<void> clear() => _prefs.clear();
}
