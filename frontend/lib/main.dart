import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/auth/auth_bloc.dart';
import 'bloc/auth/auth_event.dart';
import 'bloc/auth/auth_state.dart';
import 'bloc/location/location_bloc.dart';
import 'bloc/people/people_bloc.dart';
import 'bloc/pulse/pulse_bloc.dart';
import 'bloc/airport/airport_bloc.dart';
import 'bloc/airport/airport_event.dart';
import 'bloc/station/station_bloc.dart';
import 'bloc/station/station_event.dart';
import 'bloc/profile/profile_bloc.dart';
import 'bloc/profile/profile_event.dart';
import 'bloc/profile/profile_state.dart';
import 'services/api_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/map/map_screen.dart';
import 'screens/people/people_screen.dart';
import 'screens/pulse/pulse_screen.dart';
import 'screens/profile/me_screen.dart';
import 'screens/trips/trips_screen.dart';
import 'utils/app_theme.dart';
import 'utils/window_size.dart';
import 'components/shared/ambient_field.dart';
import 'components/shared/glass_container.dart';
import 'components/shared/nav_label.dart';
import 'bloc/theme/theme_cubit.dart';

import 'package:timezone/data/latest.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'bloc/map/map_settings_cubit.dart';
import 'bloc/trip/trip_bloc.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'components/shared/chromatic_pulse.dart';
import 'components/shared/thermal_response.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await FMTCObjectBoxBackend().initialise();
  }
  tz.initializeTimeZones();
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  const MyApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    // Initialize ApiService singleton
    final apiService = ApiService();

    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc()..add(CheckAuthStatus()),
        ),
        BlocProvider<LocationBloc>(
          create: (context) => LocationBloc()..add(LoadLocation()),
        ),
        BlocProvider<PeopleBloc>(
          create: (context) =>
              PeopleBloc(apiService: apiService)..add(LoadPeople()),
        ),
        BlocProvider<PulseBloc>(
          create: (context) => PulseBloc(apiService: apiService),
        ),
        BlocProvider<ProfileBloc>(create: (context) => ProfileBloc()),
        BlocProvider<ThemeCubit>(create: (context) => ThemeCubit()),
        BlocProvider<MapSettingsCubit>(
          create: (context) => MapSettingsCubit(prefs: prefs),
        ),
        BlocProvider<AirportBloc>(
          create: (context) => AirportBloc()..add(LoadMapAirports()),
        ),
        BlocProvider<StationBloc>(
          create: (context) => StationBloc()..add(LoadMapStations()),
        ),
        BlocProvider<TripBloc>(create: (context) => TripBloc()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            title: 'Map My Friends',
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en'), // English
              Locale('es'), // Spanish
            ],
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthInitial || state is AuthLoading) {
          // The app's very first frame is a wait, so it is the first thing
          // the Chromatic Pulse answers for.
          return const Scaffold(body: PulseIndicator());
        }

        if (state is Authenticated) {
          return const MainScreen();
        }

        return const LoginScreen();
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Load profile data (custom pin settings) on app launch
    context.read<ProfileBloc>().add(LoadProfile());
  }

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return const MapScreen();
      case 1:
        return const PeopleScreen();
      case 2:
        return const PulseScreen();
      case 3:
        return TripsScreen(onNavigateToMap: () => _onItemTapped(0));
      case 4:
        return const MeScreen();
      default:
        return const MapScreen();
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ProfileBloc, ProfileState>(
          listener: (context, state) {
            if (state is ProfileLoaded && state.distanceUnit != null) {
              final unit = state.distanceUnit == 'imperial'
                  ? DistanceUnit.imperial
                  : DistanceUnit.metric;
              // Only update if different to avoid redundant pref writes
              if (context.read<MapSettingsCubit>().state.distanceUnit != unit) {
                context.read<MapSettingsCubit>().setDistanceUnit(unit);
              }
            }
          },
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Both axes, not just width: see MapWindow. A phone in landscape is
          // wider than a tablet in portrait, and it is the one place a rail
          // cannot fit.
          final window = MapWindow(
            Size(constraints.maxWidth, constraints.maxHeight),
          );

          // One backdrop sample for the whole shell: the nav chrome and every
          // glass surface the active screen draws share it, so the screen costs
          // a single BackdropFilter layer rather than one per panel.
          // Scoped to the shell, not the app, so route transitions never
          // overlap two screens on the same backdrop key.
          return BackdropGroup(
            child: Scaffold(
              extendBodyBehindAppBar: true,
              // Transparent so the field below is what every glass surface on
              // every tab refracts. The shell owns exactly one field; tab
              // screens are transparent over it, and only routes pushed on top
              // of the shell bring their own (see AmbientScaffold).
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  // The room. Painted first so the shared backdrop sample taken
                  // by the chrome above includes it; it costs no filter layer
                  // of its own.
                  const Positioned.fill(child: AmbientField()),

                  // Content Layer
                  Positioned.fill(child: _getScreen(_selectedIndex)),

                  // Glass Navigation Rail (Desktop)
                  if (window.usesRail)
                    Positioned(
                      left: 24 + MediaQuery.of(context).padding.left,
                      top: 24 + MediaQuery.of(context).padding.top,
                      child: GlassContainer(
                        width: 80,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 24),
                            // App Logo
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                MapGlass.radiusMd,
                              ),
                              child: Image.asset(
                                'assets/Map-My-Friends-Default-1024x1024@1x.png',
                                width: 48,
                                height: 48,
                              ),
                            ),
                            const SizedBox(height: 32),

                            _buildGlassNavItem(
                              icon: Icons.map_outlined,
                              selectedIcon: Icons.map,
                              label: 'Map',
                              index: 0,
                              isSelected: _selectedIndex == 0,
                            ),
                            const SizedBox(height: 24),
                            _buildGlassNavItem(
                              icon: Icons.people_outline,
                              selectedIcon: Icons.people,
                              label: 'People',
                              index: 1,
                              isSelected: _selectedIndex == 1,
                            ),
                            const SizedBox(height: 24),
                            _buildGlassNavItem(
                              icon: Icons.monitor_heart_outlined,
                              selectedIcon: Icons.monitor_heart,
                              label: 'Pulse',
                              index: 2,
                              isSelected: _selectedIndex == 2,
                            ),
                            const SizedBox(height: 24),
                            _buildGlassNavItem(
                              icon: Icons.route_outlined,
                              selectedIcon: Icons.route,
                              index: 3,
                              isSelected: _selectedIndex == 3,
                              label: 'Trips',
                            ),
                            const SizedBox(height: 24),
                            _buildGlassNavItem(
                              icon: Icons.person_outline,
                              selectedIcon: Icons.person,
                              label: 'Me',
                              index: 4,
                              isSelected: _selectedIndex == 4,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Glass Bottom Navigation (Mobile)
                  if (window.usesBar)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16 + MediaQuery.of(context).padding.bottom,
                      child: GlassContainer(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        borderRadius: MapGlass.radiusLg,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildGlassNavItemMobile(
                              icon: Icons.map,
                              label: 'Map',
                              index: 0,
                              isSelected: _selectedIndex == 0,
                            ),
                            _buildGlassNavItemMobile(
                              icon: Icons.people,
                              label: 'People',
                              index: 1,
                              isSelected: _selectedIndex == 1,
                            ),
                            _buildGlassNavItemMobile(
                              icon: Icons.monitor_heart,
                              label: 'Pulse',
                              index: 2,
                              isSelected: _selectedIndex == 2,
                            ),
                            _buildGlassNavItemMobile(
                              icon: Icons.route,
                              label: 'Trips',
                              index: 3,
                              isSelected: _selectedIndex == 3,
                            ),
                            _buildGlassNavItemMobile(
                              icon: Icons.person,
                              label: 'Me',
                              index: 4,
                              isSelected: _selectedIndex == 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGlassNavItem({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required int index,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;
    final unselectedColor = theme.colorScheme.onSurfaceVariant;

    return Semantics(
      selected: isSelected,
      label: '$label Tab',
      // The most-touched control in the app, so it answers in the app's own
      // interaction language: heat and a yielding surface, not an ink ripple
      // crossing a Material layer that exists only to host the ripple.
      child: ThermalResponse(
        onTap: () => _onItemTapped(index),
        borderRadius: MapGlass.radiusMd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 60,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: isSelected
              ? BoxDecoration(
                  color: MapGlass.selectionLift(theme.brightness),
                  borderRadius: BorderRadius.circular(MapGlass.radiusMd),
                )
              : const BoxDecoration(),
          child: Column(
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                color: isSelected ? selectedColor : unselectedColor,
                size: 24,
              ),
              const SizedBox(height: 4),
              NavLabel(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? selectedColor : unselectedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassNavItemMobile({
    required IconData icon,
    required String label,
    required int index,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;
    final unselectedColor = theme.colorScheme.onSurfaceVariant;

    return Expanded(
      child: Semantics(
        selected: isSelected,
        label: '$label Tab',
        child: ThermalResponse(
          onTap: () => _onItemTapped(index),
          borderRadius: MapGlass.radiusMd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            decoration: isSelected
                ? BoxDecoration(
                    color: MapGlass.selectionLift(theme.brightness),
                    borderRadius: BorderRadius.circular(MapGlass.radiusMd),
                  )
                : const BoxDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isSelected ? selectedColor : unselectedColor,
                  size: 24,
                ),
                const SizedBox(height: 4),
                NavLabel(
                  label,
                  style: (theme.textTheme.labelSmall ?? const TextStyle())
                      .copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? selectedColor : unselectedColor,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
