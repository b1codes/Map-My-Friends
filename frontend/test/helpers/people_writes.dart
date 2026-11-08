import 'package:map_my_friends/bloc/people/people_bloc.dart';
import 'package:mocktail/mocktail.dart';

/// Makes a mocked [PeopleBloc] answer every add, update and delete the way
/// the real one does: by completing the event's `done`, or failing it with
/// [error]. Screens wait for that before they move on, so without it they'd
/// wait forever.
void answerPeopleWrites(PeopleBloc bloc, {Object? error}) {
  when(() => bloc.add(any())).thenAnswer((invocation) {
    final event = invocation.positionalArguments.single;
    if (event is PersonWrite) {
      error == null ? event.done?.complete() : event.done?.completeError(error);
    }
  });
}
