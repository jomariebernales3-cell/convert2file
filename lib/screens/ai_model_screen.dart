import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/local_llama_service.dart';
import '../widgets/figma_app_chrome.dart';

class AiModelScreen extends StatefulWidget {
  const AiModelScreen({super.key});

  @override
  State<AiModelScreen> createState() => _AiModelScreenState();
}

class _AiModelScreenState extends State<AiModelScreen> {
  static final _recommendedModelUrl = Uri.parse(
    'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF',
  );

  final _llama = LocalLlamaService.instance;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRecommendedModel() async {
    final opened = await launchUrl(
      _recommendedModelUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw Exception('Could not open the model download page.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _llama,
      builder: (context, _) {
        final modelName = _llama.modelPath == null
            ? 'No model imported'
            : _llama.modelPath!.split(RegExp(r'[\\/]')).last;
        final aiStatusTitle = _llama.isLoaded
            ? 'Llama AI is loaded'
            : _llama.hasModel
                ? 'Llama model is integrated'
                : 'Offline Llama is supported';
        final aiStatusMessage = _llama.isLoaded
            ? '$modelName is active and ready for Study generation.'
            : _llama.hasModel
                ? '$modelName is imported. Tap Load to activate it.'
                : 'Import the recommended GGUF model to activate offline AI.';

        return FigmaAppShell(
          title: 'Offline AI',
          subtitle: 'Llama GGUF model manager',
          selectedIndex: 2,
          showBack: true,
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FigmaCard(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _llama.isLoaded
                                ? Icons.psychology
                                : Icons.memory_outlined,
                            size: 34,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  aiStatusTitle,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  aiStatusMessage,
                                  style: TextStyle(
                                    color: FigmaAppColors.subtext(context),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FigmaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.memory,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Local Llama Model',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(modelName),
                          const SizedBox(height: 6),
                          Text(
                            _llama.status,
                            style: TextStyle(
                                color: FigmaAppColors.subtext(context)),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _busy || _llama.isGenerating
                                  ? null
                                  : () => _run(_llama.importModel),
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Import .gguf Model'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy || !_llama.hasModel
                                      ? null
                                      : () => _run(_llama.loadModel),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Load'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy || !_llama.hasModel
                                      ? null
                                      : () => _run(_llama.clearModel),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Disable/Delete'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FigmaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Compatible GGUF models',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          _modelOption(
                            'Llama 3.2 1B Instruct Q4_K_M',
                            'Recommended. Balanced size, speed, and answer quality.',
                          ),
                          _modelOption(
                            'Llama 3.2 1B Instruct IQ3_M',
                            'Smaller and faster, but answers may be less accurate.',
                          ),
                          _modelOption(
                            'Llama 3.2 3B Instruct Q4_K_M',
                            'Better answers, but much slower and needs more RAM.',
                          ),
                          _modelOption(
                            'Gemma / Phi / Qwen GGUF instruct models',
                            'May work if the file is GGUF, but Llama 3.2 1B is the safest first choice.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FigmaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'How offline AI works',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'The app includes the local AI engine, but not the model file. You download a GGUF model, import it here, then the app loads it from this phone. Study and Home AI prompts are processed locally, so they can work without an online AI API.',
                            style: TextStyle(
                              color: FigmaAppColors.subtext(context),
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Why it is slower than online AI',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Online AI runs on powerful servers. Offline AI runs on your phone CPU/GPU, so generation speed depends on the phone RAM, processor, model size, and how long the source text is. Smaller models are faster, but usually less accurate.',
                            style: TextStyle(
                              color: FigmaAppColors.subtext(context),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FigmaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recommended model',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use a small GGUF model like Llama 3.2 1B Instruct Q4. The app does not include the model file, so the APK stays small.',
                            style: TextStyle(
                                color: FigmaAppColors.subtext(context)),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Recommended file: Llama-3.2-1B-Instruct-Q4_K_M.gguf',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Open the page, go to Files and versions, then tap the exact Q4_K_M .gguf file. If the Download button shows a multiple-file warning, use Copy download link and open that link in your browser. The correct link ends with .gguf.',
                            style: TextStyle(
                              color: FigmaAppColors.subtext(context),
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(_openRecommendedModel),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Open Download Page'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
              if (_busy || _llama.isLoading)
                Container(
                  color: Colors.black45,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _modelOption(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: FigmaAppColors.subtext(context),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
