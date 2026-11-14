import 'package:bloc/bloc.dart';
import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import '../../models/person.dart';
import '../../models/contact_log.dart';
import '../../services/api_service.dart';

part 'pulse_event.dart';
part 'pulse_state.dart';

/// Drives the Keep-in-Touch (Pulse) screen: loads people alongside their
/// contact history, and records new touchpoints with optimistic updates so the
/// roster re-colors instantly instead of waiting on a round-trip.
class PulseBloc extends Bloc<PulseEvent, PulseState> {
  final ApiService _apiService;

  PulseBloc({required ApiService apiService})
    : _apiService = apiService,
      super(PulseInitial()) {
    on<LoadPulse>(_onLoadPulse);
    on<LogContact>(_onLogContact);
    on<SetCadence>(_onSetCadence);
  }

  Future<void> _onLoadPulse(LoadPulse event, Emitter<PulseState> emit) async {
    emit(PulseLoading());
    try {
      // People carry a server-computed recency summary; logs feed the calendar.
      final results = await Future.wait([
        _apiService.getPeople(),
        _apiService.getContactLogs(),
      ]);
      final people = results[0] as List<Person>;
      final logs = results[1] as List<ContactLog>;
      emit(PulseLoaded(people: people, logs: _sorted(logs)));
    } catch (e) {
      emit(PulseError(e.toString()));
    }
  }

  Future<void> _onLogContact(LogContact event, Emitter<PulseState> emit) async {
    final current = state;
    if (current is! PulseLoaded) return;

    // Optimistic insert with a temporary id, reconciled on success.
    final tempId = 'temp-${clock.now().microsecondsSinceEpoch}';
    final optimisticLog = ContactLog(
      id: tempId,
      personId: event.personId,
      channel: event.channel,
      contactedAt: event.contactedAt,
      note: event.note,
    );

    final optimisticLogs = _sorted([optimisticLog, ...current.logs]);
    final optimisticPeople = _applyRecency(current.people, optimisticLog);
    emit(current.copyWith(people: optimisticPeople, logs: optimisticLogs));

    try {
      final saved = await _apiService.addContactLog(optimisticLog);
      final reconciledLogs = _sorted([
        for (final log in optimisticLogs)
          if (log.id == tempId) saved else log,
      ]);
      emit(current.copyWith(people: optimisticPeople, logs: reconciledLogs));
    } catch (e) {
      // Roll back to the pre-log snapshot and surface the failure.
      emit(
        current.copyWith(
          actionError: 'Could not save contact. Please try again.',
          actionNonce: current.actionNonce + 1,
        ),
      );
    }
  }

  Future<void> _onSetCadence(SetCadence event, Emitter<PulseState> emit) async {
    final current = state;
    if (current is! PulseLoaded) return;

    final index = current.people.indexWhere((p) => p.id == event.personId);
    if (index == -1) return;

    final original = current.people[index];
    final updated = original.copyWith(contactCadenceDays: event.cadenceDays);
    final optimisticPeople = List<Person>.from(current.people)
      ..[index] = updated;
    emit(current.copyWith(people: optimisticPeople));

    try {
      final saved = await _apiService.updatePerson(updated);
      final finalPeople = List<Person>.from(current.people)..[index] = saved;
      emit(current.copyWith(people: finalPeople));
    } catch (e) {
      emit(
        current.copyWith(
          people: List<Person>.from(current.people)..[index] = original,
          actionError: 'Could not update cadence. Please try again.',
          actionNonce: current.actionNonce + 1,
        ),
      );
    }
  }

  /// Bumps a person's recency summary when [log] is their newest touchpoint.
  List<Person> _applyRecency(List<Person> people, ContactLog log) {
    return people.map((p) {
      if (p.id != log.personId) return p;
      final last = p.lastContactedAt;
      if (last != null && last.isAfter(log.contactedAt)) return p;
      return p.copyWith(
        lastContactedAt: log.contactedAt,
        lastContactChannel: log.channel.apiValue,
      );
    }).toList();
  }

  List<ContactLog> _sorted(List<ContactLog> logs) {
    final copy = List<ContactLog>.from(logs)
      ..sort((a, b) => b.contactedAt.compareTo(a.contactedAt));
    return copy;
  }
}
