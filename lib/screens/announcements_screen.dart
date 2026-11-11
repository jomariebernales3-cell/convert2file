import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/announcement_service.dart';
import '../services/supabase_config.dart';
import '../theme/app_colors.dart';

enum _AnnouncementFilter { all, unread }

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _service = AnnouncementService();
  final Set<String> _removing = {};
  List<Map<String, dynamic>> _items = const [];
  Set<String> _readIds = {};
  Set<String> _hiddenIds = {};
  String? _openId;
  _AnnouncementFilter _filter = _AnnouncementFilter.all;
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToChanges();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.fetchActive(forceRefresh: true),
      _service.seenIds(),
      _service.dismissedIds(),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<Map<String, dynamic>>;
      _readIds = results[1] as Set<String>;
      _hiddenIds = results[2] as Set<String>;
      _loading = false;
    });
  }

  void _subscribeToChanges() {
    if (!SupabaseConfig.isConfigured) return;
    _channel = Supabase.instance.client
        .channel('announcements-screen-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'announcements',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  String _id(Map<String, dynamic> item) => item['id']?.toString() ?? '';

  bool _isRead(Map<String, dynamic> item) => _readIds.contains(_id(item));

  Color _kindColor(String kind, AppColors colors) => switch (kind) {
        'important' => colors.warning,
        'maintenance' => colors.muted,
        _ => colors.accent,
      };

  IconData _kindIcon(String kind) => switch (kind) {
        'important' => Icons.priority_high_rounded,
        'maintenance' => Icons.build_circle_outlined,
        _ => Icons.campaign_outlined,
      };

  String _kindLabel(String kind) => switch (kind) {
        'important' => 'Important',
        'maintenance' => 'Maintenance',
        _ => 'News',
      };

  String _relativeDate(Map<String, dynamic> item) {
    final raw = item['created_at'] ?? item['starts_at'];
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  List<Map<String, dynamic>> get _visibleItems => _items
      .where((item) => !_hiddenIds.contains(_id(item)))
      .where((item) =>
          _filter == _AnnouncementFilter.all || !_isRead(item))
      .toList(growable: false);

  Future<void> _markRead(Map<String, dynamic> item) async {
    final id = _id(item);
    if (_readIds.contains(id)) return;
    setState(() {
      _readIds.add(id);
    });
    await _service.markSeen([id]);
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final colors = AppColors.of(context);
    final shouldDelete = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Delete this announcement?',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 6),
              Text('It will be removed from this device only. This can’t be undone.',
                  style: TextStyle(color: colors.muted, height: 1.5)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: _actionStyle(foreground: colors.accent),
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: _actionStyle(foreground: colors.danger),
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('Delete'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (shouldDelete != true || !mounted) return;

    final id = _id(item);
    setState(() => _removing.add(id));
    await Future<void>.delayed(const Duration(milliseconds: 260));
    await _service.dismiss(id);
    if (!mounted) return;
    setState(() {
      _hiddenIds.add(id);
      _removing.remove(id);
      if (_openId == id) _openId = null;
    });
  }

  ButtonStyle _actionStyle({required Color foreground}) =>
      OutlinedButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: foreground),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        visualDensity: VisualDensity.standard,
      );

  TextSpan _inlineMarkdown(String text, TextStyle base, AppColors colors) {
    final spans = <TextSpan>[];
    final expression = RegExp(r'\*\*(.+?)\*\*');
    var cursor = 0;
    for (final match in expression.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: base.copyWith(fontWeight: FontWeight.w800, color: colors.text),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: base, children: spans);
  }

  Widget _formattedMessage(String message, AppColors colors) {
    final baseStyle = TextStyle(color: colors.text, fontSize: 15, height: 1.6);
    final blocks = <Widget>[];
    var paragraph = <String>[];
    var bullets = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 10),
        child: Text.rich(_inlineMarkdown(paragraph.join(' '), baseStyle, colors)),
      ));
      paragraph = [];
    }

    void flushBullets() {
      if (bullets.isEmpty) return;
      blocks.add(Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: bullets.map((line) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 9),
                child: Icon(Icons.circle, size: 6, color: colors.accent),
              ),
              Expanded(child: Text.rich(_inlineMarkdown(line, baseStyle, colors))),
            ]),
          )).toList(),
        ),
      ));
      bullets = [];
    }

    for (final line in message.replaceAll('\r\n', '\n').split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushParagraph();
        flushBullets();
      } else if (trimmed.startsWith('- ')) {
        flushParagraph();
        bullets.add(trimmed.substring(2));
      } else {
        flushBullets();
        paragraph.add(trimmed);
      }
    }
    flushParagraph();
    flushBullets();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }

  Widget _announcementCard(Map<String, dynamic> item) {
    final colors = AppColors.of(context);
    final id = _id(item);
    final kind = item['kind']?.toString() ?? 'info';
    final kindColor = _kindColor(kind, colors);
    final isOpen = _openId == id;
    final isRead = _isRead(item);
    final isRemoving = _removing.contains(id);
    final title = item['title']?.toString() ?? 'Announcement';
    final body = item['body']?.toString() ?? item['message']?.toString() ?? '';
    final link = Uri.tryParse(item['link_url']?.toString() ?? '');
    final hasSafeLink = link != null &&
        link.scheme.toLowerCase() == 'https' &&
        link.host.isNotEmpty;
    final preview = body
        .replaceAll(RegExp(r'\*\*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('- ', '')
        .trim();

    return AnimatedSlide(
      key: ValueKey(id),
      offset: isRemoving ? const Offset(0.08, 0) : Offset.zero,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: AnimatedOpacity(
        opacity: isRemoving ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.line),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (!isRead)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 3,
                    color: colors.accent,
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(left: !isRead ? 3 : 0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        button: true,
                        expanded: isOpen,
                        label: '$title, ${_kindLabel(kind)}, ${isRead ? 'read' : 'unread'}, ${_relativeDate(item)}',
                        hint: isOpen ? 'Collapse announcement' : 'Expand announcement',
                        child: Material(
                          color: colors.surface,
                          child: InkWell(
                            onTap: isRemoving
                                ? null
                                : () => setState(() => _openId = isOpen ? null : id),
                            focusColor: colors.accent.withValues(alpha: 0.14),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 72),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: kindColor.withValues(alpha: 0.13),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(_kindIcon(kind), size: 22, color: kindColor),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isRead ? colors.muted : colors.text,
                                              fontSize: 16,
                                              fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                            )),
                                          const SizedBox(height: 2),
                                          Text.rich(TextSpan(children: [
                                            TextSpan(text: '${_kindLabel(kind)}  ', style: TextStyle(color: kindColor, fontWeight: FontWeight.w700)),
                                            TextSpan(text: _relativeDate(item), style: TextStyle(color: colors.muted)),
                                          ]), maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12)),
                                          if (!isOpen) ...[
                                            const SizedBox(height: 2),
                                            Text(preview,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: colors.muted, fontSize: 13)),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!isRead)
                                      Semantics(label: 'Unread', child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
                                      )),
                                    const SizedBox(width: 8),
                                    AnimatedRotation(
                                      turns: isOpen ? 0.5 : 0,
                                      duration: const Duration(milliseconds: 280),
                                      child: Icon(Icons.keyboard_arrow_down_rounded, color: colors.muted, size: 24),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.hardEdge,
                        child: isOpen
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Divider(height: 1, color: colors.line),
                                    _formattedMessage(body, colors),
                                    if (hasSafeLink)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          onPressed: () => launchUrl(
                                            link!,
                                            mode: LaunchMode.externalApplication,
                                          ),
                                          style: TextButton.styleFrom(
                                            minimumSize: const Size(48, 48),
                                            foregroundColor: colors.accent,
                                          ),
                                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                          label: Text(
                                            item['link_label']?.toString().trim().isNotEmpty == true
                                                ? item['link_label'].toString()
                                                : 'Learn more',
                                          ),
                                        ),
                                      ),
                                    Row(children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: _actionStyle(foreground: isRead ? colors.muted : colors.accent),
                                          onPressed: isRead || isRemoving ? null : () => _markRead(item),
                                          icon: Icon(isRead ? Icons.check_rounded : Icons.done_rounded, size: 18),
                                          label: Text(isRead ? 'Read' : 'Mark as read'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: _actionStyle(foreground: colors.danger),
                                          onPressed: !isRead || isRemoving ? null : () => _confirmDelete(item),
                                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                          label: const Text('Delete'),
                                        ),
                                      ),
                                    ]),
                                    if (!isRead)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text('Mark as read to unlock Delete',
                                            style: TextStyle(color: colors.muted, fontSize: 12)),
                                      ),
                                  ],
                                ),
                              )
                            : const SizedBox(width: double.infinity, height: 0),
                      ),
                    ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final visibleItems = _visibleItems;
    final unreadCount = _items
        .where((item) => !_hiddenIds.contains(_id(item)) && !_isRead(item))
        .length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Announcements'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Semantics(
                label: unreadCount == 0 ? 'All read' : '$unreadCount unread',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    unreadCount == 0 ? 'All read' : '$unreadCount unread',
                    style: TextStyle(color: colors.accent, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 8, children: [
                      _filterChip('All', _AnnouncementFilter.all, colors),
                      _filterChip('Unread', _AnnouncementFilter.unread, colors),
                    ]),
                  ),
                ),
                Expanded(
                  child: visibleItems.isEmpty
                      ? _emptyState(colors)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: visibleItems.length,
                          itemBuilder: (context, index) => _announcementCard(visibleItems[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _filterChip(String label, _AnnouncementFilter filter, AppColors colors) {
    final selected = _filter == filter;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label announcements',
      child: Focus(
        child: Builder(builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return OutlinedButton(
            onPressed: () => setState(() {
              _filter = filter;
              if (filter == _AnnouncementFilter.unread &&
                  _openId != null &&
                  !_items.any((item) => _id(item) == _openId && !_isRead(item))) {
                _openId = null;
              }
            }),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              foregroundColor: selected ? colors.accentInk : colors.muted,
              backgroundColor: selected ? colors.accent : colors.surface,
              side: BorderSide(color: focused ? colors.accent : selected ? colors.accent : colors.line, width: focused ? 2 : 1),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: Text(label),
          );
        }),
      ),
    );
  }

  Widget _emptyState(AppColors colors) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.campaign_outlined, size: 48, color: colors.accent),
              const SizedBox(height: 12),
              Text('No announcements',
                  style: TextStyle(color: colors.text, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('New messages from the admin will show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted, height: 1.5)),
            ],
          ),
        ),
      );
}
