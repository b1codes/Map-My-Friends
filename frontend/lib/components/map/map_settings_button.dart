import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/map/local_map_settings_cubit.dart';
import '../shared/glass_container.dart';
import '../shared/thermal_response.dart';
import 'map_settings_modal.dart';
import '../../utils/app_theme.dart';

class MapSettingsButton extends StatelessWidget {
  const MapSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      right: 16,
      top: topPadding + 16,
      child: GlassContainer(
        padding: const EdgeInsets.all(8),
        borderRadius: MapGlass.radiusLg,
        child: ThermalResponse(
          borderRadius: MapGlass.radiusLg,
          onTap: () {
            showModalBottomSheet<void>(
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
          child: Semantics(
            button: true,
            label: 'Map settings',
            child: Icon(
              Icons.settings,
              color: Theme.of(context).colorScheme.primary,
              size: 24, // Consistent with IconButton default size
            ),
          ),
        ),
      ),
    );
  }
}
