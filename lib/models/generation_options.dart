class GenerationOptions {
  final List<String> selectedFormats;
  final String styleProfile;
  final String outputName;
  final String fontFamily;
  final String paperSize;
  final String pageOrientation;
  final String marginPreset;
  final double lineSpacing;
  final String warningAction;
  final bool summarize;
  final bool cleanGrammar;
  final bool includeImages;
  final bool includeTables;
  final bool preserveSourceTableFormat;
  /// Keeps a DOCX-to-DOCX result as the original Office package while no
  /// preview edits have been applied. This preserves symbols, table styling,
  /// image anchors, headers, and other OOXML features that cannot be rebuilt
  /// reliably from plain text.
  final bool preserveSourceLayout;
  final String workspaceMode;

  GenerationOptions({
    this.selectedFormats = const ['docx'],
    this.styleProfile = 'academic',
    this.outputName = '',
    this.fontFamily = 'default',
    this.paperSize = 'a4',
    this.pageOrientation = 'portrait',
    this.marginPreset = 'normal',
    this.lineSpacing = 1.5,
    this.warningAction = 'sanitize',
    this.summarize = false,
    this.cleanGrammar = true,
    this.includeImages = true,
    this.includeTables = true,
    this.preserveSourceTableFormat = true,
    this.preserveSourceLayout = true,
    this.workspaceMode = 'direct',
  });

  Map<String, dynamic> toJson() {
    return {
      'selected_formats': selectedFormats,
      'style_profile': styleProfile,
      'output_name': outputName,
      'font_family': fontFamily,
      'paper_size': paperSize,
      'page_orientation': pageOrientation,
      'margin_preset': marginPreset,
      'line_spacing': lineSpacing,
      'warning_action': warningAction,
      'summarize': summarize,
      'clean_grammar': cleanGrammar,
      'include_images': includeImages,
      'include_tables': includeTables,
      'preserve_source_table_format': preserveSourceTableFormat,
      'preserve_source_layout': preserveSourceLayout,
      'workspace_mode': workspaceMode,
    };
  }

  factory GenerationOptions.fromJson(Map<String, dynamic> json) {
    return GenerationOptions(
      selectedFormats: List<String>.from(json['selected_formats'] as List? ?? ['docx']),
      styleProfile: json['style_profile'] as String? ?? 'academic',
      outputName: json['output_name'] as String? ?? '',
      fontFamily: json['font_family'] as String? ?? 'default',
      paperSize: json['paper_size'] as String? ?? 'a4',
      pageOrientation: json['page_orientation'] as String? ?? 'portrait',
      marginPreset: json['margin_preset'] as String? ?? 'normal',
      lineSpacing: (json['line_spacing'] as num?)?.toDouble() ?? 1.5,
      warningAction: json['warning_action'] as String? ?? 'sanitize',
      summarize: json['summarize'] as bool? ?? false,
      cleanGrammar: json['clean_grammar'] as bool? ?? true,
      includeImages: json['include_images'] as bool? ?? true,
      includeTables: json['include_tables'] as bool? ?? true,
      preserveSourceTableFormat:
          json['preserve_source_table_format'] as bool? ?? true,
      preserveSourceLayout: json['preserve_source_layout'] as bool? ?? true,
      workspaceMode: json['workspace_mode'] as String? ?? 'direct',
    );
  }

  List<String> get availableFormats => ['docx', 'pdf', 'html', 'txt'];
  List<String> get availableStyleProfiles => ['academic', 'module', 'clean'];
  List<String> get availableFontFamilies => [
    'default', 'aptos', 'times', 'arial', 'arial_narrow', 'calibri',
    'cambria', 'garamond', 'georgia', 'book_antiqua', 'palatino',
    'tahoma', 'verdana', 'trebuchet', 'century_gothic', 'courier_new'
  ];
  List<String> get availablePaperSizes => ['a4', 'letter', 'legal'];
  List<String> get availableOrientations => ['portrait', 'landscape'];
  List<String> get availableMarginPresets => ['normal', 'narrow', 'wide'];
  List<String> get availableLineSpacings => ['1.15', '1.5', '2'];
  List<String> get availableWarningActions => ['sanitize', 'continue'];
}
