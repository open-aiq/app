import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../ble/protocol.dart';
import '../../services.dart';
import '../../widgets/aiq_app_bar.dart';
import '../../widgets/monitor_illustration.dart';
import '../../widgets/sections.dart';
import '../../widgets/states.dart';
import 'connect_screen.dart';
import 'provisioning_controller.dart';

/// "Add monitor": pair over BLE, register if needed, send WiFi + location.
class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key});

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  ProvisioningController? _controller;
  bool _connecting = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null && _connecting) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
  }

  Future<void> _connect() async {
    final services = AppServices.of(context);
    final ok = await ConnectScreen.ensureConnected(context);
    if (!mounted) return;
    if (!ok || services.ble.session == null) {
      Navigator.of(context).pop();
      return;
    }
    final controller = ProvisioningController(
      session: services.ble.session!,
      api: services.api,
    );
    setState(() {
      _controller = controller;
      _connecting = false;
    });
    await controller.start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const AiqAppBar(title: '').preferredSize,
        child: controller == null
            ? const AiqAppBar(
                title: 'Add monitor',
                subtitle: 'Step 1 of 4 · Pair',
              )
            : ListenableBuilder(
                listenable: controller,
                builder: (context, _) => AiqAppBar(
                  title: 'Add monitor',
                  subtitle: _stepLabel(controller.step),
                ),
              ),
      ),
      body: SafeArea(
        child: controller == null
            ? const WaitingView(title: 'Waiting for a monitor…')
            : ListenableBuilder(
                listenable: controller,
                builder: (context, _) => _StepView(controller: controller),
              ),
      ),
    );
  }
}

/// Where you are in setup, for the top bar: pair, name, WiFi, location.
String _stepLabel(ProvisioningStep step) => switch (step) {
  ProvisioningStep.inspecting ||
  ProvisioningStep.register => 'Step 2 of 4 · Name',
  ProvisioningStep.wifi => 'Step 3 of 4 · WiFi',
  ProvisioningStep.location => 'Step 4 of 4 · Location',
  ProvisioningStep.saving || ProvisioningStep.verifying => 'Finishing up',
  ProvisioningStep.done => 'All set',
};

class _StepView extends StatelessWidget {
  const _StepView({required this.controller});

  final ProvisioningController controller;

  @override
  Widget build(BuildContext context) {
    final body = switch (controller.step) {
      ProvisioningStep.inspecting =>
        controller.error == null
            ? const WaitingView(title: 'Getting to know your monitor…')
            : ErrorView(message: controller.error!, onRetry: controller.start),
      ProvisioningStep.register => _RegisterStep(controller: controller),
      ProvisioningStep.wifi => _WifiStep(controller: controller),
      ProvisioningStep.location => _LocationStep(controller: controller),
      ProvisioningStep.saving => const WaitingView(
        title: 'Saving and joining WiFi…',
        message: 'This usually takes a few seconds.',
      ),
      ProvisioningStep.verifying => _VerifyStep(controller: controller),
      ProvisioningStep.done => _DoneStep(controller: controller),
    };
    return SoftSwitcher(
      child: KeyedSubtree(key: ValueKey(controller.step), child: body),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: pagePadding,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

/// Space above a step's main button.
const _actionGap = SizedBox(height: 20);

class _RegisterStep extends StatefulWidget {
  const _RegisterStep({required this.controller});

  final ProvisioningController controller;

  @override
  State<_RegisterStep> createState() => _RegisterStepState();
}

class _RegisterStepState extends State<_RegisterStep> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _outdoor = false;
  bool _public = false;
  bool _locationPublic = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Form(
      key: _form,
      child: _StepScaffold(
        title: 'Name your monitor',
        subtitle: controller.registeredElsewhere
            ? "This monitor was set up on another account (${controller.info?.deviceId}). Adding it here gives it fresh credentials for yours."
            : "We'll add it to your account and give it its own credentials.",
        children: [
          SectionCard(
            children: [
              SectionField(
                child: TextFormField(
                  controller: _name,
                  autofocus: true,
                  maxLength: 100,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Living room',
                    counterText: '',
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Enter a name'
                      : null,
                ),
              ),
              SectionSwitch(
                icon: const Icon(Icons.park_outlined),
                title: 'Installed outdoors',
                value: _outdoor,
                onChanged: (value) => setState(() => _outdoor = value),
              ),
              SectionSwitch(
                icon: const Icon(Icons.public),
                title: 'Share data publicly',
                subtitle: 'Readings appear on the public map',
                value: _public,
                onChanged: (value) => setState(() {
                  _public = value;
                  if (!value) _locationPublic = false;
                }),
              ),
              SectionSwitch(
                icon: const Icon(Icons.place_outlined),
                title: 'Share exact location',
                subtitle: _public
                    ? 'Shown on the public map'
                    : 'Turn on public sharing first',
                value: _locationPublic,
                onChanged: _public
                    ? (value) => setState(() => _locationPublic = value)
                    : null,
              ),
            ],
          ),
          InlineError(controller.error),
          _actionGap,
          FilledButton(
            onPressed: controller.busy
                ? null
                : () {
                    if (!_form.currentState!.validate()) return;
                    controller.register(
                      name: _name.text.trim(),
                      isOutdoor: _outdoor,
                      isPublic: _public,
                      isLocationPublic: _locationPublic,
                    );
                  },
            child: controller.busy
                ? const _ButtonProgress()
                : const Text('Add to my account'),
          ),
        ],
      ),
    );
  }
}

class _WifiStep extends StatefulWidget {
  const _WifiStep({required this.controller});

