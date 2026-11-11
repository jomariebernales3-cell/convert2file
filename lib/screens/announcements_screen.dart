import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/announcement_service.dart';
import '../theme/app_colors.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _service = AnnouncementService();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _service.fetchActive();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Color _kindColor(String kind, AppColors colors) => switch (kind) {
        'important' => colors.warning,
        'maintenance' => colors.muted,
        _ => colors.accent,
      };

  IconData _kindIcon(String kind) => switch (kind) {
        'important' => Icons.priority_high_rounded,
        'maintenance' => Icons.build_circle_outlined,
        _ => Icons.info_outline_rounded,
      };

  Widget _announcementCard(Map<String, dynamic> item) {
    final colors = AppColors.of(context);
    final kind = item['kind']?.toString() ?? 'info';
    final link = Uri.tryParse(item['link_url']?.toString() ?? '');
    final hasSafeLink = link != null &&
        link.scheme.toLowerCase() == 'https' &&
        link.host.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: _kindColor(kind, colors)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(_kindIcon(kind), size: 24, color: _kindColor(kind, colors)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item['title']?.toString() ?? 'Announcement',
                          style: TextStyle(color: colors.text, fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(item['body']?.toString() ?? '', style: TextStyle(color: colors.muted)),
                    if (hasSafeLink) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => launchUrl(link, mode: LaunchMode.externalApplication),
                          child: Text(item['link_label']?.toString().trim().isNotEmpty == true
                              ? item['link_label'].toString()
                              : 'Learn more'),
                        ),
                      ),
                    ],
                  ],
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
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    'No announcements right now',
                    style: TextStyle(color: colors.muted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _items.length,
                  itemBuilder: (context, index) => _announcementCard(_items[index]),
                ),
    );
  }
}
