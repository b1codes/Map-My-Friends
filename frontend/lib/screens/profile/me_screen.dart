import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/profile/profile_event.dart';
import '../../bloc/profile/profile_state.dart';
import '../../components/shared/image_editor_modal.dart';
import '../../components/shared/custom_text_form_field.dart';
import '../../components/map/custom_map_marker.dart';
import '../../components/shared/nearby_airports_section.dart';
import '../../components/shared/nearby_stations_section.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../bloc/location/location_bloc.dart';
import '../settings/settings_screen.dart';

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
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _imagePicker = ImagePicker();
  Uint8List?
  _localImageBytes; // For showing local image immediately after picking

  // Pin customization state
  String _pinColor = '#2196F3';
  String _pinStyle = 'teardrop';
  String _pinIconType = 'none';
  String? _pinEmoji;
  bool _pinFieldsPopulated = false;

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

        if (mounted) {
          context.read<ProfileBloc>().add(
            UploadProfileImage(imageBytes: croppedBytes),
          );
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

  void _showColorPicker() {
    Color pickerColor = Color(int.parse(_pinColor.replaceFirst('#', '0xFF')));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a Pin Color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) {
              setState(() {
                _pinColor =
                    '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
              });
            },
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Got it'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _showEmojiPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 300,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {
                setState(() {
                  _pinEmoji = emoji.emoji;
                });
                Navigator.pop(context);
              },
            ),
          ),
        );
      },
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
    if (_firstNameController.text.isEmpty && state.firstName != null) {
      _firstNameController.text = state.firstName!;
    }
    if (_lastNameController.text.isEmpty && state.lastName != null) {
      _lastNameController.text = state.lastName!;
    }
    if (_phoneNumberController.text.isEmpty && state.phoneNumber != null) {
      _phoneNumberController.text = state.phoneNumber!;
    }
    if (_birthDateController.text.isEmpty && state.birthDate != null) {
      _birthDateController.text = state.birthDate!;
    }
    // Populate pin fields only once from server
    if (!_pinFieldsPopulated) {
      if (state.pinColor != null) _pinColor = state.pinColor!;
      if (state.pinStyle != null) _pinStyle = state.pinStyle!;
      if (state.pinIconType != null) _pinIconType = state.pinIconType!;
      _pinEmoji = state.pinEmoji ?? '😀';
      _pinFieldsPopulated = true;
    }
  }

  @override
  void dispose() {
    _cityController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _streetController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneNumberController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        child: MultiBlocListener(
          listeners: [
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
                              const SizedBox(height: 32),
                              Text(
                                'Personal Info',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: CustomTextFormField(
                                      controller: _firstNameController,
                                      labelText: 'First Name',
                                      prefixIcon: const Icon(
                                        Icons.person_outline,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: CustomTextFormField(
                                      controller: _lastNameController,
                                      labelText: 'Last Name',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              CustomTextFormField(
                                controller: _phoneNumberController,
                                labelText: 'Phone Number',
                                prefixIcon: const Icon(Icons.phone_outlined),
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 16),
                              CustomTextFormField(
                                controller: _birthDateController,
                                labelText: 'Birth Date (YYYY-MM-DD)',
                                prefixIcon: const Icon(Icons.cake_outlined),
                                keyboardType: TextInputType.datetime,
                                readOnly: true,
                                onTap: () async {
                                  FocusScope.of(
                                    context,
                                  ).requestFocus(FocusNode());
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        DateTime.tryParse(
                                          _birthDateController.text,
                                        ) ??
                                        DateTime.now(),
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime.now(),
                                  );
                                  if (date != null) {
                                    _birthDateController.text =
                                        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
                                  }
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

                              // --- Map Pin Customization ---
                              Text(
                                'Map Pin Customization',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                              const SizedBox(height: 16),

                              // Pin Preview
                              Center(
                                child: Column(
                                  children: [
                                    CustomMapMarker(
                                      pinColorHex: _pinColor,
                                      pinStyle: _pinStyle,
                                      pinIconType: _pinIconType,
                                      pinEmoji: _pinEmoji,
                                      initials: _getInitials(),
                                      profileImageUrl:
                                          profileState is ProfileLoaded
                                          ? profileState.profileImageUrl
                                          : null,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Preview',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Pin Color'),
                                trailing: GestureDetector(
                                  onTap: _showColorPicker,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Color(
                                        int.parse(
                                          _pinColor.replaceFirst('#', '0xFF'),
                                        ),
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              DropdownButtonFormField<String>(
                                initialValue: _pinStyle,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'teardrop',
                                    child: Text('Teardrop'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'circle',
                                    child: Text('Circle'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'square',
                                    child: Text('Square'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'triangle',
                                    child: Text('Triangle'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'diamond',
                                    child: Text('Diamond'),
                                  ),
                                ],
                                onChanged: (val) =>
                                    setState(() => _pinStyle = val!),
                                decoration: InputDecoration(
                                  labelText: 'Pin Shape',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLowest,
                                ),
                              ),
                              const SizedBox(height: 16),

                              DropdownButtonFormField<String>(
                                initialValue: _pinIconType,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'none',
                                    child: Text('None'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'emoji',
                                    child: Text('Emoji'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'initials',
                                    child: Text('Initials'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'picture',
                                    child: Text('Profile Picture'),
                                  ),
                                ],
                                onChanged: (val) =>
                                    setState(() => _pinIconType = val!),
                                decoration: InputDecoration(
                                  labelText: 'Inner Icon',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLowest,
                                ),
                              ),

                              if (_pinIconType == 'emoji') ...[
                                const SizedBox(height: 16),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Selected Emoji'),
                                  trailing: GestureDetector(
                                    onTap: _showEmojiPicker,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _pinEmoji ?? '😀',
                                        style: const TextStyle(fontSize: 24),
                                      ),
                                    ),
                                  ),
                                ),
                              ],

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
                                                firstName:
                                                    _firstNameController
                                                        .text
                                                        .isNotEmpty
                                                    ? _firstNameController.text
                                                    : null,
                                                lastName:
                                                    _lastNameController
                                                        .text
                                                        .isNotEmpty
                                                    ? _lastNameController.text
                                                    : null,
                                                phoneNumber:
                                                    _phoneNumberController
                                                        .text
                                                        .isNotEmpty
                                                    ? _phoneNumberController
                                                          .text
                                                    : null,
                                                birthDate:
                                                    _birthDateController
                                                        .text
                                                        .isNotEmpty
                                                    ? _birthDateController.text
                                                    : null,
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
                                                pinColor: _pinColor,
                                                pinStyle: _pinStyle,
                                                pinIconType: _pinIconType,
                                                pinEmoji: _pinEmoji,
                                              ),
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text('Profile Saved'),
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
                                          'Save Profile',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Nearby Airports section
                              BlocBuilder<LocationBloc, LocationState>(
                                builder: (context, locationState) {
                                  if (locationState is LocationLoaded &&
                                      locationState.position != null) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 24,
                                      ),
                                      child: NearbyAirportsSection(
                                        latitude:
                                            locationState.position!.latitude,
                                        longitude:
                                            locationState.position!.longitude,
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),

                              BlocBuilder<LocationBloc, LocationState>(
                                builder: (context, locationState) {
                                  if (locationState is LocationLoaded &&
                                      locationState.position != null) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 24,
                                      ),
                                      child: NearbyStationsSection(
                                        latitude:
                                            locationState.position!.latitude,
                                        longitude:
                                            locationState.position!.longitude,
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),

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

  String _getInitials() {
    String initials = '';
    if (_firstNameController.text.isNotEmpty) {
      initials += _firstNameController.text[0];
    }
    if (_lastNameController.text.isNotEmpty) {
      initials += _lastNameController.text[0];
    }
    return initials;
  }
}
