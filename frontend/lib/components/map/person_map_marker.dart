import 'package:flutter/material.dart';
import '../../models/person.dart';
import '../../screens/people/person_details_screen.dart';
import 'custom_map_marker.dart';

class PersonMapMarker extends StatelessWidget {
  final Person person;
  final VoidCallback? onTap;

  const PersonMapMarker({super.key, required this.person, this.onTap});

  @override
  Widget build(BuildContext context) {
    String initials = '';
    if (person.firstName.isNotEmpty) initials += person.firstName[0];
    if (person.lastName.isNotEmpty) initials += person.lastName[0];

    return CustomMapMarker(
      pinColorHex: person.pinColor,
      pinStyle: person.pinStyle,
      pinIconType: person.pinIconType,
      pinEmoji: person.pinEmoji,
      initials: initials,
      profileImageUrl: person.profileImageUrl,
      semanticsLabel: 'Friend: ${person.firstName} ${person.lastName}',
      onTap:
          onTap ??
          () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('${person.firstName} ${person.lastName}'),
                content: Text('${person.city}, ${person.state}'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); // Close dialog
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              PersonDetailsScreen(personId: person.id),
                        ),
                      );
                    },
                    child: const Text('View Details'),
                  ),
                ],
              ),
            );
          },
    );
  }
}
