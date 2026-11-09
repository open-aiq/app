import 'package:flutter/material.dart';

import '../api/models.dart';
import '../features/account/account.dart';
import '../theme.dart';
import '../tokens.g.dart';
import '../widgets/aiq_app_bar.dart';
import '../widgets/monitor_card.dart';
import '../widgets/monitor_illustration.dart';
import '../widgets/sections.dart';
import '../widgets/states.dart';
import '../widgets/tiles.dart';

/// The shared components with mock data, section by section in the same
/// order as the docs site's visual playground page, so you can hold the two
/// side by side. Run it with `make gallery`; it needs no sign-in or network.
///
/// It uses the real top bar and avatar menu with a sample account, so the
/// theme, Settings and links work here just as they do in the app.
class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key, this.themeMode = ThemeMode.system});

  final ThemeMode themeMode;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  static const _account = Account(
    name: 'Riley Review',
    email: 'riley@example.com',
  );

  @override
  void initState() {
    super.initState();
    themeModePreference.value = widget.themeMode;
  }

  Future<void> _signOut(BuildContext context) async {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('The gallery keeps you signed in.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AccountScope(
      account: _account,
      onSignOut: _signOut,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModePreference,
        builder: (context, mode, _) => MaterialApp(
          title: 'Open AIQ gallery',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: mode,
          home: const GalleryScreen(),
        ),
      ),
    );
  }
}

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final seen = DateTime.now().subtract(const Duration(minutes: 2));
    return Scaffold(
      appBar: const AiqAppBar(
        title: 'Gallery',
        subtitle: 'Shared screens with mock data',
      ),
      body: ListView(
        padding: pagePadding,
        children: [
          const SectionLabel('Monitor card'),
          MonitorCard(device: _garden, reading: _reading(32, seen)),
          _gap,
          const MonitorCard(device: _kitchen, loading: true),
          _gap,
          const MonitorCard(device: _newSensor),
          _gap,
          MonitorCard(
            device: _ridge,
            reading: _reading(
              340,
              DateTime.now().subtract(const Duration(hours: 3)),
              online: false,
            ),
          ),
          _gap,
          const MonitorCardSkeleton(),
          const SizedBox(height: 32),
          const SectionLabel('Inside the monitor'),
          const AqiTile(aqi: 78, caption: 'Averages over the last hour'),
          _gap,
          MetricGroups(
            groups: metricGroups(
              pm25: 23.8,
              pm10: 33.8,
              pm1: 16.2,
              temperature: 22.1,
              humidity: 46,
              heatIndex: 22.7,
            ),
          ),
          _gap,
          SkeletonShape(
            radius: AiqRadii.sheet,
            child: const AqiTile(aqi: null),
          ),
          _gap,
          MetricGroups(groups: metricGroups(), loading: true),
          const SizedBox(height: 32),
          const SectionLabel('AQI bands'),
          for (final aqi in const [32, 78, 128, 172, 240, 340, null]) ...[
            AqiBlock(aqi: aqi, height: 96),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 24),
          const SectionLabel('States'),
          const EmptyView(
            illustration: MonitorIllustration(),
            title: 'No readings yet',
            message:
                'Once your monitor is online and sending data, its readings '
                'show up here.',
          ),
          const ErrorView(message: 'We couldn’t load your monitors.'),
          QuietNote(updatedAt: seen, onRetry: () {}),
          _gap,
          const Skeleton(child: SkeletonBlock(height: 96, radius: AiqRadii.xl)),
        ],
      ),
    );
  }
}

const _gap = SizedBox(height: 16);

const _garden = Device(
  id: 'dev-garden',
  deviceId: 'dev_garden000000a1b2c3d4e5f6',
  name: 'Back garden',
  isOutdoor: true,
  isPublic: true,
  isLocationPublic: true,
  firmwareVersion: '0.6.2',
  ota: OtaSummary(status: 'up_to_date', version: '0.6.2'),
);

const _kitchen = Device(
  id: 'dev-kitchen',
  deviceId: 'dev_kitchen00000a1b2c3d4e5f6',
  name: 'Kitchen',
  isOutdoor: false,
  isPublic: false,
  isLocationPublic: false,
);

const _newSensor = Device(
  id: 'dev-new',
  deviceId: 'dev_new000000000a1b2c3d4e5f6',
  name: 'New sensor',
  isOutdoor: false,
  isPublic: false,
  isLocationPublic: false,
  ota: OtaSummary(status: 'update_available', version: '0.6.2'),
);

const _ridge = Device(
  id: 'dev-ridge',
  deviceId: 'dev_ridge0000000a1b2c3d4e5f6',
  name: 'Ridge lookout',
  isOutdoor: true,
  isPublic: true,
  isLocationPublic: true,
);

CurrentReading _reading(int aqi, DateTime seen, {bool online = true}) {
  return CurrentReading(
    online: online,
    lastSeen: seen,
    sampleCount: 58,
    metrics: Metrics(
      aqi: aqi,
      pm25: aqi / 5.5,
      pm10: aqi / 3.9,
      pm1: aqi / 8,
      temperature: 22.4,
      humidity: 64,
      heatIndex: 23.0,
    ),
  );
}
