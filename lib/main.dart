import 'package:flutter/material.dart';

import 'app/app_orientation.dart';
import 'app/hareeg_table_app.dart';

/// Starts the Hareeg Table Flutter application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppOrientation.usePortrait();

  runApp(const HareegTableApp());
}
