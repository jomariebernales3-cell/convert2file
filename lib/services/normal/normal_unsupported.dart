class NormalUnsupported implements Exception {
  final String sourceExt;
  final String targetExt;
  final String? message;

  const NormalUnsupported(
    this.sourceExt,
    this.targetExt, {
    this.message,
  });

  @override
  String toString() => message ??
      'Normal mode does not support $sourceExt to $targetExt.';
}
