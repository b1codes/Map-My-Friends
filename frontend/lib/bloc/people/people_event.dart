part of 'people_bloc.dart';

abstract class PeopleEvent extends Equatable {
  const PeopleEvent();

  @override
  List<Object?> get props => [];
}

class LoadPeople extends PeopleEvent {}

/// A change to one person that goes to the API: add, update or delete.
///
/// [done], when given, completes once the API has accepted the change, or
/// completes with its error, so the screen that asked can wait: close a
/// form only once its person is saved, or keep it open, input and all, to
/// try again. The loaded list stays as it was when a change fails.
abstract class PersonWrite extends PeopleEvent {
  const PersonWrite({this.done});

  final Completer<void>? done;
}

class AddPerson extends PersonWrite {
  final Person person;
  final XFile? profileImage;
  final Uint8List? imageBytes;

  const AddPerson(
    this.person, {
    this.profileImage,
    this.imageBytes,
    super.done,
  });

  @override
  List<Object?> get props => [person, profileImage, imageBytes];
}

class UpdatePerson extends PersonWrite {
  final Person person;
  final XFile? profileImage;
  final Uint8List? imageBytes;

  const UpdatePerson(
    this.person, {
    this.profileImage,
    this.imageBytes,
    super.done,
  });

  @override
  List<Object?> get props => [person, profileImage, imageBytes];
}

class DeletePerson extends PersonWrite {
  final String id;

  const DeletePerson(this.id, {super.done});

  @override
  List<Object?> get props => [id];
}
