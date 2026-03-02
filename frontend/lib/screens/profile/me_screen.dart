import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../bloc/location/location_bloc.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/profile/profile_event.dart';
import '../../bloc/profile/profile_state.dart';
import '../../components/shared/image_editor_modal.dart';
import '../../components/shared/custom_text_form_field.dart';
import '../../bloc/theme/theme_cubit.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _countryController = TextEditingController();
  final _streetController = TextEditingController();
  final _imagePicker = ImagePicker();
  Uint8List?
  _localImageBytes; // For showing local image immediately after picking

  @override
  void initState() {
    super.initState();
    // Load profile when screen loads
    context.read<ProfileBloc>().add(LoadProfile());
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1024, // Increased to allow better quality potential for zoom
      maxHeight: 1024,
      imageQuality: 90,
    );

    if (pickedFile != null && mounted) {
      final bytes = await pickedFile.readAsBytes();

      if (!mounted) return;

      // Open editor
      // ignore: use_build_context_synchronously
      final Uint8List? croppedBytes = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ImageEditorModal(imageBytes: bytes, isCircular: true),
        ),
      );

      if (croppedBytes != null) {
        setState(() {
          _localImageBytes = croppedBytes;
        });

        // Upload to server
        // We need to pass the bytes, or save to a file first.
        // The UploadProfileImage event takes an XFile.
        // We can create an XFile from bytes.
        final tempFile = XFile.fromData(
          croppedBytes,
          name: 'profile_image.png',
          mimeType: 'image/png',
        );

        if (mounted) {
          context.read<ProfileBloc>().add(UploadProfileImage(image: tempFile));
        }
      }
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _populateFieldsFromProfile(ProfileLoaded state) {
    if (_cityController.text.isEmpty && state.city != null) {
      _cityController.text = state.city!;
    }
    if (_stateController.text.isEmpty && state.state != null) {
      _stateController.text = state.state!;
    }
    if (_countryController.text.isEmpty && state.country != null) {
      _countryController.text = state.country!;
    }
    if (_streetController.text.isEmpty && state.street != null) {
      _streetController.text = state.street!;
    }
  }

  @override
  void dispose() {
    _cityController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _streetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: MultiBlocListener(
          listeners: [
            BlocListener<LocationBloc, LocationState>(
              listener: (context, state) {
                if (state is LocationPermissionDenied) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Location permission denied')),
                  );
                } else if (state is LocationPermissionDeniedForever) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Location permission denied forever'),
                    ),
                  );
                } else if (state is LocationLoaded) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Location loaded')),
                  );
                }
              },
            ),
            BlocListener<ProfileBloc, ProfileState>(
              listener: (context, state) {
                if (state is ProfileLoaded) {
                  _populateFieldsFromProfile(state);
                  // Clear local image path once server image is loaded
                  if (state.profileImageUrl != null) {
                    setState(() {
                      _localImageBytes = null;
                    });
                  }
                } else if (state is ProfileError) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(state.message)));
                }
              },
            ),
          ],
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 600;

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 600 : double.infinity,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 32.0,
                    ),
                    child: Form(
                      key: _formKey,
                      child: BlocBuilder<ProfileBloc, ProfileState>(
                        builder: (context, profileState) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Profile Picture Section
                              Center(
                                child: Stack(
                                  children: [
                                    _buildProfileAvatar(profileState),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Theme.of(
                                              context,
                                            ).scaffoldBackgroundColor,
                                            width: 2,
                                          ),
                                        ),
                                        child: InkWell(
                                          onTap: profileState is ProfileUpdating
                                              ? null
                                              : _showImageSourceDialog,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child:
                                                profileState is ProfileUpdating
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : Icon(
                                                    Icons.camera_alt,
                                                    size: 20,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.onPrimary,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Theme Selector
                              BlocBuilder<ThemeCubit, ThemeMode>(
                                builder: (context, themeMode) {
                                  return SegmentedButton<ThemeMode>(
                                    segments: const [
                                      ButtonSegment(
                                        value: ThemeMode.light,
                                        icon: Icon(Icons.light_mode),
                                        label: Text('Light'),
                                      ),
                                      ButtonSegment(
                                        value: ThemeMode.system,
                                        icon: Icon(Icons.brightness_auto),
                                        label: Text('System'),
                                      ),
                                      ButtonSegment(
                                        value: ThemeMode.dark,
                                        icon: Icon(Icons.dark_mode),
                                        label: Text('Dark'),
                                      ),
                                    ],
                                    selected: {themeMode},
                                    onSelectionChanged:
                                        (Set<ThemeMode> newSelection) {
                                          context.read<ThemeCubit>().setTheme(
                                            newSelection.first,
                                          );
                                        },
                                    showSelectedIcon: false,
                                  );
                                },
                              ),

                              const SizedBox(height: 32),

                              // Location Button
                              BlocBuilder<LocationBloc, LocationState>(
                                builder: (context, state) {
                                  if (state is LocationLoading) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  return OutlinedButton.icon(
                                    onPressed: () {
                                      context.read<LocationBloc>().add(
                                        RequestPermission(),
                                      );
                                    },
                                    icon: const Icon(Icons.my_location),
                                    label: const Text('Use Current Location'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 32),
                              Text(
                                'My Address',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),

                              CustomTextFormField(
                                controller: _streetController,
                                labelText: 'Street Address (Optional)',
                                prefixIcon: const Icon(Icons.home_outlined),
                              ),
                              const SizedBox(height: 16),

                              CustomTextFormField(
                                controller: _cityController,
                                labelText: 'City (Required)',
                                prefixIcon: const Icon(Icons.location_city),
                                validator: (value) =>
                                    value == null || value.isEmpty
                                    ? 'City is required'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: CustomTextFormField(
                                      controller: _stateController,
                                      labelText: 'State (Required)',
                                      validator: (value) =>
                                          value == null || value.isEmpty
                                          ? 'Required'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: CustomTextFormField(
                                      controller: _countryController,
                                      labelText: 'Country (Required)',
                                      validator: (value) =>
                                          value == null || value.isEmpty
                                          ? 'Required'
                                          : null,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 32),

                              SizedBox(
                                height: 50,
                                child: FilledButton(
                                  onPressed: profileState is ProfileUpdating
                                      ? null
                                      : () {
                                          if (_formKey.currentState!
                                              .validate()) {
                                            context.read<ProfileBloc>().add(
                                              UpdateProfile(
                                                city: _cityController.text,
                                                state: _stateController.text,
                                                country:
                                                    _countryController.text,
                                                street:
                                                    _streetController
                                                        .text
                                                        .isNotEmpty
                                                    ? _streetController.text
                                                    : null,
                                              ),
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text('Address Saved'),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: profileState is ProfileUpdating
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Save Address',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                height: 50,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    context.read<AuthBloc>().add(
                                      LogoutRequested(),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.logout,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Logout',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: Colors.red,
                                      width: 2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: 120,
                              ), // Bottom padding for navigation bar
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(ProfileState profileState) {
    ImageProvider? backgroundImage;

    // Priority: local image (just picked) > server image
    if (_localImageBytes != null) {
      backgroundImage = MemoryImage(_localImageBytes!);
    } else if (profileState is ProfileLoaded &&
        profileState.profileImageUrl != null) {
      backgroundImage = NetworkImage(profileState.profileImageUrl!);
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          width: 4,
        ),
        shape: BoxShape.circle,
      ),
      child: CircleAvatar(
        radius: 64,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        backgroundImage: backgroundImage,
        child: backgroundImage == null
            ? Icon(
                Icons.person,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )
            : null,
      ),
    );
  }
}
