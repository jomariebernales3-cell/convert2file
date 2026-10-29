import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/database_helper.dart';
import '../services/auth_service.dart';
import '../widgets/figma_app_chrome.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();

  bool _isSaving = false;
  List<int> _activityCounts = List.filled(7, 0);

  @override
  void initState() {
    super.initState();
    _syncUserFields();
    _loadActivity();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _syncUserFields() {
    final user = _authService.currentUser;
    _nameController.text = user?.name ?? '';
    _bioController.text = user?.bio ?? '';
    _phoneController.text = user?.phone ?? '';
    _locationController.text = user?.location ?? '';
  }

  Future<void> _loadActivity() async {
    final userId = (await _authService.requireLocalUser()).id!;

    final logs = await DatabaseHelper.instance.queryLogsByUser(userId);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final counts = List.filled(7, 0);

    for (final log in logs) {
      final createdAt = DateTime.tryParse(log['created_at'] as String? ?? '');
      if (createdAt == null) continue;

      final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
      final offset = day.difference(start).inDays;
      if (offset >= 0 && offset < counts.length) {
        counts[offset] += 1;
      }
    }

    if (mounted) setState(() => _activityCounts = counts);
  }

  Future<void> _pickProfileImage() async {
    final user = await _authService.requireLocalUser();

    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 900,
    );
    if (image == null) return;

    final docs = await getApplicationDocumentsDirectory();
    final profileDir = Directory('${docs.path}/smart_template/profile_images');
    if (!await profileDir.exists()) {
      await profileDir.create(recursive: true);
    }

    final extension = p.extension(image.path).isEmpty
        ? '.jpg'
        : p.extension(image.path).toLowerCase();
    final targetPath =
        p.join(profileDir.path, 'user_${user.id}_profile$extension');
    await File(image.path).copy(targetPath);

    await _authService.updateProfile(profileImagePath: targetPath);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile image updated')),
      );
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      await _authService.updateProfile(
        name: _nameController.text.trim(),
        bio: _bioController.text.trim(),
        phone: _phoneController.text.trim(),
        location: _locationController.text.trim(),
      );
      await _loadActivity();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: Colors.red, content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    if (user == null) {
      return const FigmaAppShell(
        title: 'Local Profile',
        subtitle: 'Your local system identity',
        selectedIndex: 2,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return FigmaAppShell(
      title: 'Local Profile',
      subtitle: 'Your local system identity',
      selectedIndex: 2,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProfileHeader(),
                const SizedBox(height: 20),
                _buildProfileForm(),
                const SizedBox(height: 20),
                _buildActivityCard(),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          if (_isSaving)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final user = _authService.currentUser!;
    final imagePath = user.profileImagePath;
    final hasImage = imagePath != null && File(imagePath).existsSync();

    return FigmaCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: Theme.of(context).colorScheme.primary,
                backgroundImage: hasImage ? FileImage(File(imagePath)) : null,
                child: hasImage
                    ? null
                    : Text(
                        user.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: IconButton.filled(
                  onPressed: _pickProfileImage,
                  icon: const Icon(Icons.camera_alt, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
                const SizedBox(height: 8),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(user.role.toUpperCase()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileForm() {
    return FigmaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile Info',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bioController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Bio',
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone',
              prefixIcon: Icon(Icons.phone),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Location',
              prefixIcon: Icon(Icons.location_on),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveProfile,
              icon: const Icon(Icons.save),
              label: const Text('SAVE PROFILE'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard() {
    final maxCount = _activityCounts.fold<int>(1, (max, count) {
      return count > max ? count : max;
    });

    return FigmaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Local Activity',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxCount.toDouble() + 1,
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final labels = _dayLabels();
                        final index = value.toInt();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            labels[index],
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < _activityCounts.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: _activityCounts[i].toDouble(),
                          width: 16,
                          borderRadius: BorderRadius.circular(5),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _dayLabels() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    return List.generate(7, (index) {
      final weekday = start.add(Duration(days: index)).weekday;
      return labels[weekday - 1];
    });
  }
}