  final ProvisioningController controller;

  @override
  State<_WifiStep> createState() => _WifiStepState();
}

class _WifiStepState extends State<_WifiStep> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _ssid.text = widget.controller.info?.ssid ?? '';
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.controller.scanWifi(),
    );
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final scanning = controller.busy && controller.networks.isEmpty;
    return _StepScaffold(
      title: 'Choose WiFi',
      subtitle:
          'Pick the 2.4 GHz network ${controller.device?.name ?? 'the monitor'} should use.',
      children: [
        SectionLabel(
          'Networks nearby',
          trailing: IconButton(
            tooltip: 'Scan again',
            visualDensity: VisualDensity.compact,
            onPressed: controller.busy ? null : controller.scanWifi,
            icon: const Icon(Icons.refresh),
          ),
        ),
        SoftSwitcher(
          child: scanning
              ? Skeleton(
                  key: const ValueKey('scanning'),
                  label: 'Looking for networks',
                  child: SectionCard(
                    children: [
                      for (var i = 0; i < 3; i++)
                        const SkeletonShape(
                          child: SectionRow(
                            icon: Icon(Icons.wifi),
                            title: 'Home network',
                          ),
                        ),
                    ],
                  ),
                )
              : controller.networks.isEmpty
              ? Padding(
                  key: const ValueKey('none'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    "No networks found yet. You can type the name below.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : SectionCard(
                  key: const ValueKey('networks'),
                  children: [
                    for (final network in controller.networks)
                      Semantics(
                        selected: network.ssid == _ssid.text,
                        child: SectionRow(
                          icon: Icon(
                            network.secured ? Icons.wifi_password : Icons.wifi,
                            semanticLabel:
                                '${network.bars} of 4 bars, ${network.secured ? 'secured' : 'open'}',
                          ),
                          title: network.ssid,
                          onTap: () =>
                              setState(() => _ssid.text = network.ssid),
                          trailing: network.ssid == _ssid.text
                              ? Icon(
                                  Icons.check_circle,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                  semanticLabel: 'Selected',
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
        ),
        const SectionLabel('Network'),
        SectionCard(
          children: [
            SectionField(
              child: TextField(
                controller: _ssid,
                decoration: const InputDecoration(
                  labelText: 'Network name (SSID)',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SectionField(
              child: TextField(
                controller: _password,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ),
          ],
        ),
        InlineError(controller.error),
        _actionGap,
        FilledButton(
          onPressed: controller.busy || _ssid.text.trim().isEmpty
              ? null
              : () => controller.submitWifi(_ssid.text.trim(), _password.text),
          child: const Text('Next'),
        ),
      ],
    );
  }
}

class _LocationStep extends StatefulWidget {
  const _LocationStep({required this.controller});

  final ProvisioningController controller;

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  bool _locating = false;
  String? _locationError;

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final position = await currentPosition();
      _lat.text = position.latitude.toStringAsFixed(6);
      _lon.text = position.longitude.toStringAsFixed(6);
    } catch (e) {
      _locationError = e.toString();
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final lat = double.tryParse(_lat.text);
    final lon = double.tryParse(_lon.text);
    final valid =
        lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180;
    return _StepScaffold(
      title: 'Where is it?',
      subtitle:
          'Each reading carries this location. It only appears publicly if you share the exact location.',
      children: [
        SectionCard(
          children: [
            SectionRow(
              icon: const Icon(Icons.my_location),
              title: _locating ? 'Finding you…' : "Use this phone's location",
              onTap: _locating ? null : _useCurrentLocation,
              enabled: !_locating,
            ),
            SectionField(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Latitude'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lon,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Longitude'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        InlineError(_locationError),
        InlineError(controller.error),
        _actionGap,
        FilledButton(
          onPressed: controller.busy || !valid
              ? null
              : () => controller.submitLocation(lat: lat, lon: lon),
          child: const Text('Save to monitor'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: controller.busy ? null : () => controller.submitLocation(),
          child: const Text('Skip for now'),
        ),
      ],
    );
  }
}

class _VerifyStep extends StatelessWidget {
  const _VerifyStep({required this.controller});

  final ProvisioningController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.verifyTimedOut) {
      return const WaitingView(
        title: 'Waiting for the first reading…',
        message: "WiFi's connected. This usually takes under a minute.",
      );
    }
    return _StepScaffold(
      title: 'Still waiting for the monitor',
      subtitle:
          'The monitor joined WiFi${controller.ip == null ? '' : ' (${controller.ip})'} but no reading has arrived yet. '
          'Check that the network has internet access. If the monitor was set up before, its key may be out of date.',
      children: [
        InlineError(controller.error),
        _actionGap,
        FilledButton(
          onPressed: controller.busy ? null : controller.retryVerify,
          child: const Text('Keep waiting'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: controller.busy
              ? null
              : () async {
                  await controller.rotateAndResendKey();
                  await controller.retryVerify();
                },
          child: const Text('Send a new device key'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Finish anyway'),
        ),
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.controller});

  final ProvisioningController controller;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      illustration: const MonitorIllustration(),
      title: '${controller.device?.name ?? 'Your monitor'} is online',
      message:
          "You'll see a new reading every 10 minutes, and live ones whenever you're nearby over Bluetooth.",
      action: FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Done'),
      ),
    );
  }
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 18,
    width: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

/// The phone's current position, asking for location permission if needed.
Future<Position> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw BleProtocolException(
      'Turn on location services, or enter the coordinates.',
    );
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw BleProtocolException(
      'Location permission was denied. Enter the coordinates instead.',
    );
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    ),
  );
}
