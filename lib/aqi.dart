import 'package:flutter/material.dart';

/// AQI band presentation; mirrors frontend/src/lib/aqi.js (US EPA bands with
/// the IQAir palette). Always render [label] with the color so meaning never
/// rides on color alone.
@immutable
class AqiInfo {
  const AqiInfo(this.label, this.background, this.foreground, [String? short])
    : short = short ?? label;

  final String label;

  /// A word or two for tight spaces, such as the home screen cards.
  final String short;
  final Color background;
  final Color foreground;
}

const _bands = <(int, AqiInfo)>[
  (50, AqiInfo('Good', Color(0xFFA8E05F), Color(0xFF718B3A))),
  (100, AqiInfo('Moderate', Color(0xFFFDD64B), Color(0xFFA57F23))),
  (
    150,
    AqiInfo(
      'Unhealthy for Sensitive Groups',
      Color(0xFFFF9B57),
      Color(0xFFB25826),
      'Unhealthy for some',
    ),
  ),
  (200, AqiInfo('Unhealthy', Color(0xFFFE6A69), Color(0xFFAF2C3B))),
  (300, AqiInfo('Very Unhealthy', Color(0xFFA97ABC), Color(0xFF634675))),
];

const _hazardous = AqiInfo('Hazardous', Color(0xFFA87383), Color(0xFF683E51));
const _unknown = AqiInfo(
  'Unknown',
  Color(0xFFE5E5E5),
  Color(0xFF525252),
  'No data',
);

AqiInfo aqiInfo(num? aqi) {
  if (aqi == null || aqi.isNaN) return _unknown;
  for (final (max, info) in _bands) {
    if (aqi <= max) return info;
  }
  return _hazardous;
}
