import 'package:flutter/material.dart';
import '../../models/person.dart';
import '../../screens/people/person_details_screen.dart';
import 'custom_map_marker.dart';
import '../shared/glass_surfaces.dart';

class PersonMapMarker extends StatelessWidget {
  final Person person;
  final VoidCallback? onTap;

  /// Whether this marker answers taps itself. False on a marker layer that
  /// handles them (see [PersonMapMarker.onLayer]).
  final bool _handlesTap;

  const PersonMapMarker({super.key, required this.person, this.onTap})
    : _handlesTap = true;

  /// A pin on a map layer that already handles marker taps, as MapScreen's
  /// cluster layer does.
  ///
  /// The layer wraps every marker in its own tap handler. A marker that
  /// handled taps too would be a second tap target inside the layer's, and a
  /// screen reader would land on the layer's first: a button with no name.
  /// Leaving the tap to the layer makes the pin one button, named for the
  /// friend.
  const PersonMapMarker.onLayer({super.key, required this.person})
    : onTap = null,
      _handlesTap = false;

  @override
  Widget build(BuildContext context) {
    String initials = '';
    if (person.firstName.isNotEmpty) initials += person.firstName[0];
    if (person.lastName.isNotEmpty) initials += person.lastName[0];

    final marker = CustomMapMarker(
      pinColorHex: person.pinColor,
      pinStyle: person.pinStyle,
      pinIconType: person.pinIconType,
      pinEmoji: person.pinEmoji,
      initials: initials,
      profileImageUrl: person.profileImageUrl,
      semanticsLabel: 'Friend: ${person.firstName} ${person.lastName}',
      onTap: !_handlesTap
          ? null
          : onTap ??
                () {
                  GlassDialog.confirm(
                    context,
                    title: '${person.firstName} ${person.lastName}',
                    message: '${person.city}, ${person.state}',
                    confirmLabel: 'View Details',
                    cancelLabel: 'Close',
                  ).then((open) {
                    if (!open || !context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) =>
                            PersonDetailsScreen(personId: person.id),
                      ),
                    );
                  });
                },
    );
    // The layer's tap handler supplies the tap; this says what it does.
    return _handlesTap ? marker : Semantics(button: true, child: marker);
  }
}
