import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/auth/auth_bloc.dart';
import 'bloc/auth/auth_event.dart';
import 'bloc/auth/auth_state.dart';
import 'bloc/location/location_bloc.dart';
import 'bloc/people/people_bloc.dart';
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
import 'screens/profile/me_screen.dart';
import 'utils/app_theme.dart';
import 'components/shared/glass_container.dart';
import 'bloc/theme/theme_cubit.dart';

import 'package:timezone/data/latest.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'bloc/map/map_settings_cubit.dart';
import 'bloc/trip/trip_bloc.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

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
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
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
          final isDesktop = constraints.maxWidth >= 600;

          return Scaffold(
            extendBodyBehindAppBar: true,
            // Removed AppBar as requested
            body: Stack(
              children: [
                // Content Layer
                Positioned.fill(child: _getScreen(_selectedIndex)),

                // Glass Navigation Rail (Desktop)
                if (isDesktop)
                  Positioned(
                    left: 20,
                    top: 20,
                    child: GlassContainer(
                      width: 80,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 20),
                          // App Logo
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/Map-My-Friends-Default-1024x1024@1x.png',
                              width: 48,
                              height: 48,
                            ),
                          ),
                          const SizedBox(height: 40),

                          _buildGlassNavItem(
                            icon: Icons.map_outlined,
                            selectedIcon: Icons.map,
                            label: 'Map',
                            index: 0,
                            isSelected: _selectedIndex == 0,
                          ),
                          const SizedBox(height: 20),
                          _buildGlassNavItem(
                            icon: Icons.people_outline,
                            selectedIcon: Icons.people,
                            label: 'People',
                            index: 1,
                            isSelected: _selectedIndex == 1,
                          ),
                          const SizedBox(height: 20),
                          _buildGlassNavItem(
                            icon: Icons.person_outline,
                            selectedIcon: Icons.person,
                            label: 'Me',
                            index: 2,
                            isSelected: _selectedIndex == 2,
                          ),
                        ],
                      ),
                    ),
                  ),

                // Glass Bottom Navigation (Mobile)
                if (!isDesktop)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: GlassContainer(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 20,
                      ),
                      borderRadius: 30,
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
                            icon: Icons.person,
                            label: 'Me',
                            index: 2,
                            isSelected: _selectedIndex == 2,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = isDark ? Colors.indigoAccent : Colors.indigo;
    final unselectedColor = isDark ? Colors.white70 : Colors.grey[700];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onItemTapped(index),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 60,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: isSelected
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Column(
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                color: isSelected ? selectedColor : unselectedColor,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = isDark ? Colors.indigoAccent : Colors.indigo;
    final unselectedColor = isDark ? Colors.white70 : Colors.grey[700];

    return Expanded(
      child: InkWell(
        onTap: () => _onItemTapped(index),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? selectedColor : unselectedColor,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
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
}
