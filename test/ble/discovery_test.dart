import 'package:app/ble/discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scanBlocker', () {
    test('Android 11 and older need location, whatever Bluetooth says', () {
      for (final sdkInt in [26, 29, 30]) {
        expect(
          scanBlocker(
            sdkInt: sdkInt,
            bluetoothGranted: true,
            locationGranted: false,
          ),
          ScanBlocker.location,
          reason: 'API $sdkInt',
        );
        expect(
          scanBlocker(
            sdkInt: sdkInt,
            bluetoothGranted: true,
            locationGranted: true,
          ),
          isNull,
          reason: 'API $sdkInt',
        );
      }
    });

    test('Android 12 and newer scan without location', () {
      expect(
        scanBlocker(sdkInt: 31, bluetoothGranted: true, locationGranted: false),
        isNull,
      );
      expect(
        scanBlocker(sdkInt: 35, bluetoothGranted: false, locationGranted: true),
        ScanBlocker.bluetooth,
      );
    });
  });
}
