import 'dart:async';
import 'dart:typed_data';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/person.dart';
import '../../services/api_service.dart';

part 'people_event.dart';
part 'people_state.dart';

class PeopleBloc extends Bloc<PeopleEvent, PeopleState> {
  final ApiService _apiService;

  PeopleBloc({required ApiService apiService})
    : _apiService = apiService,
      super(PeopleInitial()) {
    on<LoadPeople>(_onLoadPeople);
    on<AddPerson>(_onAddPerson);
    on<UpdatePerson>(_onUpdatePerson);
    on<DeletePerson>(_onDeletePerson);
  }

  Future<void> _onLoadPeople(
    LoadPeople event,
    Emitter<PeopleState> emit,
  ) async {
    emit(PeopleLoading());
    try {
      final people = await _apiService.getPeople();
      emit(PeopleLoaded(people));
    } catch (e) {
      emit(PeopleError(e.toString()));
    }
  }

  // Each write applies its result to the list as it is when the API
  // answers, not as it was when the request left: the bloc handles events
  // concurrently, so two quick saves would otherwise each write back a list
  // without the other's person.
  //
  // A failed write leaves the list alone and reports through the event's
  // `done`. It used to replace the whole list with PeopleError, a dead end
  // with no retry until the app restarted, and the form that asked had
  // already closed with its input.

  Future<void> _onAddPerson(AddPerson event, Emitter<PeopleState> emit) async {
    await _write(event, () async {
      final newPerson = await _apiService.addPerson(
        event.person,
        profileImage: event.profileImage,
        imageBytes: event.imageBytes,
        idempotencyKey: event.idempotencyKey,
      );
      final current = state;
      if (current is PeopleLoaded) {
        emit(PeopleLoaded([...current.people, newPerson]));
      } else {
        // Saved before the list arrived (or after it failed to): load it,
        // new person included.
        add(LoadPeople());
      }
    });
  }

  Future<void> _onUpdatePerson(
    UpdatePerson event,
    Emitter<PeopleState> emit,
  ) async {
    await _write(event, () async {
      final updatedPerson = await _apiService.updatePerson(
        event.person,
        profileImage: event.profileImage,
        imageBytes: event.imageBytes,
      );
      final current = state;
      if (current is PeopleLoaded) {
        emit(
          PeopleLoaded([
            for (final p in current.people)
              p.id == updatedPerson.id ? updatedPerson : p,
          ]),
        );
      } else {
        add(LoadPeople());
      }
    });
  }

  Future<void> _onDeletePerson(
    DeletePerson event,
    Emitter<PeopleState> emit,
  ) async {
    await _write(event, () async {
      await _apiService.deletePerson(event.id);
      final current = state;
      if (current is PeopleLoaded) {
        emit(
          PeopleLoaded([
            for (final p in current.people)
              if (p.id != event.id) p,
          ]),
        );
      } else {
        add(LoadPeople());
      }
    });
  }

  Future<void> _write(PersonWrite event, Future<void> Function() run) async {
    try {
      await run();
      event.done?.complete();
    } catch (e, stack) {
      event.done?.completeError(e, stack);
    }
  }
}
