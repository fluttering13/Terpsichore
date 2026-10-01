import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/entrypoints/mobile/terpsichore_app.dart';
import 'package:terpsichore/infrastructure/engagement/emotion_backmail_service.dart';

void main() {
  testWidgets('shows all five dancer workflows', (tester) async {
    await tester.pumpWidget(const TerpsichoreApp());

    expect(find.text('選擇練習方式'), findsOneWidget);
    expect(find.text('學習模式'), findsOneWidget);
    expect(find.text('A+B 分析'), findsOneWidget);
    expect(find.text('純音樂練習'), findsOneWidget);
    expect(find.text('影片轉檔'), findsOneWidget);
    expect(find.text('平台影片下載'), findsOneWidget);

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
    await tester.tap(find.byTooltip('AI 設定'));
    await tester.pumpAndSettle();
    expect(find.text('B 對齊模式（A 始終固定）'), findsOneWidget);
    expect(find.text('時間軸與倍速都搜尋'), findsOneWidget);
    expect(find.text('骨架平滑窗口（秒）'), findsOneWidget);
    final multiPerson = find.byKey(
      const ValueKey('pose-multi-person-filtering'),
    );
    expect(multiPerson, findsNothing);
    expect(find.textContaining('自動追蹤主要人物'), findsOneWidget);
    expect(find.text('自動（6–12 FPS）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pose-sampling-fps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 FPS').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('pose-sampling-fps')),
          )
          .initialValue,
      1,
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
    await tester.enterText(windowField, '2.5');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '儲存'))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.text('時間軸與倍速都搜尋').first);
    await tester.tap(find.text('時間軸與倍速都搜尋').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('固定時間軸，只搜尋倍速').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('保留 B 目前的裁切起點與終點'), findsOneWidget);
    expect(find.text('AI 對齊設定'), findsOneWidget);
    expect(find.text('3D Pose 設定'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('pose3d-model')));
    expect(find.text('MediaPipe Heavy'), findsNothing);
    expect(find.text('NLF-L INT8'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('pose3d-fps')),
          )
          .initialValue,
      10,
    );
    await tester.tap(find.byKey(const ValueKey('pose3d-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NLF-L INT8').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('pose3d-fps')));
    await tester.tap(find.byKey(const ValueKey('pose3d-fps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 FPS').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('pose3d-fps')),
          )
          .initialValue,
      3,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('pose-sampling-fps')),
          )
          .initialValue,
      1,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Post-processing：內插其餘影格'),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI 設定'));
    await tester.pumpAndSettle();
    expect(find.text('時間軸與倍速都搜尋'), findsOneWidget);
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
    await tester.tap(find.text('平台下載'));
    await tester.pumpAndSettle();
    expect(find.text('平台影片下載'), findsOneWidget);
    expect(find.text('貼上連結'), findsOneWidget);
    expect(find.text('解析影片'), findsOneWidget);

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
    EmotionBackmailService.bestOnlineStreak.value = 12;
    EmotionBackmailService.notificationMessage.value = '第六天的通知台詞';
    addTearDown(() {
      EmotionBackmailService.onlineStreak.value = null;
      EmotionBackmailService.bestOnlineStreak.value = null;
      EmotionBackmailService.notificationMessage.value = null;
    });

    await tester.pumpWidget(const TerpsichoreApp());

    expect(find.text('目前連續登入 6 天'), findsOneWidget);
    expect(find.text('最高連續登入 12 天'), findsOneWidget);
    expect(find.text('第六天的通知台詞'), findsOneWidget);
  });

  testWidgets('switches the login streak and home screen to English', (
    tester,
  ) async {
    EmotionBackmailService.onlineStreak.value = 2;
    EmotionBackmailService.bestOnlineStreak.value = 8;
    EmotionBackmailService.language.value = AppLanguage.traditionalChinese;
    addTearDown(() {
      EmotionBackmailService.onlineStreak.value = null;
      EmotionBackmailService.bestOnlineStreak.value = null;
      EmotionBackmailService.notificationMessage.value = null;
      EmotionBackmailService.language.value = AppLanguage.traditionalChinese;
    });

    await tester.pumpWidget(const TerpsichoreApp());
    EmotionBackmailService.language.value = AppLanguage.english;
    await tester.pump();

    expect(find.text('Current login streak: 2 days'), findsOneWidget);
    expect(find.text('Best login streak: 8 days'), findsOneWidget);
    expect(find.text('Choose a practice mode'), findsOneWidget);
  });
}
