import '../../domain/updates/app_release.dart';
import 'update_channel.dart';

/// Update channel for a Google Play build.
///
/// Play installs and updates the app itself, so this channel never compares
/// versions: it reports no release and only knows where the listing is.
class PlayStoreUpdateChannel implements UpdateChannel {
  /// Creates the Play channel.
  const PlayStoreUpdateChannel();

  /// The app's Play listing (`HareegAppMetadata.appId`).
  static final listingUrl = Uri.parse(
    'https://play.google.com/store/apps/details?id=com.maiz27.hareegtable',
  );

  @override
  bool get reportsVersions => false;

  @override
  Uri? get storeListingUrl => listingUrl;

  @override
  Future<AppRelease?> fetchLatestRelease() async => null;
}
