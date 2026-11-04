import 'package:flutter/widgets.dart';

import 'api/api_client.dart';
import 'ble/connection_manager.dart';

/// App-wide services available below the signed-in part of the tree.
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.api,
    required this.ble,
    required super.child,
  });

  final ApiClient api;
  final BleConnectionManager ble;

  static AppServices of(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'AppServices is missing from the widget tree');
    return services!;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) =>
      api != oldWidget.api || ble != oldWidget.ble;
}
