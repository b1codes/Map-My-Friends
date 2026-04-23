import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/person.dart';
import '../../bloc/people/people_bloc.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../components/shared/image_editor_modal.dart';
import '../../components/shared/custom_text_form_field.dart';
import '../../components/map/custom_map_marker.dart';

class AddEditPersonScreen extends StatefulWidget {
  final Person? person;

  const AddEditPersonScreen({super.key, this.person});

  @override
  State<AddEditPersonScreen> createState() => _AddEditPersonScreenState();
}

class _AddEditPersonScreenState extends State<AddEditPersonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _tagController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _countryController;
  late TextEditingController _streetController;
  late TextEditingController _phoneController;
  DateTime? _birthday;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  String? _existingImageUrl;

  String _pinColor = '#F44336';
  String _pinStyle = 'teardrop';
  String _pinIconType = 'none';
  String? _pinEmoji;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(
      text: widget.person?.firstName ?? '',
    );
    _lastNameController = TextEditingController(
      text: widget.person?.lastName ?? '',
    );
    _tagController = TextEditingController(
      text: widget.person?.relationshipTag ?? 'FRIEND',
    );
    _cityController = TextEditingController(text: widget.person?.city ?? '');
    _stateController = TextEditingController(text: widget.person?.state ?? '');
    _countryController = TextEditingController(
      text: widget.person?.country ?? '',
    );
    _streetController = TextEditingController(
      text: widget.person?.street ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.person?.phoneNumber ?? '',
    );
    _birthday = widget.person?.birthday;
    _existingImageUrl = widget.person?.profileImageUrl;

    _pinColor = widget.person?.pinColor ?? '#F44336';
    _pinStyle = widget.person?.pinStyle ?? 'teardrop';
    _pinIconType = widget.person?.pinIconType ?? 'none';
    _pinEmoji = widget.person?.pinEmoji ?? '😀';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _tagController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _streetController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
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
            _selectedImageBytes = croppedBytes;
            _selectedImage = null; // clear any previous XFile
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
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
            onPressed: () {
              Navigator.of(context).pop();
            },
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

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_selectedImage != null || _existingImageUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedImage = null;
                    _selectedImageBytes = null;
                    _existingImageUrl = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final person = Person(
        id: widget.person?.id ?? '',
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        relationshipTag: _tagController.text,
        city: _cityController.text,
        state: _stateController.text,
        country: _countryController.text,
        street: _streetController.text.isNotEmpty
            ? _streetController.text
            : null,
        phoneNumber: _phoneController.text.isNotEmpty
            ? _phoneController.text
            : null,
        birthday: _birthday,
        latitude: widget.person?.latitude,
        longitude: widget.person?.longitude,
        profileImageUrl: _existingImageUrl,
        pinColor: _pinColor,
        pinStyle: _pinStyle,
        pinIconType: _pinIconType,
        pinEmoji: _pinIconType == 'emoji' ? _pinEmoji : null,
      );

      if (widget.person != null) {
        context.read<PeopleBloc>().add(
          UpdatePerson(
            person,
            profileImage: _selectedImage,
            imageBytes: _selectedImageBytes,
          ),
        );
      } else {
        context.read<PeopleBloc>().add(
          AddPerson(
            person,
            profileImage: _selectedImage,
            imageBytes: _selectedImageBytes,
          ),
        );
      }
      Navigator.pop(context);
    }
  }

  Widget _buildProfileImagePicker() {
    return Center(
      child: GestureDetector(
        onTap: _showImagePickerOptions,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  width: 4,
                ),
                shape: BoxShape.circle,
              ),
              child: CircleAvatar(
                radius: 64,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                backgroundImage: _selectedImageBytes != null
                    ? MemoryImage(_selectedImageBytes!)
                    : (_existingImageUrl != null
                              ? NetworkImage(_existingImageUrl!)
                              : null)
                          as ImageProvider?,
                child:
                    (_selectedImageBytes == null && _existingImageUrl == null)
                    ? Icon(
                        Icons.person,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.person != null ? 'Edit Person' : 'Add Person'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 600;

          String? timeString;
          if (widget.person?.timezone != null &&
              widget.person!.timezone!.isNotEmpty) {
            try {
              final location = tz.getLocation(widget.person!.timezone!);
              final now = tz.TZDateTime.now(location);
              timeString = DateFormat.jm().format(now);
            } catch (_) {}
          }

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 600 : double.infinity,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 24.0,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProfileImagePicker(),
                      if (timeString != null) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Local Time: $timeString',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        const SizedBox(height: 32),
                      ],

                      Text(
                        'Basic Info',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: CustomTextFormField(
                              controller: _firstNameController,
                              labelText: 'First Name',
                              validator: (val) => val == null || val.isEmpty
                                  ? 'Required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: CustomTextFormField(
                              controller: _lastNameController,
                              labelText: 'Last Name',
                              validator: (val) => val == null || val.isEmpty
                                  ? 'Required'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      DropdownButtonFormField<String>(
                        initialValue: _tagController.text.isNotEmpty
                            ? _tagController.text
                            : 'FRIEND',
                        items: const [
                          DropdownMenuItem(
                            value: 'FRIEND',
                            child: Text('Friend'),
                          ),
                          DropdownMenuItem(
                            value: 'FAMILY',
                            child: Text('Family'),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _tagController.text = val!),
                        decoration: InputDecoration(
                          labelText: 'Relationship Tag',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          filled: true,
                          fillColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLowest,
                        ),
                      ),
                      const SizedBox(height: 32),

                      Text(
                        'Address',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
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
                        validator: (val) =>
                            val == null || val.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: CustomTextFormField(
                              controller: _stateController,
                              labelText: 'State (Required)',
                              validator: (val) => val == null || val.isEmpty
                                  ? 'Required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: CustomTextFormField(
                              controller: _countryController,
                              labelText: 'Country (Required)',
                              validator: (val) => val == null || val.isEmpty
                                  ? 'Required'
                                  : null,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      Text(
                        'Additional Info',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const SizedBox(height: 16),

                      CustomTextFormField(
                        controller: _phoneController,
                        labelText: 'Phone Number (Optional)',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),

                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _birthday ?? DateTime.now(),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) setState(() => _birthday = date);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Birthday (Optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLowest,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            prefixIcon: const Icon(Icons.cake_outlined),
                          ),
                          child: Text(
                            _birthday != null
                                ? _birthday!.toLocal().toString().split(' ')[0]
                                : 'Select Date',
                            style: _birthday != null
                                ? Theme.of(context).textTheme.bodyMedium
                                : Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).hintColor,
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      Text(
                        'Map Pin Customization',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
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
                              profileImageUrl: _existingImageUrl,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Preview',
                              style: Theme.of(context).textTheme.bodySmall,
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
                                int.parse(_pinColor.replaceFirst('#', '0xFF')),
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
                        onChanged: (val) => setState(() => _pinStyle = val!),
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
                          DropdownMenuItem(value: 'none', child: Text('None')),
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
                        onChanged: (val) => setState(() => _pinIconType = val!),
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

                      const SizedBox(height: 40),

                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _save,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Save Person',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24), // Bottom padding
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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
