import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/hareeg_table_app.dart';

/// Starts the Hareeg Table Flutter application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const HareegTableApp());
}
