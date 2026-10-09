import 'package:flutter/material.dart';
import '../../models/contact_log.dart';
import '../../models/person.dart';
import '../../utils/contact_recency.dart';
import '../shared/thermal_response.dart';
import '../../utils/app_theme.dart';

/// A single row in the Keep-in-Touch roster: avatar with a thermal status orb,
/// the person's name in a contrast-safe recency ink, a status chip, the last
/// touchpoint, and a cadence progress bar. Pressing the row ignites the
/// signature thermal glow and opens the log sheet.
class ContactRosterTile extends StatelessWidget {
  final Person person;
  final ContactRecency recency;
  final VoidCallback onTap;

  const ContactRosterTile({
    super.key,
    required this.person,
    required this.recency,
    required this.onTap,
  });

  String get _initials {
    final f = person.firstName.isNotEmpty ? person.firstName[0] : '';
    final l = person.lastName.isNotEmpty ? person.lastName[0] : '';
    final joined = '$f$l'.trim();
    return joined.isEmpty ? '?' : joined.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nameColor = recency.inkColor(context);
    final lastChannel = ContactChannel.fromApi(person.lastContactChannel);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ThermalResponse(
        onTap: onTap,
        borderRadius: MapGlass.radiusMd,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MapGlass.inlayFill(theme.brightness),
            borderRadius: BorderRadius.circular(MapGlass.radiusMd),
            border: Border.all(color: MapGlass.inlayEdge(theme.brightness)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(
                initials: _initials,
                imageUrl: person.profileImageUrl,
                orbColor: recency.vividColor,
                glow: recency.isAttentionNeeded,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${person.firstName} ${person.lastName}'.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: nameColor,
                              fontWeight: recency.isAttentionNeeded
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 132),
                          child: _StatusChip(recency: recency),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (lastChannel != null) ...[
                          Icon(
                            lastChannel.icon,
                            size: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            recency.lastContactPhrase,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _CadenceBar(
                      progress: recency.progress,
                      color: recency.vividColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _LogAffordance(color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final String? imageUrl;
  final Color orbColor;
  final bool glow;

  const _Avatar({
    required this.initials,
    required this.imageUrl,
    required this.orbColor,
    required this.glow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: MapGlass.inlayFillStrong(theme.brightness),
            backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
            child: imageUrl == null
                ? Text(
                    initials,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: orbColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: MapGlass.inlayFill(theme.brightness),
                  width: 2.5,
                ),
                boxShadow: glow
                    ? [
                        BoxShadow(
                          color: orbColor.withValues(alpha: 0.6),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ContactRecency recency;

  const _StatusChip({required this.recency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vivid = recency.vividColor;
    final ink = recency.inkColor(context);
    final days = recency.daysSince;
    final label = days != null ? '${recency.label} · ${days}d' : recency.label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: vivid.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(MapGlass.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(recency.icon, size: 12, color: ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CadenceBar extends StatelessWidget {
  final double progress;
  final Color color;

  const _CadenceBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.08);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(
        children: [
          Container(height: 5, color: track),
          FractionallySizedBox(
            widthFactor: progress.clamp(0.02, 1.0),
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.55), color],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogAffordance extends StatelessWidget {
  final Color color;

  const _LogAffordance({required this.color});

  @override
  Widget build(BuildContext context) {
    // Purely visual affordance — the surrounding ThermalResponse owns the tap.
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.add_comment_outlined, size: 20, color: color),
    );
  }
}
