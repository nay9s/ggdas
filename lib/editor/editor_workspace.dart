import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import 'editor_screen.dart';

class EditorWorkspace extends StatefulWidget {
  const EditorWorkspace({super.key, required this.initialDocument});

  final InkDocument initialDocument;

  @override
  State<EditorWorkspace> createState() => _EditorWorkspaceState();
}

class _EditorWorkspaceState extends State<EditorWorkspace> {
  late final List<InkDocument> _openDocuments = [widget.initialDocument];
  late String _activeId = widget.initialDocument.id;

  InkDocument get _activeDocument =>
      _openDocuments.firstWhere((document) => document.id == _activeId);

  void _documentSaved(InkDocument saved) {
    if (!mounted) return;
    final index = _openDocuments.indexWhere((item) => item.id == saved.id);
    if (index >= 0) {
      setState(() {
        _openDocuments[index] = saved;
      });
    }
  }

  Future<void> _newTab() async {
    var value = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New tab'),
        content: TextFormField(
          autofocus: true,
          decoration: const InputDecoration(labelText: 'File name'),
          onChanged: (text) => value = text,
          onFieldSubmitted: (text) => Navigator.pop(context, text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final document = await InkDocumentStore.create(name);
    if (!mounted) return;
    setState(() {
      _openDocuments.add(document);
      _activeId = document.id;
    });
  }

  void _closeTab(String id) {
    final index = _openDocuments.indexWhere((document) => document.id == id);
    if (index < 0) return;
    if (_openDocuments.length == 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _openDocuments.removeAt(index);
      if (_activeId == id) {
        _activeId =
            _openDocuments[math.min(index, _openDocuments.length - 1)].id;
      }
    });
  }

  @override
  Widget build(BuildContext context) => EditorScreen(
    key: ValueKey(_activeId),
    document: _activeDocument,
    openDocuments: List.unmodifiable(_openDocuments),
    activeDocumentId: _activeId,
    onSelectTab: (id) => setState(() => _activeId = id),
    onCloseTab: _closeTab,
    onNewTab: _newTab,
    onExit: () => Navigator.pop(context),
    onDocumentSaved: _documentSaved,
  );
}
