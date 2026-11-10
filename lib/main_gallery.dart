import 'package:flutter/material.dart';

import 'gallery/gallery_app.dart';

/// `make gallery`: the shared components with mock data, no sign-in needed.
///
/// On the web, `?screen=<key>` opens one of the app's screens on mock data
/// instead (see [galleryScreens]); the hosted prototype links to these.
void main() {
  runApp(GalleryApp(screen: Uri.base.queryParameters['screen']));
}
