import 'package:flutter/material.dart';

import 'monitor_illustration.dart';
import 'soft_card.dart';

/// The page gutter shared by every screen.
const pagePadding = EdgeInsets.fromLTRB(16, 12, 16, 32);

/// A small heading above a group of rows, with an optional trailing widget
/// such as a status chip.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.color});

  final String text;
  final Widget? trailing;

  /// Overrides the accent, e.g. the error colour for a danger zone.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color ?? theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A rounded group of rows on a raised card, divided by soft inset lines.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final divider = Divider(
      height: 1,
      indent: 64,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) divider,
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A soft tinted circle behind an icon, used at the start of rows.
class IconBubble extends StatelessWidget {
  const IconBubble({
    super.key,
    required this.icon,
    this.background,
    this.foreground,
    this.size = 36,
  });

  final Widget icon;
  final Color? background;
  final Color? foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? scheme.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: IconTheme.merge(
        data: IconThemeData(
          size: size * 0.55,
          color: foreground ?? scheme.onSecondaryContainer,
        ),
        child: icon,
      ),
    );
  }
}

/// One row inside a [SectionCard]: an icon bubble, a title with an optional
/// subtitle, and a trailing widget (a chevron when tappable).
class SectionRow extends StatelessWidget {
  const SectionRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleStyle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final Widget icon;
  final String title;
  final String? subtitle;

  /// Merged into the subtitle's style, e.g. a monospace font for an ID.
  final TextStyle? subtitleStyle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  /// Dims the row and ignores taps, e.g. while another action runs.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              IconBubble(
                icon: icon,
                background: destructive ? scheme.errorContainer : null,
                foreground: destructive ? scheme.onErrorContainer : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: destructive ? scheme.error : null,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)
                            .merge(subtitleStyle),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (onTap != null)
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [SectionRow] with a switch.
class SectionSwitch extends StatelessWidget {
  const SectionSwitch({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: SectionRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        enabled: onChanged != null,
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// Padding for form fields placed inside a [SectionCard].
class SectionField extends StatelessWidget {
  const SectionField({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), child: child);
}

/// A calm waiting state: the floating monitor and a short message, used
/// while something slow happens (pairing, saving, waiting for a reading).
class WaitingView extends StatelessWidget {
  const WaitingView({super.key, required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MonitorIllustration(),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
