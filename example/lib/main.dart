import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:imaji_install_attribution/imaji_install_attribution.dart';

void main() => runApp(const ExampleApp());

/// Paths this app is willing to open from a referrer. Anything else in
/// `utm_content` is ignored.
const allowedPaths = ['/items/', '/profile/'];

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Install attribution',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const AttributionPage(),
  );
}

class AttributionPage extends StatefulWidget {
  const AttributionPage({super.key});

  @override
  State<AttributionPage> createState() => _AttributionPageState();
}

class _AttributionPageState extends State<AttributionPage> {
  InstallAttributionResult? _result;
  InstallSource? _source;
  bool? _handled;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() => _loading = true);
    final result = await InstallAttribution.read(
      timeout: const Duration(seconds: 10),
    );
    final source = await InstallAttribution.installSource();
    final handled = await InstallAttribution.isHandled();
    if (!mounted) return;
    setState(() {
      _result = result;
      _source = source;
      _handled = handled;
      _loading = false;
    });
  }

  void _simulate({String? referrer, InstallAttributionResult? result}) {
    InstallAttribution.debugOverride(
      referrer: referrer,
      result: result,
      clickedAt: DateTime.now().subtract(const Duration(minutes: 3)),
    );
    _read();
  }

  Future<void> _markHandled() async {
    await InstallAttribution.markHandled();
    await _read();
  }

  Future<void> _clearHandled() async {
    await InstallAttribution.clearHandled();
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Where did this install come from?')),
      body: RefreshIndicator(
        onRefresh: _read,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            _ResultCard(result: _result),
            const SizedBox(height: 12),
            _InfoTile(
              title: 'Install source',
              value: _source == null
                  ? 'unknown (iOS, or not readable)'
                  : '${_source!.store.name} '
                        '(${_source!.installerPackage ?? 'no installer'})',
            ),
            _InfoTile(
              title: 'Consume-once marker',
              value: _handled == true ? 'handled' : 'not handled',
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _markHandled,
                  child: const Text('markHandled()'),
                ),
                OutlinedButton(
                  onPressed: _clearHandled,
                  child: const Text('clearHandled()'),
                ),
              ],
            ),
            if (kDebugMode) ...[
              const Divider(height: 32),
              Text(
                'Simulate (debug builds only)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _simulate(
                      referrer:
                          'utm_source=newsletter&utm_medium=email'
                          '&utm_content=%2Fitems%2F42',
                    ),
                    child: const Text('Attributed + deep link'),
                  ),
                  OutlinedButton(
                    onPressed: () => _simulate(
                      referrer: 'utm_source=evil&utm_content=%2Fadmin',
                    ),
                    child: const Text('Link outside allowlist'),
                  ),
                  OutlinedButton(
                    onPressed: () => _simulate(
                      referrer: 'utm_source=google-play&utm_medium=organic',
                    ),
                    child: const Text('Organic'),
                  ),
                  OutlinedButton(
                    onPressed: () => _simulate(
                      referrer: 'utm_source=(not%20set)&utm_medium=(not%20set)',
                    ),
                    child: const Text('(not set)'),
                  ),
                  OutlinedButton(
                    onPressed: () => _simulate(
                      result: const Unavailable(
                        UnavailableReason.timeout,
                        message: 'simulated',
                      ),
                    ),
                    child: const Text('Unavailable(timeout)'),
                  ),
                  TextButton(
                    onPressed: () {
                      InstallAttribution.debugClearOverride();
                      _read();
                    },
                    child: const Text('Real read'),
                  ),
                ],
              ),
            ],
            const Divider(height: 32),
            _InfoTile(
              title: 'Play URL that would produce the first simulation',
              value: PlayStoreUrl.web(
                packageName:
                    'io.github.saimskywalker.imaji_install_attribution_example',
                referrer: const {
                  'utm_source': 'newsletter',
                  'utm_medium': 'email',
                  'utm_content': '/items/42',
                },
              ).toString(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final InstallAttributionResult? result;

  @override
  Widget build(BuildContext context) {
    final (String title, List<String> lines) = switch (result) {
      null => ('Reading…', const <String>[]),
      Attributed(source: AttributionSource.appleAds, :final token) => (
        'Attributed (Apple Ads)',
        ['token: ${token?.substring(0, 24)}… (send it to your server)'],
      ),
      Attributed(:final referrer, :final clickedAt) => (
        'Attributed (Google Play)',
        [
          'referrer: ${referrer?.raw}',
          'utm_source: ${referrer?.utmSource}',
          'clicked at: $clickedAt',
          'deep link: ${referrer?.deepLink(allow: allowedPaths) ?? 'none (not allowlisted)'}',
        ],
      ),
      Organic(:final referrer) => (
        'Organic',
        ['referrer: ${referrer?.raw ?? '(empty)'}'],
      ),
      Unavailable(:final reason, :final message) => (
        'Unavailable(${reason.name})',
        [?message],
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectableText(line),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: SelectableText(value),
  );
}
