import 'package:flutter/material.dart';

import '../api/models.dart';

/// Small badge for a device's firmware-update state; hidden when up to date.
class OtaBadge extends StatelessWidget {
  const OtaBadge({super.key, required this.summary, this.onTap});

  final OtaSummary? summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ota = summary;
    if (ota == null || !ota.needsAttention) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground, icon) = switch (ota.status) {
      'update_available' => (
        'Update available',
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.system_update,
      ),
      'approved' => (
        'Update queued',
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.schedule,
      ),
      'downloading' || 'installing' => (
        'Updating ${ota.progress ?? 0}%',
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.downloading,
      ),
      'failed' => (
        'Update failed',
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      _ => (
        'Update',
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        Icons.info_outline,
      ),
    };
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: ota.version == null ? label : '$label, version ${ota.version}',
      excludeSemantics: true,
      child: onTap == null
          ? badge
          : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: badge,
            ),
    );
  }
}
