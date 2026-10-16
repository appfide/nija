/// Build-time constants injected by CI via `--dart-define`.
///
/// `flutter build … --dart-define=APP_VERSION=1.2.3 --dart-define=GIT_SHA=abc`
abstract final class BuildInfo {
  /// Semantic version of this build, `dev` for local runs.
  static const String version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  /// Short git SHA of this build.
  static const String gitSha = String.fromEnvironment(
    'GIT_SHA',
    defaultValue: 'local',
  );

  /// App Store / Mac App Store build (`--dart-define=STORE_BUILD=true`).
  /// Hides what a store build must not offer: installers for other
  /// platforms, and start-at-login, which the Mac App Store sandbox blocks
  /// until it moves to SMAppService.
  static const bool storeBuild = bool.fromEnvironment('STORE_BUILD');

  /// Public repository.
  static const String repoUrl = 'https://github.com/appfide/nija';
}
