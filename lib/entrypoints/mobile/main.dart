import 'package:flutter/widgets.dart';

import 'model_licenses.dart';
import 'terpsichore_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerModelLicenses();
  runApp(const TerpsichoreApp());
}
