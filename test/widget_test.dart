// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:director/main.dart';
import 'package:director/services/api_service.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    // 传 restoredUser: null 才能落到登录页——这是「没有可恢复的登录态」
    // 那条分支，登录页存在的全部意义就是它。
    await tester.pumpWidget(
      MyApp(apiService: ApiService(), restoredUser: null),
    );

    expect(find.text('导播控制系统'), findsOneWidget);
    expect(find.widgetWithText(TextField, '用户名'), findsOneWidget);
    expect(find.widgetWithText(TextField, '密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
