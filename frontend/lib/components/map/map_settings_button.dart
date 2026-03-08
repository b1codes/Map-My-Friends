import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/map/local_map_settings_cubit.dart';
import '../shared/glass_container.dart';
import 'map_settings_modal.dart';

class MapSettingsButton extends StatelessWidget {
  const MapSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      right: 20,
      top: topPadding > 0 ? topPadding + 10 : 20,
      child: GlassContainer(
        padding: const EdgeInsets.all(8),
        borderRadius: 30,
        child: IconButton(
          icon: const Icon(Icons.settings, color: Colors.indigo),
          tooltip: 'Map Settings',
          onPressed: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (_) {
                // Pass the existing scoped cubit to the modal
                return BlocProvider.value(
                  value: context.read<LocalMapSettingsCubit>(),
                  child: const MapSettingsModal(),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
