import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// AQI band presentation from the shared design tokens (US EPA bands with the
/// IQAir palette), the same bands as the web dashboard. Always render [label]
/// with the color so meaning never rides on color alone.
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

AqiInfo _info(AiqBandToken band) =>
    AqiInfo(band.label, band.background, band.foreground, band.short);

final _bands = [for (final band in aiqBands) (band.max, _info(band))];
final _unknown = _info(aiqUnknownBand);

AqiInfo aqiInfo(num? aqi) {
  if (aqi == null || aqi.isNaN) return _unknown;
  for (final (max, info) in _bands) {
    if (max == null || aqi <= max) return info;
  }
  return _bands.last.$2;
}
