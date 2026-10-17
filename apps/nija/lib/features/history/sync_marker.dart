import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nija/data/local/local_store.dart';
import 'package:nija/providers.dart';
import 'package:nija/ui/app_theme.dart';

/// Display name of the connected database, such as *Supabase*. Pass
/// [listen] false outside `build`.
String databaseName(WidgetRef ref, {bool listen = true}) {
  final id = listen
      ? ref.watch(settingsProvider.select((s) => s.backendId))
      : ref.read(settingsProvider).backendId;
  final registry = listen
      ? ref.watch(backendRegistryProvider)
      : ref.read(backendRegistryProvider);
  return registry.descriptor(id)?.displayName ?? 'the database';
}

/// One line describing [state], for tooltips and the clip preview.
String syncStateLabel(ClipSyncState state, String database) => switch (state) {
  ClipSyncState.inDatabase => 'In $database',
  ClipSyncState.pending => 'Waiting to sync to $database',
  ClipSyncState.localOnly => 'Only on this device',
};

/// Icon for [state].
IconData syncStateIcon(ClipSyncState state) => switch (state) {
  ClipSyncState.inDatabase => Icons.cloud_done_outlined,
  ClipSyncState.pending => Icons.cloud_upload_outlined,
  ClipSyncState.localOnly => Icons.cloud_off_outlined,
};

/// Small cloud on a history row telling whether the clip reached the
/// database. Tap or hover it for the words.
class SyncMarker extends StatelessWidget {
  /// Creates the marker.
  const SyncMarker(this.state, {required this.database, super.key});

  /// Where the clip is.
  final ClipSyncState state;

  /// Display name of the connected database.
  final String database;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = syncStateLabel(state, database);
    return Tooltip(
      message: label,
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
        label: label,
        child: Icon(
          syncStateIcon(state),
          key: ValueKey('sync-${state.name}'),
          size: 14,
          color: switch (state) {
            ClipSyncState.inDatabase => c.success,
            ClipSyncState.pending => c.warning,
            ClipSyncState.localOnly => c.muted,
          },
        ),
      ),
    );
  }
}
