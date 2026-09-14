import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/entrypoints/mobile/terpsichore_app.dart';

void main() {
  testWidgets('shows all three dancer workflows', (tester) async {
    await tester.pumpWidget(const TerpsichoreApp());

    expect(find.text('選擇練習方式'), findsOneWidget);
    expect(find.text('學習模式'), findsOneWidget);
    expect(find.text('A+B 分析'), findsOneWidget);
    expect(find.text('純音樂練習'), findsOneWidget);

    await tester.tap(find.text('開始舞蹈練習'));
    await tester.pumpAndSettle();
    expect(find.text('選一支舞蹈影片開始練習'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A+B 分析'));
    await tester.pumpAndSettle();

    expect(find.text('A・參考影片'), findsOneWidget);
    expect(find.text('B・我的影片'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pumpAndSettle();
    await tester.tap(find.text('純音樂練習'));
    await tester.pumpAndSettle();

    expect(find.text('選擇練習音樂'), findsOneWidget);
    expect(find.text('匯入影片或聲音檔'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首頁'));
    await tester.pumpAndSettle();

    expect(find.text('今天想從哪裡開始？'), findsOneWidget);
  });
}
