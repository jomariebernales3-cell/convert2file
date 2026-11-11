import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'report_problem_sheet.dart';

Future<void> openReportProblem(
  BuildContext context, {
  required String area,
  Map<String, dynamic> contextInfo = const {},
  String? sourceFilePath,
  String? outputFilePath,
}) =>
    showReportProblemSheet(
      context,
      area: area,
      contextInfo: contextInfo,
      sourceFilePath: sourceFilePath,
      outputFilePath: outputFilePath,
    );

class ReportProblemEntry extends StatelessWidget {
  const ReportProblemEntry({
    super.key,
    required this.area,
    this.label = 'Report a problem',
    this.prompt,
    this.contextInfo = const {},
    this.sourceFilePath,
    this.outputFilePath,
  });

  final String area;
  final String label;
  final String? prompt;
  final Map<String, dynamic> contextInfo;
  final String? sourceFilePath;
  final String? outputFilePath;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.of(context).muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prompt != null) ...[
          Text(prompt!, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 2),
        ],
        SizedBox(
          height: 48,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: muted, minimumSize: const Size(48, 48), tapTargetSize: MaterialTapTargetSize.padded),
            onPressed: () => openReportProblem(context, area: area, contextInfo: contextInfo, sourceFilePath: sourceFilePath, outputFilePath: outputFilePath),
            icon: const Icon(Icons.flag_outlined, size: 17),
            label: Text(label),
          ),
        ),
      ],
    );
  }
}
