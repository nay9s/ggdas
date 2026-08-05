import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ink_note/main.dart';

void main() {
  testWidgets('Ink Note launches and shows the library', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const InkNoteApp());
    await tester.pumpAndSettle();

    expect(find.text('Notes'), findsWidgets);
    expect(find.text('Study Notes'), findsOneWidget);
  });
}
