import '../widgets/bootstrap_icon.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/auth_service.dart';
import '../widgets/figma_app_chrome.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _auth = AuthService();
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _phone = TextEditingController();
  final _location = TextEditingController();
  final _picker = ImagePicker();
  bool _saving = false;
  String? _newImagePath;
  bool _removeImage = false;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    _name.text = user?.name ?? '';
    _bio.text = user?.bio ?? '';
    _phone.text = user?.phone ?? '';
    _location.text = user?.location ?? '';
    for (final controller in [_name, _bio, _phone, _location]) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _bio, _phone, _location]) {
      controller.removeListener(_refresh);
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _changed {
    final user = _auth.currentUser;
    if (user == null) return false;
    return _name.text.trim() != user.name ||
        _bio.text.trim() != (user.bio ?? '') ||
        _phone.text.trim() != (user.phone ?? '') ||
        _location.text.trim() != (user.location ?? '') ||
        _newImagePath != null ||
        _removeImage;
  }

  Future<void> _pickPhoto() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 900,
    );
    if (image == null) return;
    final user = await _auth.requireLocalUser();
    final docs = await getApplicationDocumentsDirectory();
    final directory =
        Directory(p.join(docs.path, 'smart_template/profile_images'));
    if (!await directory.exists()) await directory.create(recursive: true);
    final extension =
        p.extension(image.path).isEmpty ? '.jpg' : p.extension(image.path);
    final destination =
        p.join(directory.path, 'user_${user.id}_profile$extension');
    await File(image.path).copy(destination);
    if (!mounted) return;
    setState(() {
      _newImagePath = destination;
      _removeImage = false;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _auth.updateProfile(
        name: _name.text.trim(),
        bio: _bio.text.trim(),
        phone: _phone.text.trim(),
        location: _location.text.trim(),
        profileImagePath: _newImagePath,
        clearProfileImage: _removeImage,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final imagePath =
        _newImagePath ?? (_removeImage ? null : user?.profileImagePath);
    final hasImage = imagePath != null && File(imagePath).existsSync();
    return FigmaAppShell(
      title: 'Edit profile',
      subtitle: 'Profile details on this device',
      selectedIndex: 2,
      showBack: true,
      showProfile: false,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FigmaCard(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 42,
                            backgroundImage:
                                hasImage ? FileImage(File(imagePath)) : null,
                            child: hasImage
                                ? null
                                : Text(
                                    (_name.text.isEmpty ? 'G' : _name.text[0])
                                        .toUpperCase()),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: IconButton.filled(
                              onPressed: _pickPhoto,
                              icon: const BootstrapIcon.material(
                                  Icons.camera_alt_outlined),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                              onPressed: _pickPhoto,
                              child: const Text('Change photo')),
                          TextButton(
                            onPressed: () => setState(() {
                              _newImagePath = null;
                              _removeImage = true;
                            }),
                            child: const Text('Remove photo'),
                          ),
                        ],
                      ),
                      TextField(
                          controller: _name,
                          maxLength: 80,
                          decoration: const InputDecoration(labelText: 'Name')),
                      TextField(
                          controller: _bio,
                          maxLength: 120,
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: 'Bio')),
                      TextFormField(
                          initialValue: user?.email ?? '',
                          readOnly: true,
                          decoration:
                              const InputDecoration(labelText: 'Email')),
                      TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration:
                              const InputDecoration(labelText: 'Phone')),
                      TextField(
                          controller: _location,
                          decoration:
                              const InputDecoration(labelText: 'Location')),
                      TextFormField(
                          initialValue: user?.role ?? 'user',
                          readOnly: true,
                          decoration: const InputDecoration(
                              labelText: 'Role · set by app admin')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving || !_changed ? null : _save,
                  child: const Text('Save changes'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
          if (_saving)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
