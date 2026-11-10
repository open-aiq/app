import 'package:flutter/material.dart';

import '../ble/connection_manager.dart';
import '../features/account/account.dart';
import '../features/account/account_screen.dart';
import '../features/account/settings_screen.dart';
import '../features/device_detail/device_detail_screen.dart';
import '../features/devices/device_list_screen.dart';
import '../services.dart';
import '../theme.dart';
import '../tokens.g.dart';
import '../widgets/aiq_app_bar.dart';
import '../widgets/monitor_card.dart';
import '../widgets/monitor_illustration.dart';
import '../widgets/sections.dart';
import '../widgets/states.dart';
import '../widgets/tiles.dart';
import 'fixtures.dart';
import 'mock_account_actions.dart';
import 'mock_api.dart';

/// The screens the gallery can open, by their `?screen=` key. The hosted
/// prototype's Screen picker (`frontend/prototype/index.html`) uses the same
/// keys, so keep the two in step.
const galleryScreens = [
  'gallery',
  'monitors',
  'monitor',
  'monitor-new',
  'monitor-logs',
  'monitor-settings',
  'settings',
  'account',
];

/// The shared components with mock data, section by section in the same
/// order as the docs site's visual playground page, so you can hold the two
/// side by side. Run it with `make gallery`; it needs no sign-in or network.
///
/// With a [screen] key it opens one of the app's real screens instead, on the
/// mock backend in `mock_api.dart` and the mock account in
/// `mock_account_actions.dart`. Bluetooth isn't faked, so Bluetooth actions
/// fail calmly here.
///
/// It uses the real top bar and avatar menu with a sample account, so the
/// theme, Settings and links work here just as they do in the app.
class GalleryApp extends StatefulWidget {
  const GalleryApp({
    super.key,
    this.themeMode = ThemeMode.system,
    this.screen,
    this.delay = const Duration(milliseconds: 300),
  });

  final ThemeMode themeMode;

  /// A key from [galleryScreens]. Null or unknown opens the gallery.
  final String? screen;

  /// How long mock requests and account changes take.
  final Duration delay;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final _api = MockApi(delay: widget.delay);
  late final _actions = MockAccountActions(
    api: _api.client,
    messenger: _messenger,
    delay: widget.delay,
  );
  final _ble = BleConnectionManager();

  @override
  void initState() {
    super.initState();
    themeModePreference.value = widget.themeMode;
  }

  @override
  void dispose() {
    _actions.dispose();
    _ble.dispose();
    super.dispose();
  }

  Account get _account => Account(
    name: 'Riley Review',
    email: _actions.emails.where((e) => e.isPrimary).firstOrNull?.address,
    username: _actions.username,
  );

  Future<void> _signOut(BuildContext context) async {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('The gallery keeps you signed in.')),
    );
  }

  /// The screens under the one you asked for, as you'd reach it in the app,
  /// so the back button works and nothing pops to an empty page.
  List<Widget> _stack() {
    final garden = fixtureDevice('dev-garden');
    return switch (widget.screen) {
      'monitors' => const [DeviceListScreen()],
      'monitor' => [
        const DeviceListScreen(),
        DeviceDetailScreen(device: garden),
      ],
      'monitor-new' => [
        const DeviceListScreen(),
        DeviceDetailScreen(device: fixtureDevice('dev-new')),
      ],
      'monitor-logs' => [
        const DeviceListScreen(),
        DeviceDetailScreen(device: garden, initialTab: DeviceTab.logs),
      ],
      'monitor-settings' => [
        const DeviceListScreen(),
        DeviceDetailScreen(device: garden, initialTab: DeviceTab.settings),
      ],
      'settings' => const [DeviceListScreen(), SettingsScreen()],
      'account' => const [
        DeviceListScreen(),
        SettingsScreen(),
        AccountScreen(),
      ],
      _ => const [GalleryScreen()],
    };
  }

  @override
  Widget build(BuildContext context) {
    return AppServices(
      api: _api.client,
      ble: _ble,
      child: ListenableBuilder(
        listenable: _actions,
        builder: (context, child) => AccountScope(
          account: _account,
          onSignOut: _signOut,
          actions: _actions,
          child: child!,
        ),
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModePreference,
          builder: (context, mode, _) => MaterialApp(
            title: 'Open AIQ gallery',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: _messenger,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: mode,
            onGenerateInitialRoutes: (_) => [
              for (final screen in _stack())
                MaterialPageRoute<void>(builder: (_) => screen),
            ],
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => const GalleryScreen()),
          ),
        ),
      ),
    );
  }
}

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final kitchen = fixtureReading('dev-kitchen')!.metrics;
    return Scaffold(
      appBar: const AiqAppBar(
        title: 'Gallery',
        subtitle: 'Shared screens with mock data',
      ),
      body: ListView(
        padding: pagePadding,
        children: [
          const SectionLabel('Monitor card'),
          MonitorCard(
            device: fixtureDevice('dev-garden'),
            reading: fixtureReading('dev-garden'),
          ),
          _gap,
          MonitorCard(device: fixtureDevice('dev-kitchen'), loading: true),
          _gap,
          MonitorCard(device: fixtureDevice('dev-new')),
          _gap,
          MonitorCard(
            device: fixtureDevice('dev-bushfire'),
            reading: fixtureReading('dev-bushfire'),
          ),
          _gap,
          const MonitorCardSkeleton(),
          const SizedBox(height: 32),
          const SectionLabel('Inside the monitor'),
          AqiTile(aqi: kitchen.aqi, caption: 'Averages over the last hour'),
          _gap,
          MetricGroups(
            groups: metricGroups(
              pm25: kitchen.pm25,
              pm10: kitchen.pm10,
              pm1: kitchen.pm1,
              temperature: kitchen.temperature,
              humidity: kitchen.humidity,
              heatIndex: kitchen.heatIndex,
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
          QuietNote(
            updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
            onRetry: () {},
          ),
          _gap,
          const Skeleton(child: SkeletonBlock(height: 96, radius: AiqRadii.xl)),
        ],
      ),
    );
  }
}

const _gap = SizedBox(height: 16);
