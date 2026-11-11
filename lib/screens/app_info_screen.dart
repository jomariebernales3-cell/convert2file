import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/app_info_service.dart';

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
  List<_AdditionalInfo> _additionalInfo = _defaultAdditionalInfo;
  List<_ReleaseNote> _releaseNotes = _defaultReleaseNotes;

  @override
  void initState() {
    super.initState();
    _loadManagedContent();
  }

  Future<void> _loadManagedContent() async {
    final content = await AppInfoService().fetchContent();
    if (!mounted || content == null) return;
    try {
      final sections = (content['sections'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .map((value) => _AdditionalInfo(
                title: value['title']?.toString() ?? 'Information',
                icon: _iconForKey(value['icon']?.toString()),
                details: (value['details'] as List)
                    .map((detail) => detail.toString())
                    .toList(growable: false),
              ))
          .toList(growable: false);
      final releases = (content['release_notes'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .map((value) => _ReleaseNote(
                version: value['version']?.toString() ?? 'Unknown',
                date: value['date']?.toString() ?? '',
                isLatest: value['is_latest'] == true,
                features: (value['features'] as List)
                    .map((entry) => entry.toString())
                    .toList(growable: false),
                fixes: (value['fixes'] as List)
                    .map((entry) => entry.toString())
                    .toList(growable: false),
              ))
          .toList(growable: false);
      if (sections.isEmpty || releases.isEmpty) return;
      setState(() {
        _additionalInfo = sections;
        _releaseNotes = releases;
        _selectedAdditionalInfoIndex = 0;
        _selectedReleaseIndex = releases.indexWhere((note) => note.isLatest);
        if (_selectedReleaseIndex < 0) _selectedReleaseIndex = 0;
        _releasePage = _selectedReleaseIndex ~/ _releaseNotesPerPage;
      });
    } catch (_) {
      // Keep the bundled copy available if an incomplete online record is returned.
    }
  }

  IconData _iconForKey(String? key) => switch (key) {
        'school' => Icons.school_outlined,
        'files' => Icons.file_present_outlined,
        'privacy' => Icons.privacy_tip_outlined,
        'credits' => Icons.groups_outlined,
        'capabilities' => Icons.auto_awesome_outlined,
        'disclaimer' => Icons.info_outline,
        _ => Icons.info_outline,
      };

  String get _latestVersion => _releaseNotes
      .firstWhere((note) => note.isLatest, orElse: () => _releaseNotes.first)
      .version;

  static const _defaultAdditionalInfo = [
    _AdditionalInfo(
      title: 'App Purpose',
      icon: Icons.school_outlined,
      details: [
        'Convert2File helps students and teachers turn lesson files and notes into usable documents, study guides, and quiz drafts on Android.',
        'It combines on-device tools with optional online account and service features. You can also use a local guest workspace.',
      ],
    ),
    _AdditionalInfo(
      title: 'Supported Files',
      icon: Icons.file_present,
      details: [
        'Source files: PDF, DOCX, PPTX, legacy PPT, and TXT. Legacy PPT files have limited extraction support.',
        'Create and conversion outputs: DOCX, PDF, HTML, and TXT. QR codes can be saved as PNG images.',
        'Scanned or image-only PDFs may have little or no extractable text because OCR is not currently provided. Complex layouts may change during conversion.',
      ],
    ),
    _AdditionalInfo(
      title: 'Privacy',
      icon: Icons.privacy_tip,
      details: [
        'Selected source files are processed by the app and saved materials/history are stored on this device. Core conversion does not upload your documents to Convert2File storage.',
        'If you sign in, Supabase handles account authentication and account profile data. The app also connects to Supabase for announcements, app controls, and submitted problem reports.',
        'Problem reports are sent to the Convert2File project. Depending on your choices, a report may include your description, email, app/device details, technical context, and attached files. Chosen attachments are uploaded to private report storage.',
        'Guest workspace files stay on this device. Web links and online services need an internet connection; offline AI runs on-device after you import a compatible model.',
      ],
    ),
    _AdditionalInfo(
      title: 'Credits',
      icon: Icons.groups_outlined,
      details: [
        'Project creator: Despair(0_0).',
        'Built with Flutter and Dart. Local workspace data uses SQLite; account and app-management services use Supabase.',
        'Development was AI-assisted with OpenAI Codex. The project creator is responsible for the app and its published content.',
      ],
    ),
    _AdditionalInfo(
      title: 'Capabilities',
      icon: Icons.auto_awesome_outlined,
      details: [
        'Convert documents, create files from typed text, build study guides, and draft quizzes. Review generated content and formatting before using it.',
        'Study guides and quizzes can be created manually. AI-assisted actions require a compatible GGUF model imported on the device; model output can be incorrect.',
        'The QR tool scans codes and creates QR images. Camera access is needed for scanning.',
        'My Materials and History let you find and manage locally saved files and outputs. Android may ask for permission when saving images or accessing selected files.',
        'Sharing offers the installed APK when Android exposes it, the public website link, or a QR code for that link. Installing APKs may require Android to allow installs from the app you use to open the file.',
        'Online source links require internet access. Offline AI is performed on the device with the imported model, but speed and quality depend on the phone and model.',
      ],
    ),
    _AdditionalInfo(
      title: 'Disclaimer',
      icon: Icons.info,
      details: [
        'Conversion and extraction can omit or rearrange content, especially in scanned PDFs, complex layouts, tables, and formulas. OCR is not available in this build.',
        'AI-generated summaries, study guides, and quiz drafts may contain mistakes or invented details. Check facts, answers, and source material yourself.',
        'Convert2File is a study and document utility, not a substitute for professional advice or the original course material. Review outputs before relying on, submitting, or sharing them.',
      ],
    ),
  ];

  static const _defaultReleaseNotes = [
    _ReleaseNote(
      version: '1.0.26.29',
      date: 'Current build',
      isLatest: true,
      features: [
        'Refreshed App Info with current supported formats, privacy disclosures, capabilities, and limitations.',
        'Added APK, website-link, and QR-code choices to Share App in Settings.',
      ],
      fixes: [
        'Corrected outdated text that described the app as local-only while it still uses Supabase for online services.',
        'Updated the release notes to reflect the current account, guest, and online-service behavior.',
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
      ],
      fixes: [
        'Fixed the password reset cancel crash caused by the reset email field controller lifecycle.',
      ],
    ),
    _ReleaseNote(
      version: '1.0.19.22',
      date: 'May 25, 2026',
      features: [
        'Improved DOCX output formatting to better match the original system output style.',
        'Added preview image/table edit regeneration controls.',
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
            tooltip: 'Refresh App Info',
            onPressed: _loadManagedContent,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _buildProjectCard(context),
          const SizedBox(height: 24),
          _buildSectionHeading(context, 'About the app', 'Purpose, formats, data use, and limitations'),
          const SizedBox(height: 12),
          _buildAdditionalInfoSection(context),
          const SizedBox(height: 24),
          _buildSectionHeading(context, 'Update history', 'What has changed across app versions'),
          const SizedBox(height: 12),
          _buildVersionButtons(context),
          const SizedBox(height: 12),
          _buildReleaseCard(context, _releaseNotes[_selectedReleaseIndex]),
        ],
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.description_outlined, color: colors.accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Convert2File', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('Documents and study tools for Android', style: TextStyle(color: colors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metaChip(context, Icons.new_releases_outlined, 'Latest release $_latestVersion'),
              _metaChip(context, Icons.person_outline, 'Despair(0_0)'),
              _metaChip(context, Icons.code, 'Flutter · Dart'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Convert lesson files into editable documents and study resources. Choose a section below for details about formats, privacy, and limitations.',
            style: TextStyle(color: colors.muted, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(BuildContext context, IconData icon, String text) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.accent),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: colors.text, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSectionHeading(BuildContext context, String title, String subtitle) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(color: colors.muted)),
      ],
    );
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _additionalInfo.length; i++)
          _buildAdditionalInfoTile(context, _additionalInfo[i], i),
      ],
    );
  }

  Widget _buildAdditionalInfoTile(
    BuildContext context,
    _AdditionalInfo info,
    int index,
  ) {
    final isSelected = _selectedAdditionalInfoIndex == index;
    final colors = AppColors.of(context);

    return Material(
      color: isSelected ? colors.accent.withValues(alpha: 0.16) : colors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _selectedAdditionalInfoIndex = index),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: isSelected ? colors.accent : colors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(info.icon, size: 17, color: isSelected ? colors.accent : colors.muted),
              const SizedBox(width: 7),
              Text(
                info.title,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdditionalInfoCard(BuildContext context, _AdditionalInfo info) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(info.icon, color: colors.accent, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  info.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
    final colors = AppColors.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedReleaseIndex = releaseIndex),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.accent.withValues(alpha: 0.16)
              : colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? colors.accent : colors.line),
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
                    color: isSelected ? colors.accent : colors.muted,
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
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Version ${note.version}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                note.date,
                style: TextStyle(
                  color: colors.muted,
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
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 9),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.of(context).accent,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry,
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      height: 1.45,
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
    final colors = AppColors.of(context);
    return BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: colors.line),
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
