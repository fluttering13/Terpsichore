import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/entrypoints/mobile/terpsichore_app.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';

void main() {
  testWidgets('shows all four dancer workflows', (tester) async {
    await tester.pumpWidget(const TerpsichoreApp());

    expect(find.text('選擇練習方式'), findsOneWidget);
    expect(find.text('學習模式'), findsOneWidget);
    expect(find.text('A+B 分析'), findsOneWidget);
    expect(find.text('純音樂練習'), findsOneWidget);
    expect(find.text('影片轉檔'), findsOneWidget);

    await tester.tap(find.text('開始舞蹈練習'));
    await tester.pumpAndSettle();
    expect(find.text('選一支舞蹈影片開始練習'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A+B 分析'));
    await tester.pumpAndSettle();

    expect(find.text('A・參考影片'), findsOneWidget);
    expect(find.text('B・我的影片'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'AI 對齊（固定 A）'))
          .onPressed,
      isNull,
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI 對齊設定'));
    await tester.pumpAndSettle();
    expect(find.text('B 起點搜尋範圍：±10%'), findsOneWidget);
    expect(find.text('骨架平滑窗口（秒）'), findsOneWidget);
    final multiPerson = find.byKey(
      const ValueKey('pose-multi-person-filtering'),
    );
    expect(multiPerson, findsNothing);
    expect(find.textContaining('自動追蹤主要人物'), findsOneWidget);
    expect(find.text('自動（6–12 FPS）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pose-sampling-fps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6 FPS').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('pose-sampling-fps')),
          )
          .initialValue,
      6,
    );
    final windowField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(windowField, 'NaN');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '儲存'))
          .onPressed,
      isNull,
    );
    await tester.enterText(windowField, '0.35');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '儲存'))
          .onPressed,
      isNotNull,
    );
    tester
        .widget<Slider>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Slider),
          ),
        )
        .onChanged!(0);
    await tester.pump();
    expect(find.text('B 起點搜尋範圍：±0%'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI 對齊設定'));
    await tester.pumpAndSettle();
    expect(multiPerson, findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pumpAndSettle();
    await tester.tap(find.text('純音樂練習'));
    await tester.pumpAndSettle();

    expect(find.text('選擇練習音樂'), findsOneWidget);
    expect(find.text('匯入影片或聲音檔'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pumpAndSettle();
    await tester.tap(find.text('影片轉檔'));
    await tester.pumpAndSettle();

    expect(find.text('選擇要轉換的影片'), findsOneWidget);
    expect(find.text('輸出格式'), findsOneWidget);
    expect(find.text('輸出解析度'), findsOneWidget);
    expect(find.text('影像編碼'), findsOneWidget);
    expect(find.text('H.264 / AVC'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首頁'));
    await tester.pumpAndSettle();

    expect(find.text('今天想從哪裡開始？'), findsOneWidget);
  });

  testWidgets('shows the consecutive login streak on the home screen', (
    tester,
  ) async {
    EmotionBackmailService.onlineStreak.value = 6;
    EmotionBackmailService.notificationMessage.value = '第六天的通知台詞';
    addTearDown(() {
      EmotionBackmailService.onlineStreak.value = null;
      EmotionBackmailService.notificationMessage.value = null;
    });

    await tester.pumpWidget(const TerpsichoreApp());

    expect(find.text('已連續登入 6 天'), findsOneWidget);
    expect(find.text('第六天的通知台詞'), findsOneWidget);
  });

  testWidgets('switches the login streak and home screen to English', (
    tester,
  ) async {
    EmotionBackmailService.onlineStreak.value = 2;
    EmotionBackmailService.language.value = AppLanguage.traditionalChinese;
    addTearDown(() {
      EmotionBackmailService.onlineStreak.value = null;
      EmotionBackmailService.notificationMessage.value = null;
      EmotionBackmailService.language.value = AppLanguage.traditionalChinese;
    });

    await tester.pumpWidget(const TerpsichoreApp());
    EmotionBackmailService.language.value = AppLanguage.english;
    await tester.pump();

    expect(find.text('2-day login streak'), findsOneWidget);
    expect(find.text('Choose a practice mode'), findsOneWidget);
  });
}
