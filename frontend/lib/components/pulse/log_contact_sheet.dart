import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/contact_log.dart';
import '../../models/person.dart';
import '../../utils/contact_recency.dart';
import '../shared/thermal_response.dart';
import '../../utils/app_theme.dart';
import '../shared/glass_surfaces.dart';

/// Bottom sheet for recording a touchpoint with [person]. Handles channel,
/// date (with quick Today/Yesterday chips), an optional note, optional
/// quick-launch of the real call/message, and a cadence stepper.
///
/// Decoupled from the bloc via callbacks so it can be tested and reused; the
/// screen wires [onLog]/[onSetCadence] to [PulseBloc].
class LogContactSheet extends StatefulWidget {
  final Person person;
  final ContactRecency recency;
  final void Function(ContactChannel channel, DateTime date, String? note)
  onLog;
  final void Function(int cadenceDays) onSetCadence;

  const LogContactSheet({
    super.key,
    required this.person,
    required this.recency,
    required this.onLog,
    required this.onSetCadence,
  });

  static Future<void> show(
    BuildContext context, {
    required Person person,
    required ContactRecency recency,
    required void Function(ContactChannel channel, DateTime date, String? note)
    onLog,
    required void Function(int cadenceDays) onSetCadence,
  }) {
    return GlassSheet.show<void>(
      context,
      builder: (_) => LogContactSheet(
        person: person,
        recency: recency,
        onLog: onLog,
        onSetCadence: onSetCadence,
      ),
    );
  }

  @override
  State<LogContactSheet> createState() => _LogContactSheetState();
}

class _LogContactSheetState extends State<LogContactSheet> {
  ContactChannel _channel = ContactChannel.call;
  late DateTime _date;
  final TextEditingController _noteController = TextEditingController();
  late int _cadence;
  bool _cadenceExpanded = false;

  @override
  void initState() {
    super.initState();
    _date = DateUtils.dateOnly(DateTime.now());
    _cadence =
        widget.person.contactCadenceDays ??
        ContactRecency.defaultCadenceForTag(widget.person.relationshipTag);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canQuickLaunch {
    final phone = widget.person.phoneNumber;
    if (phone == null || phone.isEmpty) return false;
    return _channel == ContactChannel.call ||
        _channel == ContactChannel.message;
  }

  String get _dateLabel {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    if (DateUtils.isSameDay(_date, today)) return 'Today';
    if (DateUtils.isSameDay(_date, yesterday)) return 'Yesterday';
    return DateFormat.yMMMMd().format(_date);
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      helpText: 'When did you connect?',
    );
    if (picked != null) setState(() => _date = DateUtils.dateOnly(picked));
  }

  void _submit({bool launch = false}) async {
    final note = _noteController.text.trim();
    if (launch) {
      await _launchChannel();
    }
    widget.onLog(_channel, _date, note.isEmpty ? null : note);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _launchChannel() async {
    final phone = widget.person.phoneNumber;
    if (phone == null || phone.isEmpty) return;
    final scheme = _channel == ContactChannel.message ? 'sms' : 'tel';
    final uri = Uri(scheme: scheme, path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      // Quietly fall through to logging even if no dialer/SMS app is present.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Log contact', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'with ${widget.person.firstName} ${widget.person.lastName}'
                  .trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            _SectionLabel('How did you connect?'),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final channel in ContactChannel.values) ...[
                  Expanded(
                    child: _ChannelOption(
                      channel: channel,
                      selected: _channel == channel,
                      onTap: () => setState(() => _channel = channel),
                    ),
                  ),
                  if (channel != ContactChannel.values.last)
                    const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 20),

            _SectionLabel('When?'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DateChip(
                  label: 'Today',
                  selected: _dateLabel == 'Today',
                  onTap: () => setState(
                    () => _date = DateUtils.dateOnly(DateTime.now()),
                  ),
                ),
                _DateChip(
                  label: 'Yesterday',
                  selected: _dateLabel == 'Yesterday',
                  onTap: () => setState(
                    () => _date = DateUtils.dateOnly(
                      DateTime.now().subtract(const Duration(days: 1)),
                    ),
                  ),
                ),
                _DateChip(
                  label: _dateLabel != 'Today' && _dateLabel != 'Yesterday'
                      ? _dateLabel
                      : 'Pick date…',
                  selected: _dateLabel != 'Today' && _dateLabel != 'Yesterday',
                  icon: Icons.calendar_today,
                  onTap: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _noteController,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 280,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'What did you talk about?',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),

            _CadenceEditor(
              expanded: _cadenceExpanded,
              cadence: _cadence,
              tag: widget.person.relationshipTag,
              onToggle: () =>
                  setState(() => _cadenceExpanded = !_cadenceExpanded),
              onChanged: (value) {
                setState(() => _cadence = value);
                widget.onSetCadence(value);
              },
            ),
            const SizedBox(height: 20),

            if (_canQuickLaunch) ...[
              _PrimaryButton(
                label: _channel == ContactChannel.message
                    ? 'Message & log'
                    : 'Call & log',
                icon: _channel.icon,
                onPressed: () => _submit(launch: true),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => _submit(),
                child: const Text('Just log it'),
              ),
            ] else
              _PrimaryButton(
                label: 'Log ${_channel.label.toLowerCase()}',
                icon: Icons.check,
                onPressed: () => _submit(),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ChannelOption extends StatelessWidget {
  final ContactChannel channel;
  final bool selected;
  final VoidCallback onTap;

  const _ChannelOption({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = channel.markerColor;
    final borderColor = selected
        ? accent
        : MapGlass.inlayEdge(theme.brightness);
    final fg = selected ? accent : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: '${channel.label}${selected ? ', selected' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MapGlass.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(MapGlass.radiusMd),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
          ),
          child: Column(
            children: [
              Icon(channel.icon, color: fg, size: 24),
              const SizedBox(height: 6),
              Text(
                channel.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? theme.colorScheme.onSurface : fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  const _DateChip({
    required this.label,
    required this.selected,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MapGlass.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MapGlass.radiusPill),
          border: Border.all(
            color: selected ? primary : MapGlass.inlayEdge(theme.brightness),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? primary : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? primary : theme.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CadenceEditor extends StatelessWidget {
  final bool expanded;
  final int cadence;
  final String tag;
  final VoidCallback onToggle;
  final ValueChanged<int> onChanged;

  const _CadenceEditor({
    required this.expanded,
    required this.cadence,
    required this.tag,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MapGlass.radiusMd),
        border: Border.all(color: MapGlass.inlayEdge(theme.brightness)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(MapGlass.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Stay in touch every $cadence days',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: cadence > 1
                        ? () => onChanged((cadence - 7).clamp(1, 365))
                        : null,
                    icon: const Icon(Icons.remove),
                    tooltip: 'Less often',
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '$cadence days',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: cadence < 365
                        ? () => onChanged((cadence + 7).clamp(1, 365))
                        : null,
                    icon: const Icon(Icons.add),
                    tooltip: 'More often',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ThermalResponse(
      onTap: onPressed,
      borderRadius: 14,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MapGlass.radiusMd),
          ),
        ),
      ),
    );
  }
}
