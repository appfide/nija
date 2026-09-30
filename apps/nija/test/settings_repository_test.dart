import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nija/data/settings/secret_store.dart';
import 'package:nija/data/settings/settings_repository.dart';
import 'package:nija_core/nija_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsRepository> repo() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsRepository(
      prefs,
      SecretStore(const FlutterSecureStorage(), prefs),
      BackendRegistry.builtIn(),
    );
  }

  test('desktop history options default on first launch', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await (await repo()).load(includeSecrets: false);
    expect(s.hideAfterCopy, isFalse);
    expect(s.trayRecents, isTrue);
  });

  test('desktop history options survive a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final r = await repo();
    final s = await r.load(includeSecrets: false);
    await r.save(s.copyWith(hideAfterCopy: true, trayRecents: false));
    final back = await (await repo()).load(includeSecrets: false);
    expect(back.hideAfterCopy, isTrue);
    expect(back.trayRecents, isFalse);
    expect(back.deviceId, s.deviceId);
  });
}
