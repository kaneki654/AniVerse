/// Build number of this app, compared against the server's published build to
/// decide whether an update is offered.
///
/// Deliberately a constant rather than `package_info_plus`: that plugin is not
/// yet compatible with Flutter 3.47's built-in Kotlin migration and broke the
/// release build (`cannot find symbol PackageInfoPlugin`), taking `wakelock_plus`
/// down with it.
///
/// Keep in step with `version:` in pubspec.yaml.
const int kAppBuildNumber = 7;
const String kAppVersionName = '1.4.1';
