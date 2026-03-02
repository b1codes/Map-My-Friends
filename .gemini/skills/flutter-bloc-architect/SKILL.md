---
name: flutter-bloc-architect
description: Architectural guidance for the Flutter frontend, enforcing BLoC pattern, dependency injection, and centralized theming. Use when adding new features, screens, or state management logic in Flutter.
---

# Flutter BLoC Architect

This skill ensures consistent adherence to the project's Flutter architecture.

## Architecture

### State Management
- Use **BLoC (Business Logic Component)** for all complex state management.
- BLoCs are located in `frontend/lib/bloc/`.
- States should be `sealed` classes or use `Equatable` to ensure efficient UI updates.
- Events should be descriptive and triggered from the UI layer.

### Networking
- Centralized `ApiService` in `frontend/lib/services/api_service.dart`.
- Use **Dio** with interceptors for JWT token rotation.
- All API requests must be handled through the `ApiService`.

### Directory Structure
- `lib/bloc/`: State management logic.
- `lib/components/`: Reusable UI widgets.
- `lib/models/`: Data models and JSON serialization.
- `lib/screens/`: High-level feature screens.
- `lib/services/`: API and Auth logic.
- `lib/utils/`: Theme, constants, and helpers.

## Common Workflows

### Creating a New Feature BLoC
1. Define states (`Initial`, `Loading`, `Success`, `Failure`).
2. Define events (`FetchData`, `UpdateItem`).
3. Implement logic in the `Bloc` class, interacting with the `ApiService`.

### Adding a New Screen
1. Create a `StatelessWidget` in `lib/screens/`.
2. Wrap the screen in a `BlocProvider` if it needs a feature-specific BLoC.
3. Use `BlocBuilder` or `BlocListener` to react to state changes.

### UI Standards
- Use `AppTheme` from `lib/utils/app_theme.dart` for all styling.
- Prefer `flutter_map` for any interactive map components.
