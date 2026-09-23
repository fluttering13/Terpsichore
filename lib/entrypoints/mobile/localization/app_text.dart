import 'package:flutter/widgets.dart';
import '../../../infrastructure/engagement/emotion_backmail_service.dart';
import 'english_messages.dart';
import 'english_errors.dart';

/// Translate authored UI copy, leaving interpolated filenames and user content intact.
String appText(
  BuildContext context,
  String chinese, [
  List<Object?> arguments = const [],
]) {
  // Subscribe to the app locale so existing pages and dialogs rebuild on changes.
  Localizations.maybeLocaleOf(context);
  return formatAppText(
    chinese,
    english: EmotionBackmailService.language.value == AppLanguage.english,
    arguments: arguments,
  );
}

String formatAppText(
  String chinese, {
  required bool english,
  List<Object?> arguments = const [],
}) {
  final template = english ? englishMessages[chinese] ?? chinese : chinese;
  return template.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
    final index = int.parse(match[1]!);
    return index < arguments.length ? '${arguments[index]}' : match[0]!;
  });
}

String appError(BuildContext context, Object? error) {
  Localizations.maybeLocaleOf(context);
  return formatAppError(
    error,
    english: EmotionBackmailService.language.value == AppLanguage.english,
  );
}

String formatAppError(Object? error, {required bool english}) {
  final original = error.toString();
  if (!english) return original;
  final message = original.replaceFirst(
    RegExp(
      r'^(Bad state|FormatException|Invalid argument\(s\)|HttpException|Exception): ',
    ),
    '',
  );
  for (final entry in englishErrors.entries) {
    final placeholders = RegExp(r'\{\d+\}');
    final parts = entry.key.split(placeholders).map(RegExp.escape);
    final match = RegExp(
      '^${parts.join('(.*?)')}\$',
      dotAll: true,
    ).firstMatch(message);
    if (match == null) continue;
    return entry.value.replaceAllMapped(placeholders, (token) {
      final index = int.parse(token[0]!.substring(1, token[0]!.length - 1));
      return match[index + 1]!;
    });
  }
  return original;
}
