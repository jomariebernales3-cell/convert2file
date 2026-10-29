import 'package:flutter/material.dart';

import '../services/app_share_service.dart';

class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  static const _releaseNotesPerPage = 6;
  static const _releaseGridColumnCount = 2;

  int _selectedAdditionalInfoIndex = 0;
  int _selectedReleaseIndex = 0;
  int _releasePage = 0;

  static const _additionalInfo = [
    _AdditionalInfo(
      title: 'App Purpose',
      icon: Icons.flag,
      details: [
        'Convert2File helps create structured academic documents from uploaded source files.',
        'It focuses on direct file conversion, study guide creation, and quiz generation.',
      ],
    ),
    _AdditionalInfo(
      title: 'Supported Files',
      icon: Icons.file_present,
      details: [
        'PDF, DOCX, and PPTX files can be used as source uploads.',
        'Generated outputs can be previewed before saving or sharing.',
      ],
    ),
    _AdditionalInfo(
      title: 'Privacy',
      icon: Icons.privacy_tip,
      details: [
        'Convert2File runs in local-only mode without online accounts.',
        'Uploaded files, generated outputs, history, profile details, bug reports, and theme preferences are stored on this device.',
      ],
    ),
    _AdditionalInfo(
      title: 'Credits',
      icon: Icons.person,
      details: [
        'Created by Despair(0_0).',
        'Built with Flutter and local SQLite storage through sqflite.',
      ],
    ),
    _AdditionalInfo(
      title: 'Capabilities',
      icon: Icons.auto_awesome,
      details: [
        'Create converts one source file into a structured output. It is fastest for readable PDFs, DOCX, TXT, and PPTX materials, but complex layouts, formulas, and scanned pages may need review.',
        'Study Builder lets you create manual reviewers or auto-generate editable quiz drafts from a file, topic, or link.',
        'Preview & Export shows generated sections, tables, images, and formula references before saving. Edits made in preview can regenerate selected outputs.',
        'History keeps saved uploads and outputs on the device so files can be opened, downloaded, shared, inspected, or removed later.',
        'Bug Report saves details, screenshots, and workflow files locally for review. Attach only files needed to reproduce the problem.',
        'Share App sends the installed APK file directly when Android exposes an installable APK path.',
      ],
    ),
    _AdditionalInfo(
      title: 'Disclaimer',
      icon: Icons.info,
      details: [
        'Generated documents are approximate structured outputs.',
        'Review the final document before submitting or sharing it.',
      ],
    ),
  ];

  static const _releaseNotes = [
    _ReleaseNote(
      version: '1.0.26.29',
      date: 'August 13, 2026',
      isLatest: true,
      features: [
        'Switched the app to local-only mode with no online account screens.',
        'Made profile, history, saved files, study sets, and bug reports use the local device user automatically.',
      ],
      fixes: [
        'Removed online startup initialization so the app can open without account checks.',
        'Cleaned drawer and settings actions that pointed users to account actions.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.25.28',
      date: 'June 4, 2026',
      features: [
        'Audited the Direct Workspace extraction pipeline after external file changes.',
      ],
      fixes: [
        'Prevented DOCX table rows from being duplicated when paragraph parsing already detected them.',
        'Replaced regex-only DOCX table extraction with structured XML parsing.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.24.27',
      date: 'June 4, 2026',
      features: [
        'Improved Direct Workspace DOCX extraction for academic instruction files and generated DOCX sources.',
      ],
      fixes: [
        'Preserved DOCX paragraph boundaries instead of collapsing the whole document into one line.',
        'Preserved DOCX table rows as tab-separated lines for better table detection during extraction.',
        'Cleaned control punctuation before parsing DOCX XML so generated DOCX sources remain readable.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.23.26',
      date: 'June 4, 2026',
      features: [
        'Added Direct Workspace PDF extraction notes so users are warned when designed PDF layouts may need manual review.',
      ],
      fixes: [
        'Removed repeated PDF header and footer text during Direct Workspace PDF extraction.',
        'Recorded when repeated PDF header/footer text was detected and removed from the generated output.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.22.25',
      date: 'June 4, 2026',
      features: [
        'Added PDF-to-DOCX comparison QA notes from the IM1 final project instruction file review.',
      ],
      fixes: [
        'Cleaned PDF-extracted control punctuation before generated DOCX XML is written.',
        'Reduced false formula warnings for URLs and grade percentage ranges.',
        'Fixed standalone numbering so item numbers do not carry into unrelated lines.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.21.24',
      date: 'June 3, 2026',
      features: [
        'Added formula-aware handling so detected equations are preserved as exact formula blocks in preview, copy text, DOCX, HTML, and TXT outputs.',
        'Expanded App Info tool explanations with clearer descriptions, expected use, and limitations.',
      ],
      fixes: [
        'Shared output files now keep the assigned custom file name instead of exposing the stored default name.',
        'Share App now prepares a clearer installable APK filename and uses the Android public APK source path.',
        'Settings About version text is now centered with the file icon and updated to the latest version.',
        'Added formula detection review notes for math-like lines that need manual checking.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.20.23',
      date: 'May 26, 2026',
      features: [
        'Added password reset support to the former account screen.',
        'Restored the former admin console exit action as an icon-only top-bar button.',
      ],
      fixes: [
        'Fixed the password reset cancel crash caused by the reset email field controller lifecycle.',
        'Removed the duplicate text exit button beside the former admin console header.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.19.22',
      date: 'May 25, 2026',
      features: [
        'Improved DOCX output formatting to better match the original system output style.',
        'Added preview image/table edit regeneration controls.',
        'Added admin and history pagination, history open/download/share actions, and admin date-range file deletion.',
        'Added History search, date filtering, result count, and sort controls for saved files.',
        'Added complaint mode selection with required bug report file attachments.',
      ],
      fixes: [
        'Custom output names now carry through to downloaded filenames.',
        'Preview export actions now use compact icon-only controls.',
        'Preview copy now copies the generated output text instead of only the file path.',
        'Filtered repeated small logo/icon images from generated DOCX outputs.',
        'Added safer guest file ownership handling for logged-out generation.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.18.21',
      date: 'May 25, 2026',
      features: [
        'Enabled Android internet access for the former online account mode.',
      ],
      fixes: [
        'Fixed release account failures caused by missing Android INTERNET permission.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.17.20',
      date: 'May 25, 2026',
      features: [
        'Added clearer account error messages.',
      ],
      fixes: [
        'Replaced raw statusCode-only auth failures with readable account, confirmation, and rate-limit guidance.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.16.19',
      date: 'May 25, 2026',
      features: [
        'Changed Share App to send the installed Convert2File APK file directly.',
        'Added Android APK path sharing support through a native method channel.',
      ],
      fixes: [
        'Replaced the unpublished Play Store share link with direct APK sharing.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.15.18',
      date: 'May 24, 2026',
      features: [
        'Added Share App action in the hamburger menu.',
        'Added share controls to the App Info page.',
      ],
      fixes: [
        'Prepared a single share service so the app share text can be changed in one place.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.14.17',
      date: 'May 24, 2026',
      features: [
        'Added the former online account database for user profile data.',
        'Kept a local SQLite user mirror so existing history, files, and logs can continue using local user IDs.',
        'Added local database migration support for former online user IDs.',
      ],
      fixes: [
        'Preserved local history, files, and logs while moving account authentication online.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.13.16',
      date: 'May 24, 2026',
      features: [
        'Moved workspace labels into the page header.',
        'Added the Convert2File app name beside the drawer logo.',
        'Changed Update History version buttons to a three-row, two-column layout while keeping pagination.',
      ],
      fixes: [
        'Improved hamburger menu text and icon contrast in Day theme.',
        'Removed duplicated workspace title placement from the dashboard body.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.12.15',
      date: 'May 24, 2026',
      features: [
        'Simplified dashboard upload card titles by removing step prefixes.',
      ],
      fixes: [
        'Kept upload labels consistent after removing Step 1 and Step 2 wording.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.11.14',
      date: 'May 20, 2026',
      features: [
        'Updated password visibility icon behavior in the former account screen.',
      ],
      fixes: [
        'Fixed swapped show/hide eye icons on password fields.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.10.13',
      date: 'May 20, 2026',
      features: [
        'Renamed the app to Convert2File across visible app labels and metadata.',
        'Expanded theme accent support across dashboard, settings, and app info controls.',
      ],
      fixes: [
        'Theme selections now visibly change more app colors.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.9.12',
      date: 'May 20, 2026',
      features: [
        'Renamed the app to Convert2File across visible app metadata.',
        'Connected theme choices to more app accent UI elements.',
      ],
      fixes: [
        'Theme color changes now visibly update selected controls and main accent elements.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.8.11',
      date: 'May 20, 2026',
      features: [
        'Made Day, DBZ, and Night selections mutually exclusive.',
        'Changed visible app version formatting to dot-only style.',
      ],
      fixes: [
        'Theme controls no longer show stale selected states.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.7.10',
      date: 'May 20, 2026',
      features: [
        'Moved DBZ theme between Day and Night in Settings.',
        'Changed theme controls into a separate expandable button section.',
        'Made accent controls independent from the DBZ theme.',
      ],
      fixes: [
        'Theme choices now use limited preset prime color combinations.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.6.9',
      date: 'May 20, 2026',
      features: [
        'Changed Update History to show version buttons.',
        'Added DBZ theme based on the logo colors.',
        'Added DBZ-inspired theme choices in Settings.',
      ],
      fixes: [
        'Latest update details now show by default while older versions stay collapsed until clicked.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.5.8',
      date: 'May 20, 2026',
      features: [
        'Added App Info page in the hamburger menu.',
        'Added creator, project start date, and version update history.',
      ],
      fixes: [
        'Prepared a single place to record feature and bug-fix notes per version.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.4.7',
      date: 'May 20, 2026',
      features: [
        'Set Direct Workspace as the default app view.',
        'Moved workspace choices below the user header outside the dropdown.',
      ],
      fixes: [
        'Updated Android app info versionName/versionCode so phone App Info shows the latest version.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.3.6',
      date: 'May 20, 2026',
      features: [
        'Added separate Profile screen with image upload and editable user info.',
        'Added user activity graph.',
        'Added Day and Night theme controls in Settings.',
      ],
      fixes: [
        'Added database migration for profile fields.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.2.5',
      date: 'May 20, 2026',
      features: [
        'Separated workspace entries in navigation.',
        'Moved workspace access into the hamburger menu.',
      ],
      fixes: [
        'Removed the old in-workspace mode switch.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.1.4',
      date: 'May 20, 2026',
      features: [
        'Added hamburger menu navigation.',
        'Grouped user actions under an expandable user section.',
      ],
      fixes: [
        'Cleaned up dashboard app bar actions.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Info'),
        actions: [
          IconButton(
            tooltip: 'Share App',
            icon: const Icon(Icons.share),
            onPressed: _shareApp,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProjectCard(context),
          const SizedBox(height: 20),
          const Text(
            'Additional Info',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildAdditionalInfoSection(context),
          const SizedBox(height: 20),
          const Text(
            'Update History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildVersionButtons(context),
          const SizedBox(height: 12),
          _buildReleaseCard(context, _releaseNotes[_selectedReleaseIndex]),
        ],
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description,
                  color: Theme.of(context).colorScheme.primary, size: 30),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Convert2File',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _InfoRow(label: 'Current Version', value: '1.0.26.29'),
          const _InfoRow(label: 'Created by', value: 'Despair(0_0)'),
          const _InfoRow(label: 'Date Started', value: 'April 15, 2026'),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _shareApp,
              icon: const Icon(Icons.share),
              label: const Text('SHARE APP'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareApp() async {
    try {
      await AppShareService.shareApp();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Share failed: $e'),
        ),
      );
    }
  }

  Widget _buildAdditionalInfoSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAdditionalInfoGrid(context),
        const SizedBox(height: 12),
        _buildAdditionalInfoCard(
          context,
          _additionalInfo[_selectedAdditionalInfoIndex],
        ),
      ],
    );
  }

  Widget _buildAdditionalInfoGrid(BuildContext context) {
    final rows = <Widget>[];

    for (var i = 0; i < _additionalInfo.length; i += 2) {
      rows.add(
        Padding(
          padding:
              EdgeInsets.only(bottom: i + 2 < _additionalInfo.length ? 8 : 0),
          child: Row(
            children: [
              Expanded(
                child: _buildAdditionalInfoTile(context, _additionalInfo[i], i),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < _additionalInfo.length
                    ? _buildAdditionalInfoTile(
                        context,
                        _additionalInfo[i + 1],
                        i + 1,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildAdditionalInfoTile(
    BuildContext context,
    _AdditionalInfo info,
    int index,
  ) {
    final isSelected = _selectedAdditionalInfoIndex == index;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedAdditionalInfoIndex = index),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.24)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              info.icon,
              size: 17,
              color: isSelected
                  ? colorScheme.primary
                  : Theme.of(context).hintColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                info.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionalInfoCard(BuildContext context, _AdditionalInfo info) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(info.icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  info.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildNoteList(context, 'Details', info.details),
        ],
      ),
    );
  }

  Widget _buildVersionButtons(BuildContext context) {
    final pageCount = (_releaseNotes.length / _releaseNotesPerPage).ceil();
    final startIndex = _releasePage * _releaseNotesPerPage;
    final endIndex = (startIndex + _releaseNotesPerPage)
        .clamp(0, _releaseNotes.length)
        .toInt();
    final visibleNotes = _releaseNotes.sublist(startIndex, endIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVersionGrid(context, visibleNotes, startIndex),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildPageButton(
              context,
              label: '<Prev',
              onPressed: _releasePage == 0
                  ? null
                  : () => _changeReleasePage(_releasePage - 1),
            ),
            const SizedBox(width: 8),
            _buildPageButton(
              context,
              label: 'Next>',
              onPressed: _releasePage >= pageCount - 1
                  ? null
                  : () => _changeReleasePage(_releasePage + 1),
            ),
            const Spacer(),
            _buildPageIndicator(context, _releasePage + 1, pageCount),
          ],
        ),
      ],
    );
  }

  Widget _buildVersionGrid(
    BuildContext context,
    List<_ReleaseNote> visibleNotes,
    int startIndex,
  ) {
    final rows = <Widget>[];

    for (var i = 0; i < visibleNotes.length; i += _releaseGridColumnCount) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            bottom: i + _releaseGridColumnCount < visibleNotes.length ? 8 : 0,
          ),
          child: Row(
            children:
                _buildVersionGridRow(context, visibleNotes, startIndex, i),
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  List<Widget> _buildVersionGridRow(
    BuildContext context,
    List<_ReleaseNote> visibleNotes,
    int startIndex,
    int rowStartIndex,
  ) {
    final cells = <Widget>[];

    for (var column = 0; column < _releaseGridColumnCount; column++) {
      final noteIndex = rowStartIndex + column;
      if (column > 0) cells.add(const SizedBox(width: 8));
      cells.add(
        Expanded(
          child: noteIndex < visibleNotes.length
              ? _buildVersionTile(
                  context,
                  visibleNotes[noteIndex],
                  startIndex + noteIndex,
                )
              : const SizedBox.shrink(),
        ),
      );
    }

    return cells;
  }

  Widget _buildVersionTile(
    BuildContext context,
    _ReleaseNote note,
    int releaseIndex,
  ) {
    final isSelected = _selectedReleaseIndex == releaseIndex;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedReleaseIndex = releaseIndex),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.24)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(
                    releaseIndex == 0 ? Icons.new_releases : Icons.history,
                    size: 17,
                    color: isSelected
                        ? colorScheme.primary
                        : Theme.of(context).hintColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      note.version,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (note.isLatest)
              Positioned(
                top: 0,
                right: 0,
                child: CustomPaint(
                  size: const Size(18, 18),
                  painter: _LatestRibbonPainter(colorScheme.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _changeReleasePage(int page) {
    setState(() {
      _releasePage = page;
      _selectedReleaseIndex = page * _releaseNotesPerPage;
    });
  }

  Widget _buildPageButton(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(72, 36),
      ),
      child: Text(label),
    );
  }

  Widget _buildPageIndicator(BuildContext context, int page, int pageCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        'Page $page of $pageCount',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildReleaseCard(BuildContext context, _ReleaseNote note) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Version ${note.version}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                note.date,
                style: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildNoteList(context, 'Features Added', note.features),
          const SizedBox(height: 10),
          _buildNoteList(context, 'Bug Fixes / Updates', note.fixes),
        ],
      ),
    );
  }

  Widget _buildNoteList(
    BuildContext context,
    String title,
    List<String> entries,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('- '),
                Expanded(
                  child: Text(
                    entry,
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  BoxDecoration _panelDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(context).dividerColor),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestRibbonPainter extends CustomPainter {
  final Color color;

  const _LatestRibbonPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LatestRibbonPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _AdditionalInfo {
  final String title;
  final IconData icon;
  final List<String> details;

  const _AdditionalInfo({
    required this.title,
    required this.icon,
    required this.details,
  });
}

class _ReleaseNote {
  final String version;
  final String date;
  final bool isLatest;
  final List<String> features;
  final List<String> fixes;

  const _ReleaseNote({
    required this.version,
    required this.date,
    this.isLatest = false,
    required this.features,
    required this.fixes,
  });
}
