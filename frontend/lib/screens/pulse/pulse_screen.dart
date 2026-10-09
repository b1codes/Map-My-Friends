import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../bloc/pulse/pulse_bloc.dart';
import '../../models/contact_log.dart';
import '../../models/person.dart';
import '../../utils/contact_recency.dart';
import '../../components/pulse/pulse_calendar.dart';
import '../../components/pulse/contact_roster_tile.dart';
import '../../components/pulse/log_contact_sheet.dart';
import '../../components/shared/glass_empty_state.dart';
import '../../utils/window_size.dart';
import '../../utils/app_theme.dart';
import '../../components/shared/glass_container.dart';
import '../../components/shared/chromatic_pulse.dart';
import '../../components/shared/glass_surfaces.dart';
import '../../components/shared/glass_header.dart';

/// Keep-in-Touch ("Pulse") screen: a relationship calendar plus a roster that
/// color-codes each person by how overdue a touchpoint is, along the app's
/// thermal spectrum. Loads via [PulseBloc].
class PulseScreen extends StatefulWidget {
  /// Injectable clock. Production leaves this null; tests pin it so the
  /// calendar's "today" and every recency band stop moving under the golden.
  final DateTime? now;

  const PulseScreen({super.key, this.now});

  @override
  State<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends State<PulseScreen> {
  late DateTime _displayedMonth;
  DateTime? _selectedDay;
  int _lastNonce = 0;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final now = _now;
    _displayedMonth = DateTime(now.year, now.month);
    context.read<PulseBloc>().add(LoadPulse());
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      );
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      );
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay =
          (_selectedDay != null && DateUtils.isSameDay(_selectedDay!, day))
          ? null
          : day;
    });
  }

  Map<DateTime, List<ContactLog>> _bucketLogs(List<ContactLog> logs) {
    final map = <DateTime, List<ContactLog>>{};
    for (final log in logs) {
      final key = PulseCalendar.dateKey(log.contactedAt);
      map.putIfAbsent(key, () => []).add(log);
    }
    return map;
  }

  void _openLogSheet(Person person, ContactRecency recency) {
    final bloc = context.read<PulseBloc>();
    LogContactSheet.show(
      context,
      person: person,
      recency: recency,
      onLog: (channel, date, note) {
        bloc.add(
          LogContact(
            personId: person.id,
            channel: channel,
            contactedAt: date,
            note: note,
          ),
        );
        if (!mounted) return;
        GlassToast.success(
          context,
          'Logged ${channel.label.toLowerCase()} with ${person.firstName}',
        );
      },
      onSetCadence: (days) {
        bloc.add(SetCadence(personId: person.id, cadenceDays: days));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: <Widget>[
          const GlassHeader(title: 'Keep in Touch', showBack: false),
          Expanded(
            child: BlocConsumer<PulseBloc, PulseState>(
              listenWhen: (prev, curr) =>
                  curr is PulseLoaded && curr.actionNonce != _lastNonce,
              listener: (context, state) {
                if (state is PulseLoaded) {
                  _lastNonce = state.actionNonce;
                  if (state.actionError != null) {
                    GlassToast.failure(context, state.actionError!);
                  }
                }
              },
              builder: (context, state) {
                if (state is PulseLoading || state is PulseInitial) {
                  return const PulseIndicator();
                }
                if (state is PulseError) {
                  return _ErrorView(
                    message: state.message,
                    onRetry: () => context.read<PulseBloc>().add(LoadPulse()),
                  );
                }
                if (state is PulseLoaded) {
                  if (state.people.isEmpty) {
                    return const _EmptyPeopleView();
                  }
                  return _buildLoaded(context, state);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, PulseLoaded state) {
    final now = _now;

    // Pair each person with recency, sorted most-overdue first.
    final entries = [
      for (final p in state.people)
        (person: p, recency: ContactRecency.forPerson(p, now: now)),
    ]..sort((a, b) => b.recency.overdueRatio.compareTo(a.recency.overdueRatio));

    final attentionCount = entries
        .where((e) => e.recency.isAttentionNeeded)
        .length;
    final logsByDay = _bucketLogs(state.logs);
    final selectedLogs = _selectedDay == null
        ? const <ContactLog>[]
        : (logsByDay[PulseCalendar.dateKey(_selectedDay!)] ?? const []);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = MapWindow(
          Size(constraints.maxWidth, constraints.maxHeight),
        ).isWide;
        final horizontalPadding = isDesktop ? 24.0 : 0.0;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding + (isDesktop ? 96 : 0),
                    12,
                    horizontalPadding,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SummaryHeader(
                          attentionCount: attentionCount,
                          totalPeople: entries.length,
                          hasLogs: state.logs.isNotEmpty,
                        ),
                        const SizedBox(height: 16),
                        _CalendarCard(
                          child: PulseCalendar(
                            now: widget.now,
                            displayedMonth: _displayedMonth,
                            selectedDay: _selectedDay,
                            logsByDay: logsByDay,
                            onPreviousMonth: _previousMonth,
                            onNextMonth: _nextMonth,
                            onSelectDay: _selectDay,
                          ),
                        ),
                        if (_selectedDay != null) ...[
                          const SizedBox(height: 12),
                          _SelectedDayDetail(
                            day: _selectedDay!,
                            logs: selectedLogs,
                            people: state.people,
                          ),
                        ],
                        const SizedBox(height: 20),
                        _RosterHeader(count: entries.length),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? horizontalPadding + 80 : 0,
                  ),
                  sliver: SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return ContactRosterTile(
                        person: entry.person,
                        recency: entry.recency,
                        onTap: () => _openLogSheet(entry.person, entry.recency),
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final int attentionCount;
  final int totalPeople;
  final bool hasLogs;

  const _SummaryHeader({
    required this.attentionCount,
    required this.totalPeople,
    required this.hasLogs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool caughtUp = attentionCount == 0;
    // The same spectrum the roster reads on, so "caught up" and a fresh
    // connection are the same colour rather than two teals that nearly match.
    final MapSignal signal = caughtUp ? MapPalette.vital : MapPalette.overdue;
    final Color accent = signal.ink(theme.brightness);

    final String headline;
    final String sub;
    if (!hasLogs) {
      headline = 'Start your first touchpoint';
      sub = 'Tap anyone below to log a call, video, or message.';
    } else if (caughtUp) {
      headline = "You're all caught up";
      sub = 'Every connection is within its rhythm. Nicely tended.';
    } else {
      headline = attentionCount == 1
          ? '1 connection needs a hello'
          : '$attentionCount connections need a hello';
      sub = 'Warmest names have waited longest since you last talked.';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            caughtUp || !hasLogs
                ? Icons.favorite_outline
                : Icons.local_fire_department,
            color: accent,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(headline, style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                sub,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalendarCard extends StatelessWidget {
  final Widget child;
  const _CalendarCard({required this.child});

  @override
  Widget build(BuildContext context) {
    // A month is this surface's panel, not a row inside one, so it earns a
    // real backdrop sample rather than an inlay.
    return GlassContainer(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, MapSpacing.sm),
      borderRadius: MapGlass.radiusMd,
      child: child,
    );
  }
}

class _SelectedDayDetail extends StatelessWidget {
  final DateTime day;
  final List<ContactLog> logs;
  final List<Person> people;

  const _SelectedDayDetail({
    required this.day,
    required this.logs,
    required this.people,
  });

  Person? _personFor(String id) {
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat.yMMMMEEEEd().format(day);

    return GlassContainer(
      width: double.infinity,
      padding: const EdgeInsets.all(MapSpacing.sm),
      borderRadius: MapGlass.radiusMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (logs.isEmpty)
            Text(
              'No contact logged this day.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final log in logs)
                  _DayLogChip(
                    channel: log.channel,
                    name: () {
                      final p = _personFor(log.personId);
                      return p == null
                          ? 'Someone'
                          : '${p.firstName} ${p.lastName}'.trim();
                    }(),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayLogChip extends StatelessWidget {
  final ContactChannel channel;
  final String name;

  const _DayLogChip({required this.channel, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = channel.markerColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MapGlass.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(channel.icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            name,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterHeader extends StatelessWidget {
  final int count;
  const _RosterHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'Your circle',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'by who needs you most',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              "Couldn't load your circle",
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPeopleView extends StatelessWidget {
  const _EmptyPeopleView();

  @override
  Widget build(BuildContext context) {
    return const GlassEmptyState(
      icon: Icons.favorite_outline,
      title: 'No one to keep up with yet',
      message:
          'Add friends and family on the People tab, then come back here to '
          'track when you last called, video chatted, or messaged.',
    );
  }
}
