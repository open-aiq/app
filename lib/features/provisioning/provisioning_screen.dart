import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../ble/protocol.dart';
import '../../services.dart';
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
      appBar: AppBar(title: const Text('Add monitor')),
      body: SafeArea(
        child: controller == null
            ? const LoadingView(message: 'Waiting for a monitor…')
            : ListenableBuilder(
                listenable: controller,
                builder: (context, _) => _StepView(controller: controller),
              ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({required this.controller});

  final ProvisioningController controller;

  @override
  Widget build(BuildContext context) {
    final body = switch (controller.step) {
      ProvisioningStep.inspecting =>
        controller.error == null
            ? const LoadingView(message: 'Reading monitor details…')
            : ErrorView(message: controller.error!, onRetry: controller.start),
      ProvisioningStep.register => _RegisterStep(controller: controller),
      ProvisioningStep.wifi => _WifiStep(controller: controller),
      ProvisioningStep.location => _LocationStep(controller: controller),
      ProvisioningStep.saving => const LoadingView(
        message: 'Saving settings and joining WiFi…',
      ),
      ProvisioningStep.verifying => _VerifyStep(controller: controller),
      ProvisioningStep.done => _DoneStep(controller: controller),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
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
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        if (subtitle != null) ...[const SizedBox(height: 8), Text(subtitle!)],
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

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
        title: 'Register this monitor',
        subtitle: controller.registeredElsewhere
            ? 'This monitor is linked to a device id (${controller.info?.deviceId}) that is not in your account. '
                  'Registering gives it new credentials for your account.'
            : 'The monitor is not registered yet. It will be added to your account and receive its own credentials.',
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            maxLength: 100,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Living room',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Enter a name' : null,
          ),
          SwitchListTile(
            title: const Text('Installed outdoors'),
            value: _outdoor,
            onChanged: (value) => setState(() => _outdoor = value),
          ),
          SwitchListTile(
            title: const Text('Share data publicly'),
            subtitle: const Text('Readings appear on the public map'),
            value: _public,
            onChanged: (value) => setState(() {
              _public = value;
              if (!value) _locationPublic = false;
            }),
          ),
          SwitchListTile(
            title: const Text('Share exact location'),
            subtitle: const Text('Requires public sharing'),
            value: _locationPublic,
            onChanged: _public
                ? (value) => setState(() => _locationPublic = value)
                : null,
          ),
          InlineError(controller.error),
          const SizedBox(height: 8),
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
                : const Text('Register'),
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
    return _StepScaffold(
      title: 'Connect to WiFi',
      subtitle: controller.device == null
          ? null
          : 'Monitor "${controller.device!.name}". Choose a 2.4 GHz network.',
      children: [
        Row(
          children: [
            Text(
              'Networks nearby',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Scan again',
              onPressed: controller.busy ? null : controller.scanWifi,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (controller.busy && controller.networks.isEmpty)
          const LinearProgressIndicator(),
        for (final network in controller.networks)
          ListTile(
            selected: network.ssid == _ssid.text,
            onTap: () => setState(() => _ssid.text = network.ssid),
            title: Text(network.ssid),
            leading: Icon(
              network.secured ? Icons.wifi_password : Icons.wifi,
              semanticLabel:
                  '${network.bars} of 4 bars, ${network.secured ? 'secured' : 'open'}',
            ),
            trailing: network.ssid == _ssid.text
                ? const Icon(Icons.check, semanticLabel: 'Selected')
                : null,
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _ssid,
          decoration: const InputDecoration(
            labelText: 'Network name (SSID)',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        InlineError(controller.error),
        const SizedBox(height: 8),
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
      title: 'Monitor location',
      subtitle:
          'The location is attached to each reading. It is only shown publicly if you share the exact location.',
      children: [
        OutlinedButton.icon(
          onPressed: _locating ? null : _useCurrentLocation,
          icon: const Icon(Icons.my_location),
          label: Text(_locating ? 'Locating…' : 'Use this phone\'s location'),
        ),
        InlineError(_locationError),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  border: OutlineInputBorder(),
                ),
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
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        InlineError(controller.error),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: controller.busy || !valid
              ? null
              : () => controller.submitLocation(lat: lat, lon: lon),
          child: const Text('Save to monitor'),
        ),
        TextButton(
          onPressed: controller.busy ? null : () => controller.submitLocation(),
          child: const Text('Skip location'),
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
      return const LoadingView(
        message:
            'WiFi connected. Waiting for the first reading to reach Open AIQ…\nThis usually takes under a minute.',
      );
    }
    return _StepScaffold(
      title: 'Still waiting for the monitor',
      subtitle:
          'The monitor joined WiFi${controller.ip == null ? '' : ' (${controller.ip})'} but no reading has arrived yet. '
          'Check that the network has internet access. If the monitor was set up before, its key may be out of date.',
      children: [
        InlineError(controller.error),
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
      icon: Icons.check_circle,
      title: '${controller.device?.name ?? 'Monitor'} is online',
      message:
          'Readings are uploaded every 10 minutes. Live readings are available while connected over Bluetooth.',
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
