import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ink_note/store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('clearing all notes does not recreate sample notes', () async {
    final initial = await InkDocumentStore.loadAll();
    expect(initial, isNotEmpty);

    await InkDocumentStore.deleteAll();
    final afterClear = await InkDocumentStore.loadAll();

    expect(afterClear, isEmpty);
  });

  test('deleting a folder moves its notes back to the root', () async {
    await InkDocumentStore.loadAll();
    final folder = await InkFolderStore.create('Archive');
    final note = await InkDocumentStore.create('Moved note', folderId: folder.id);

    await InkFolderStore.delete(folder.id);
    final documents = await InkDocumentStore.loadAll();
    final saved = documents.firstWhere((item) => item.id == note.id);

    expect(saved.folderId, isNull);
  });
}
