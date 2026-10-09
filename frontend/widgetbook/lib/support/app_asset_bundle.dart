import 'package:flutter/services.dart';

/// Resolves the app's own asset paths from inside the catalog.
///
/// The app loads its images as `assets/…`, which is correct while it is the
/// root package. Here it is a dependency, so Flutter bundles the same files
/// under `packages/map_my_friends/assets/…` and the unprefixed lookup misses —
/// the shell's rail and the login screen would render a broken-image box
/// where the logo goes. Installed as the [DefaultAssetBundle], this rewrites
/// the prefix so app code runs unmodified.
class AppAssetBundle extends CachingAssetBundle {
  AppAssetBundle(this._parent);

  final AssetBundle _parent;

  static String _resolve(String key) =>
      key.startsWith('assets/') ? 'packages/map_my_friends/$key' : key;

  @override
  Future<ByteData> load(String key) => _parent.load(_resolve(key));

  @override
  Future<ImmutableBuffer> loadBuffer(String key) =>
      _parent.loadBuffer(_resolve(key));
}
