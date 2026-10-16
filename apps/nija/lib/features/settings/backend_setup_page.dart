import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nija/features/settings/backend_form.dart';
import 'package:nija/features/sync/sync_controller.dart';
import 'package:nija/providers.dart';
import 'package:nija/ui/app_theme.dart';
import 'package:nija/ui/widgets/section_card.dart';
import 'package:nija_core/nija_core.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pick a database, fill its form, test, verify schema, save.
/// Used both by onboarding and from Settings.
class BackendSetupPage extends ConsumerStatefulWidget {
  /// Creates the page. [onboarding] hides the back button and marks
  /// onboarding done on save.
  const BackendSetupPage({this.onboarding = false, super.key});

  /// Wizard mode.
  final bool onboarding;

  @override
  ConsumerState<BackendSetupPage> createState() => _BackendSetupPageState();
}

class _BackendSetupPageState extends ConsumerState<BackendSetupPage> {
  final _formKey = GlobalKey<BackendFormState>();
  late String _backendId;
  Map<String, String> _values = {};
  ConnectionCheck? _conn;
  SchemaCheck? _schema;
  bool _busy = false;
  bool _secure = true;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _backendId = s.backendId;
    _values = Map.of(s.backendValues);
  }

  Future<void> _switchBackend(String id) async {
    if (id == _backendId) return;
    final values = await ref
        .read(settingsRepositoryProvider)
        .loadBackendValues(id);
    if (!mounted) return;
    setState(() {
      _backendId = id;
      _values = values;
      _conn = null;
      _schema = null;
    });
  }

  /// Creates the Supabase tables through the Management API with a personal
  /// access token the user pastes once, then tests again.
  Future<void> _autoSetup(String script) async {
    final controller = ref.read(syncControllerProvider.notifier)
      ..holdCapture(held: true);
    final (String, String)? input;
    try {
      input = await showDialog<(String, String)>(
        context: context,
        builder: (_) => _SupabaseTokenDialog(
          projectRef: SupabaseBackend.projectRefOf(_values['url'] ?? ''),
        ),
      );
    } finally {
      controller.holdCapture(held: false);
    }
    if (input == null || !mounted) return;
    final (projectRef, token) = input;
    setState(() => _busy = true);
    try {
      await SupabaseBackend.runSetup(
        projectRef: projectRef,
        accessToken: token,
        sql: script,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Database set up. Checking it again.')),
        );
      setState(() => _busy = false);
      await _test();
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _copySetup(String script) async {
    // Not recorded in history: it is setup text, not something the user
    // copied.
    await ref.read(syncControllerProvider.notifier).copyTextUnrecorded(script);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Setup SQL copied. Paste it into the SQL editor, run it, then '
            'test again.',
          ),
        ),
      );
  }

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() {
      _busy = true;
      _conn = null;
      _schema = null;
    });
    final (c, s) = await ref
        .read(syncControllerProvider.notifier)
        .probe(BackendConfig(backendId: _backendId, values: _values));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _conn = c;
      _schema = s;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    final notifier = ref.read(settingsProvider.notifier);
    final previous = ref.read(settingsProvider).backendId;
    if (previous != _backendId) {
      await ref.read(localStoreProvider).resetCursor();
    }
    setState(() => _busy = true);
    await notifier.update(
      (s) => s.copyWith(
        backendId: _backendId,
        backendValues: _values,
        onboarded: true,
      ),
    );
    if (_secure && _backendId != 'memory') {
      try {
        await ref.read(syncControllerProvider.notifier).secureNewGroup();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Saved, but the group could not be secured yet: ${redactSecrets('$e')}. Use Settings → Devices → Secure this group once connected.',
                ),
              ),
            );
        }
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.onboarding) {
      context.go('/');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(backendRegistryProvider);
    final descriptor = registry.descriptor(_backendId)!;
    final theme = Theme.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? 'Choose where to sync' : 'Database'),
        automaticallyImplyLeading: !widget.onboarding,
        leading: widget.onboarding
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go('/onboarding'),
              )
            : null,
      ),
      body: ContentColumn(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text('Pick a database', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'The app connects to it directly, no server in between.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 560 ? 3 : 2;
                return GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // A fixed height, not an aspect ratio: the tiles hold the
                  // same content at every width, and a ratio left them too
                  // short on narrow phones (an overflow at 430 pt wide).
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 120,
                  ),
                  children: [
                    for (final d in registry.descriptors)
                      _BackendTile(
                        key: ValueKey('backend-${d.id}'),
                        descriptor: d,
                        selected: d.id == _backendId,
                        onTap: _busy ? null : () => _switchBackend(d.id),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    descriptor.displayName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (descriptor.id != 'memory')
                  TextButton.icon(
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Setup guide'),
                    onPressed: () => launchUrl(
                      Uri.parse(descriptor.docsUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
              ],
            ),
            Text(descriptor.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: BackendForm(
                  key: ValueKey('form-$_backendId'),
                  descriptor: descriptor,
                  initialValues: _values,
                  onChanged: (v) => _values = v,
                ),
              ),
            ),
            if (descriptor.configSchema.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('test-connection'),
                onPressed: _busy ? null : _test,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check_rounded, size: 18),
                label: Text(_busy ? 'Testing…' : 'Test connection & schema'),
              ),
              if (_conn != null) ...[
                const SizedBox(height: 12),
                _Result(
                  ok: _conn!.ok,
                  title: _conn!.ok ? 'Connected' : 'Connection failed',
                  detail:
                      '${_conn!.message}${_conn!.latency != null ? ' · ${_conn!.latency!.inMilliseconds} ms' : ''}',
                ),
              ],
              if (_schema != null) ...[
                const SizedBox(height: 8),
                _Result(
                  ok: _schema!.ok,
                  title: _schema!.ok ? 'Schema ready' : 'Schema incomplete',
                  detail: _schema!.ok
                      ? 'All tables and collections found.'
                      : 'Missing: ${_schema!.missing.join(', ')}\n${_schema!.hint ?? ''}',
                  actions: [
                    if (_schema!.setupScript case final script?
                        when _backendId == SupabaseBackend.descriptorStatic.id)
                      FilledButton.icon(
                        key: const ValueKey('auto-setup'),
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                        label: const Text('Set up automatically'),
                        onPressed: _busy ? null : () => _autoSetup(script),
                      ),
                    if (_schema!.setupScript case final script?)
                      FilledButton.tonalIcon(
                        key: const ValueKey('copy-setup-sql'),
                        icon: const Icon(Icons.content_copy_rounded, size: 16),
                        label: const Text('Copy setup SQL'),
                        onPressed: () => _copySetup(script),
                      ),
                  ],
                ),
              ],
            ],
            if (descriptor.id != 'memory') ...[
              const SizedBox(height: 12),
              Card(
                child: SwitchRow(
                  key: const ValueKey('secure-new-group'),
                  icon: Icons.verified_user_rounded,
                  title: 'Encrypt and sign this group',
                  subtitle: _secure
                      ? 'Recommended. A random passphrase is generated and this device becomes the admin; other devices receive the key through pairing. Turn off only to join a group by typing a passphrase.'
                      : 'Off: clips are stored readable by the database and anyone with its credentials can pose as a device.',
                  value: _secure,
                  onChanged: (v) => setState(() => _secure = v),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('save-backend'),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(widget.onboarding ? 'Start syncing' : 'Save'),
            ),
            if (widget.onboarding)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
                  onPressed: () async {
                    await ref
                        .read(settingsProvider.notifier)
                        .update(
                          (s) => s.copyWith(
                            backendId: 'memory',
                            backendValues: const {},
                            onboarded: true,
                          ),
                        );
                    if (context.mounted) context.go('/');
                  },
                  child: Text(
                    'Skip: keep history on this device only',
                    style: TextStyle(color: c.muted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackendTile extends StatefulWidget {
  const _BackendTile({
    required this.descriptor,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final BackendDescriptor descriptor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_BackendTile> createState() => _BackendTileState();
}

class _BackendTileState extends State<_BackendTile> {
  bool _hover = false;

  static IconData _iconFor(String id) => switch (id) {
    'supabase' => Icons.bolt_rounded,
    'pocketbase' => Icons.inventory_2_outlined,
    'couchdb' => Icons.weekend_outlined,
    'firestore' => Icons.local_fire_department_outlined,
    'mongodb' => Icons.eco_outlined,
    _ => Icons.phonelink_lock_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final d = widget.descriptor;
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        selected: sel,
        button: true,
        label: d.displayName,
        child: AnimatedContainer(
          duration: AppTokens.fast,
          decoration: BoxDecoration(
            color: sel
                ? scheme.primary.withValues(alpha: 0.08)
                : (_hover ? scheme.surfaceContainer : c.surfaceRaised),
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            border: Border.all(
              color: sel ? scheme.primary : c.border,
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LeadingIcon(
                          icon: _iconFor(d.id),
                          color: sel ? scheme.primary : c.muted,
                          size: 32,
                        ),
                        const Spacer(),
                        if (sel)
                          Icon(
                            Icons.check_circle_rounded,
                            color: scheme.primary,
                            size: 20,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      d.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.id == 'memory'
                          ? 'No sync'
                          : (d.supportsRealtime ? 'Realtime' : 'Polling'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: d.supportsRealtime && d.id != 'memory'
                            ? c.success
                            : c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a Supabase personal access token (and the project ref when the
/// URL does not reveal it). Returns `(projectRef, token)`; nothing is saved.
class _SupabaseTokenDialog extends StatefulWidget {
  const _SupabaseTokenDialog({required this.projectRef});
  final String? projectRef;

  @override
  State<_SupabaseTokenDialog> createState() => _SupabaseTokenDialogState();
}

class _SupabaseTokenDialogState extends State<_SupabaseTokenDialog> {
  final _token = TextEditingController();
  late final _ref = TextEditingController(text: widget.projectRef ?? '');

  @override
  void dispose() {
    _token.dispose();
    _ref.dispose();
    super.dispose();
  }

  bool get _ready =>
      _token.text.trim().isNotEmpty && _ref.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.auto_fix_high_rounded),
      title: const Text('Set up the database'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The key Nija syncs with cannot create tables. A Supabase '
              'personal access token can: Nija sends it to Supabase once to '
              'run the setup, and does not keep it. Clipboard capture is '
              'paused while this window is open, so copying the token is '
              'not recorded.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Create a token'),
                onPressed: () => launchUrl(
                  Uri.parse('https://supabase.com/dashboard/account/tokens'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
            if (widget.projectRef == null) ...[
              TextField(
                key: const ValueKey('setup-project-ref'),
                controller: _ref,
                decoration: const InputDecoration(
                  labelText: 'Project ref',
                  helperText: 'Project Settings → General → Project ID',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const ValueKey('setup-token'),
              controller: _token,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Personal access token',
                hintText: 'sbp_…',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              'You can revoke the token in the Supabase dashboard as soon as '
              'this is done.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('setup-run'),
          onPressed: _ready
              ? () => Navigator.pop(context, (
                  _ref.text.trim(),
                  _token.text.trim(),
                ))
              : null,
          child: const Text('Set up'),
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.ok,
    required this.title,
    required this.detail,
    this.actions = const [],
  });
  final bool ok;
  final String title;
  final String detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final color = ok ? c.success : scheme.error;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
