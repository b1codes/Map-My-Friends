import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/contact_log.dart';
import '../../utils/contact_recency.dart';

/// A compact month calendar for the Keep-in-Touch screen. Days with logged
/// touchpoints carry small channel-colored markers; tapping a day selects it so
/// the parent can reveal that day's interactions.
///
/// Uses [MaterialLocalizations] for weekday order and names, so it respects the
/// app's supported locales (en/es) rather than hard-coding a week layout.
class PulseCalendar extends StatelessWidget {
  final DateTime displayedMonth;
  final DateTime? selectedDay;

  /// Touchpoints bucketed by date-only key (see [dateKey]).
  final Map<DateTime, List<ContactLog>> logsByDay;

  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onSelectDay;

  /// Injectable clock for "today". Production leaves this null; tests pin it,
  /// because a calendar that reads the wall clock cannot be captured in a
  /// golden — the highlighted cell moves every day and the month every month.
  final DateTime? now;

  const PulseCalendar({
    super.key,
    required this.displayedMonth,
    required this.selectedDay,
    required this.logsByDay,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onSelectDay,
    this.now,
  });

  /// Normalizes a timestamp to a midnight date key for bucketing/lookup.
  static DateTime dateKey(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final today = DateUtils.dateOnly(now ?? clock.now());

    final year = displayedMonth.year;
    final month = displayedMonth.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final dayOffset = DateUtils.firstDayOffset(year, month, localizations);

    final monthLabel = DateFormat.yMMMM().format(displayedMonth);
    final isCurrentMonth = today.year == year && today.month == month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Month navigation header
        Row(
          children: [
            IconButton(
              onPressed: onPreviousMonth,
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous month',
            ),
            Expanded(
              child: Text(
                monthLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(
              // Don't let the user page into the future beyond this month.
              onPressed: isCurrentMonth ? null : onNextMonth,
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next month',
            ),
          ],
        ),
        const SizedBox(height: 8),
        _WeekdayHeader(localizations: localizations),
        const SizedBox(height: 4),
        _DayGrid(
          year: year,
          month: month,
          daysInMonth: daysInMonth,
          dayOffset: dayOffset,
          today: today,
          selectedDay: selectedDay,
          logsByDay: logsByDay,
          onSelectDay: onSelectDay,
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final MaterialLocalizations localizations;

  const _WeekdayHeader({required this.localizations});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstDayOfWeek = localizations.firstDayOfWeekIndex;
    final labels = <Widget>[];
    for (int i = 0; i < 7; i++) {
      final weekday = (firstDayOfWeek + i) % 7;
      labels.add(
        Expanded(
          child: Center(
            child: Text(
              localizations.narrowWeekdays[weekday],
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return Row(children: labels);
  }
}

class _DayGrid extends StatelessWidget {
  final int year;
  final int month;
  final int daysInMonth;
  final int dayOffset;
  final DateTime today;
  final DateTime? selectedDay;
  final Map<DateTime, List<ContactLog>> logsByDay;
  final ValueChanged<DateTime> onSelectDay;

  const _DayGrid({
    required this.year,
    required this.month,
    required this.daysInMonth,
    required this.dayOffset,
    required this.today,
    required this.selectedDay,
    required this.logsByDay,
    required this.onSelectDay,
  });

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];

    // Leading blanks for days before the 1st.
    for (int i = 0; i < dayOffset; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final isToday = DateUtils.isSameDay(date, today);
      final isSelected =
          selectedDay != null && DateUtils.isSameDay(date, selectedDay!);
      final isFuture = date.isAfter(today);
      final logs = logsByDay[PulseCalendar.dateKey(date)] ?? const [];

      cells.add(
        _DayCell(
          day: day,
          isToday: isToday,
          isSelected: isSelected,
          isFuture: isFuture,
          logs: logs,
          onTap: isFuture ? null : () => onSelectDay(date),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.82,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final bool isSelected;
  final bool isFuture;
  final List<ContactLog> logs;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isFuture,
    required this.logs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color textColor = colorScheme.onSurface;
    if (isFuture) {
      textColor = colorScheme.onSurface.withValues(alpha: 0.28);
    } else if (isSelected) {
      textColor = colorScheme.onPrimary;
    } else if (isToday) {
      textColor = colorScheme.primary;
    }

    BoxDecoration? decoration;
    if (isSelected) {
      decoration = BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
      );
    } else if (isToday) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.primary, width: 1.5),
      );
    }

    // Distinct channels present that day, in a stable order.
    final channels = [
      for (final c in ContactChannel.values)
        if (logs.any((l) => l.channel == c)) c,
    ];

    final semanticsLabel = logs.isEmpty
        ? '$day'
        : '$day, ${logs.length} contact${logs.length == 1 ? '' : 's'} logged';

    return Semantics(
      button: onTap != null,
      selected: isSelected,
      label: semanticsLabel,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: decoration,
              child: Text(
                '$day',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: (isToday || isSelected)
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final channel in channels.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : channel.markerColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
