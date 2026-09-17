import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';

import 'model_licenses.dart';
import 'terpsichore_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerModelLicenses();
  runApp(const TerpsichoreApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(EmotionBackmailService.recordAppOpen());
  });
}
