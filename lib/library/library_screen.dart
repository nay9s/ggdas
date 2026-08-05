import 'package:flutter/material.dart';

import '../editor/editor_workspace.dart';
import '../models.dart';
import '../screens/settings_screen.dart';
import '../store.dart';
import 'notebook_card.dart';

enum LibraryTab { notes, recent, favorites }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<InkDocument> _documents = [];
  List<InkFolder> _folders = [];
  AppSettings _settings = const AppSettings();
  String? _currentFolderId;
  String _query = '';
  bool _loading = true;
  bool _isListView = false;
  LibraryTab _activeTab = LibraryTab.notes;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final results = await Future.wait<Object>([
      InkDocumentStore.loadAll(),
      InkFolderStore.loadAll(),
      AppSettingsStore.load(),
    ]);
    final documents = results[0] as List<InkDocument>;
    final folders = results[1] as List<InkFolder>;
    final settings = results[2] as AppSettings;
    _sortDocuments(documents, settings.sortBy);

    if (!mounted) return;
    setState(() {
      _documents = documents;
      _folders = folders;
      _settings = settings;
      if (_currentFolderId != null &&
          !_folders.any((folder) => folder.id == _currentFolderId)) {
        _currentFolderId = null;
      }
      _loading = false;
    });
  }

  void _sortDocuments(List<InkDocument> documents, String sortBy) {
    switch (sortBy) {
      case 'date_created':
        documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'name':
        documents.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case 'date_modified':
      default:
        documents.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
  }

  Future<void> _changeSort(String value) async {
    final settings = _settings.copyWith(sortBy: value);
    await AppSettingsStore.save(settings);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _sortDocuments(_documents, value);
    });
  }

  Future<String?> _askForName({
    String initial = '',
    required String title,
    String label = 'Name',
  }) async {
    final controller = TextEditingController(text: initial);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  }

  Future<void> _newDocument() async {
    final name = await _askForName(title: 'New note', label: 'Note title');
    if (name == null) return;
    final document = await InkDocumentStore.create(
      name,
      folderId: _activeTab == LibraryTab.notes ? _currentFolderId : null,
    );
    if (!mounted) return;
    await _openDocument(document);
  }

  Future<void> _openDocument(InkDocument document) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorWorkspace(initialDocument: document),
      ),
    );
    await _reload();
  }

  Future<void> _renameDocument(InkDocument document) async {
    final name = await _askForName(
      initial: document.title,
      title: 'Rename note',
      label: 'Note title',
    );
    if (name == null) return;
    await InkDocumentStore.save(
      document.copyWith(title: name, updatedAt: DateTime.now()),
    );
    await _reload();
  }

  Future<void> _deleteDocument(InkDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this note?'),
        content: Text(
          '“${document.title}” and all of its pages will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await InkDocumentStore.delete(document.id);
    await _reload();
  }

  Future<void> _toggleFavorite(InkDocument document) async {
    await InkDocumentStore.save(
      document.copyWith(
        isFavorite: !document.isFavorite,
        updatedAt: DateTime.now(),
      ),
    );
    await _reload();
  }

  Future<void> _changeDocumentColor(
    InkDocument document,
    int colorValue,
  ) async {
    await InkDocumentStore.save(
      document.copyWith(colorValue: colorValue, updatedAt: DateTime.now()),
    );
    await _reload();
  }

  Future<void> _moveDocument(InkDocument document) async {
    String? selectedFolderId = document.folderId;
    final destination = await showDialog<_FolderDestination>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Move note'),
          content: SizedBox(
            width: 420,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                children: [
                  _FolderChoiceTile(
                    title: 'All notes',
                    icon: Icons.home_outlined,
                    selected: selectedFolderId == null,
                    onTap: () =>
                        setDialogState(() => selectedFolderId = null),
                  ),
                  for (final folder in _folders)
                    _FolderChoiceTile(
                      title: folder.name,
                      icon: Icons.folder_outlined,
                      selected: selectedFolderId == folder.id,
                      onTap: () => setDialogState(
                        () => selectedFolderId = folder.id,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _FolderDestination(selectedFolderId),
              ),
              child: const Text('Move'),
            ),
          ],
        ),
      ),
    );
    if (destination == null) return;

    await InkDocumentStore.save(
      destination.id == null
          ? document.copyWith(clearFolder: true, updatedAt: DateTime.now())
          : document.copyWith(
              folderId: destination.id,
              updatedAt: DateTime.now(),
            ),
    );
    await _reload();
  }

  Future<void> _newFolder() async {
    final name = await _askForName(
      title: 'New folder',
      label: 'Folder name',
    );
    if (name == null) return;
    await InkFolderStore.create(name, parentId: _currentFolderId);
    await _reload();
  }

  Future<void> _renameFolder(InkFolder folder) async {
    final name = await _askForName(
      initial: folder.name,
      title: 'Rename folder',
      label: 'Folder name',
    );
    if (name == null) return;
    await InkFolderStore.rename(folder, name);
    await _reload();
  }

  Future<void> _deleteFolder(InkFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this folder?'),
        content: const Text(
          'The folder and its subfolders will be removed. Notes inside will be moved back to All notes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete folder'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await InkFolderStore.delete(folder.id);
    await _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    await _reload();
  }

  List<InkFolder> get _breadcrumbs {
    final path = <InkFolder>[];
    var current = _currentFolderId;
    final visited = <String>{};
    while (current != null && visited.add(current)) {
      InkFolder? found;
      for (final folder in _folders) {
        if (folder.id == current) {
          found = folder;
          break;
        }
      }
      if (found == null) break;
      path.insert(0, found);
      current = found.parentId;
    }
    return path;
  }

  void _selectTab(LibraryTab tab) {
    setState(() {
      _activeTab = tab;
      _currentFolderId = null;
    });
  }

  int get _selectedNavigationIndex => switch (_activeTab) {
        LibraryTab.notes => 0,
        LibraryTab.recent => 1,
        LibraryTab.favorites => 2,
      };

  void _onNavigationSelected(int index) {
    if (index == 3) {
      _openSettings();
      return;
    }
    _selectTab(LibraryTab.values[index]);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final useRail = size.width >= 840;
    final filteredDocuments = _filteredDocuments;
    final filteredFolders = _filteredFolders;

    return Scaffold(
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: _selectedNavigationIndex,
              onDestinationSelected: _onNavigationSelected,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.note_outlined),
                  selectedIcon: Icon(Icons.note_rounded),
                  label: 'Notes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.schedule_outlined),
                  selectedIcon: Icon(Icons.schedule_rounded),
                  label: 'Recent',
                ),
                NavigationDestination(
                  icon: Icon(Icons.star_outline_rounded),
                  selectedIcon: Icon(Icons.star_rounded),
                  label: 'Favorites',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
      body: SafeArea(
        bottom: useRail,
        child: Row(
          children: [
            if (useRail)
              _LibraryRail(
                selectedIndex: _selectedNavigationIndex,
                extended: size.width >= 1180,
                onSelected: _onNavigationSelected,
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1500),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      size.width < 600 ? 16 : 28,
                      size.width < 600 ? 14 : 24,
                      size.width < 600 ? 16 : 28,
                      18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LibraryHeader(
                          title: _pageTitle,
                          breadcrumbs: _activeTab == LibraryTab.notes
                              ? _breadcrumbs
                              : const [],
                          currentFolderId: _currentFolderId,
                          onOpenRoot: () =>
                              setState(() => _currentFolderId = null),
                          onOpenFolder: (id) =>
                              setState(() => _currentFolderId = id),
                          onNewNote: _newDocument,
                          onNewFolder: _activeTab == LibraryTab.notes
                              ? _newFolder
                              : null,
                          compact: size.width < 680,
                        ),
                        const SizedBox(height: 20),
                        _LibraryControls(
                          controller: _searchController,
                          isListView: _isListView,
                          sortBy: _settings.sortBy,
                          compact: size.width < 680,
                          onQueryChanged: (value) =>
                              setState(() => _query = value.trim()),
                          onToggleView: () =>
                              setState(() => _isListView = !_isListView),
                          onSortChanged: _changeSort,
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator.adaptive())
                              : filteredDocuments.isEmpty &&
                                      filteredFolders.isEmpty
                                  ? _EmptyLibrary(
                                      tab: _activeTab,
                                      hasQuery: _query.isNotEmpty,
                                      onCreate: _newDocument,
                                    )
                                  : _isListView
                                      ? _LibraryList(
                                          folders: filteredFolders,
                                          documents: filteredDocuments,
                                          onOpenFolder: (folder) => setState(
                                            () => _currentFolderId = folder.id,
                                          ),
                                          onRenameFolder: _renameFolder,
                                          onDeleteFolder: _deleteFolder,
                                          onOpenDocument: _openDocument,
                                          onRenameDocument: _renameDocument,
                                          onMoveDocument: _moveDocument,
                                          onDeleteDocument: _deleteDocument,
                                          onToggleFavorite: _toggleFavorite,
                                        )
                                      : _LibraryGrid(
                                          folders: filteredFolders,
                                          documents: filteredDocuments,
                                          compact: size.width < 600,
                                          onOpenFolder: (folder) => setState(
                                            () => _currentFolderId = folder.id,
                                          ),
                                          onRenameFolder: _renameFolder,
                                          onDeleteFolder: _deleteFolder,
                                          onOpenDocument: _openDocument,
                                          onRenameDocument: _renameDocument,
                                          onMoveDocument: _moveDocument,
                                          onDeleteDocument: _deleteDocument,
                                          onToggleFavorite: _toggleFavorite,
                                          onChangeColor: _changeDocumentColor,
                                        ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _pageTitle {
    switch (_activeTab) {
      case LibraryTab.notes:
        return 'Notes';
      case LibraryTab.recent:
        return 'Recent';
      case LibraryTab.favorites:
        return 'Favorites';
    }
  }

  List<InkDocument> get _filteredDocuments {
    final normalizedQuery = _query.toLowerCase();
    return _documents.where((document) {
      if (normalizedQuery.isNotEmpty &&
          !document.title.toLowerCase().contains(normalizedQuery)) {
        return false;
      }
      switch (_activeTab) {
        case LibraryTab.notes:
          return document.folderId == _currentFolderId;
        case LibraryTab.recent:
          return true;
        case LibraryTab.favorites:
          return document.isFavorite;
      }
    }).toList();
  }

  List<InkFolder> get _filteredFolders {
    if (_activeTab != LibraryTab.notes || _query.isNotEmpty) return [];
    return _folders
        .where((folder) => folder.parentId == _currentFolderId)
        .toList();
  }
}


class _FolderChoiceTile extends StatelessWidget {
  const _FolderChoiceTile({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: .55),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon),
      title: Text(title),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

class _FolderDestination {
  const _FolderDestination(this.id);
  final String? id;
}

class _LibraryRail extends StatelessWidget {
  const _LibraryRail({
    required this.selectedIndex,
    required this.extended,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: NavigationRail(
        selectedIndex: selectedIndex,
        extended: extended,
        minExtendedWidth: 210,
        groupAlignment: -0.75,
        onDestinationSelected: onSelected,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.draw_rounded,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              if (extended) ...[
                const SizedBox(width: 12),
                const Text(
                  'Ink Note',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ],
          ),
        ),
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.note_outlined),
            selectedIcon: Icon(Icons.note_rounded),
            label: Text('Notes'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule_rounded),
            label: Text('Recent'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.star_outline_rounded),
            selectedIcon: Icon(Icons.star_rounded),
            label: Text('Favorites'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: Text('Settings'),
          ),
        ],
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.title,
    required this.breadcrumbs,
    required this.currentFolderId,
    required this.onOpenRoot,
    required this.onOpenFolder,
    required this.onNewNote,
    required this.onNewFolder,
    required this.compact,
  });

  final String title;
  final List<InkFolder> breadcrumbs;
  final String? currentFolderId;
  final VoidCallback onOpenRoot;
  final ValueChanged<String> onOpenFolder;
  final VoidCallback onNewNote;
  final VoidCallback? onNewFolder;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleWidget = breadcrumbs.isEmpty
        ? Text(
            title,
            style: TextStyle(
              fontSize: compact ? 26 : 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -.8,
            ),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TextButton(
                  onPressed: onOpenRoot,
                  child: const Text('Notes'),
                ),
                for (final folder in breadcrumbs) ...[
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  TextButton(
                    onPressed: folder.id == currentFolderId
                        ? null
                        : () => onOpenFolder(folder.id),
                    child: Text(folder.name),
                  ),
                ],
              ],
            ),
          );

    if (compact) {
      return Row(
        children: [
          Expanded(child: titleWidget),
          if (onNewFolder != null)
            IconButton(
              tooltip: 'New folder',
              onPressed: onNewFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          IconButton.filled(
            tooltip: 'New note',
            onPressed: onNewNote,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: titleWidget),
        if (onNewFolder != null) ...[
          OutlinedButton.icon(
            onPressed: onNewFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('New folder'),
          ),
          const SizedBox(width: 10),
        ],
        FilledButton.icon(
          onPressed: onNewNote,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New note'),
        ),
      ],
    );
  }
}

class _LibraryControls extends StatelessWidget {
  const _LibraryControls({
    required this.controller,
    required this.isListView,
    required this.sortBy,
    required this.compact,
    required this.onQueryChanged,
    required this.onToggleView,
    required this.onSortChanged,
  });

  final TextEditingController controller;
  final bool isListView;
  final String sortBy;
  final bool compact;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleView;
  final ValueChanged<String> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      controller: controller,
      onChanged: onQueryChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search notes',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  onQueryChanged('');
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: 'Sort notes',
          initialValue: sortBy,
          onSelected: onSortChanged,
          icon: const Icon(Icons.sort_rounded),
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'date_modified',
              child: Text('Last edited'),
            ),
            PopupMenuItem(
              value: 'date_created',
              child: Text('Date created'),
            ),
            PopupMenuItem(value: 'name', child: Text('Name')),
          ],
        ),
        IconButton(
          tooltip: isListView ? 'Grid view' : 'List view',
          onPressed: onToggleView,
          icon: Icon(
            isListView ? Icons.grid_view_rounded : Icons.view_list_rounded,
          ),
        ),
      ],
    );

    if (compact) {
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 6),
          actions,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 12),
        actions,
      ],
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.folders,
    required this.documents,
    required this.compact,
    required this.onOpenFolder,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onOpenDocument,
    required this.onRenameDocument,
    required this.onMoveDocument,
    required this.onDeleteDocument,
    required this.onToggleFavorite,
    required this.onChangeColor,
  });

  final List<InkFolder> folders;
  final List<InkDocument> documents;
  final bool compact;
  final ValueChanged<InkFolder> onOpenFolder;
  final ValueChanged<InkFolder> onRenameFolder;
  final ValueChanged<InkFolder> onDeleteFolder;
  final ValueChanged<InkDocument> onOpenDocument;
  final ValueChanged<InkDocument> onRenameDocument;
  final ValueChanged<InkDocument> onMoveDocument;
  final ValueChanged<InkDocument> onDeleteDocument;
  final ValueChanged<InkDocument> onToggleFavorite;
  final void Function(InkDocument, int) onChangeColor;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: compact ? 220 : 260,
        mainAxisExtent: compact ? 252 : 286,
        crossAxisSpacing: compact ? 12 : 18,
        mainAxisSpacing: compact ? 12 : 18,
      ),
      itemCount: folders.length + documents.length,
      itemBuilder: (context, index) {
        if (index < folders.length) {
          final folder = folders[index];
          return _FolderCard(
            folder: folder,
            onTap: () => onOpenFolder(folder),
            onRename: () => onRenameFolder(folder),
            onDelete: () => onDeleteFolder(folder),
          );
        }
        final document = documents[index - folders.length];
        return NotebookCard(
          document: document,
          onTap: () => onOpenDocument(document),
          onRename: () => onRenameDocument(document),
          onMove: () => onMoveDocument(document),
          onDelete: () => onDeleteDocument(document),
          onToggleFavorite: () => onToggleFavorite(document),
          onChangeColor: (value) => onChangeColor(document, value),
        );
      },
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final InkFolder folder;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 94,
                        height: 74,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(
                          Icons.folder_rounded,
                          size: 52,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Folder',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: PopupMenuButton<String>(
                tooltip: 'Folder actions',
                onSelected: (value) {
                  if (value == 'rename') onRename();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Delete'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({
    required this.folders,
    required this.documents,
    required this.onOpenFolder,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onOpenDocument,
    required this.onRenameDocument,
    required this.onMoveDocument,
    required this.onDeleteDocument,
    required this.onToggleFavorite,
  });

  final List<InkFolder> folders;
  final List<InkDocument> documents;
  final ValueChanged<InkFolder> onOpenFolder;
  final ValueChanged<InkFolder> onRenameFolder;
  final ValueChanged<InkFolder> onDeleteFolder;
  final ValueChanged<InkDocument> onOpenDocument;
  final ValueChanged<InkDocument> onRenameDocument;
  final ValueChanged<InkDocument> onMoveDocument;
  final ValueChanged<InkDocument> onDeleteDocument;
  final ValueChanged<InkDocument> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: folders.length + documents.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index < folders.length) {
          final folder = folders[index];
          return Card(
            child: ListTile(
              minTileHeight: 68,
              leading: const Icon(Icons.folder_rounded, size: 32),
              title: Text(
                folder.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Folder'),
              onTap: () => onOpenFolder(folder),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') onRenameFolder(folder);
                  if (value == 'delete') onDeleteFolder(folder);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          );
        }

        final document = documents[index - folders.length];
        return Card(
          child: ListTile(
            minTileHeight: 76,
            leading: Container(
              width: 46,
              height: 54,
              decoration: BoxDecoration(
                color: Color(document.colorValue),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.description_outlined, color: Colors.white),
            ),
            title: Text(
              document.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${document.pages.length} page${document.pages.length == 1 ? '' : 's'} • ${formatNoteDate(document.updatedAt)}',
            ),
            onTap: () => onOpenDocument(document),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'favorite') onToggleFavorite(document);
                if (value == 'rename') onRenameDocument(document);
                if (value == 'move') onMoveDocument(document);
                if (value == 'delete') onDeleteDocument(document);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'favorite',
                  child: Text(
                    document.isFavorite
                        ? 'Remove favorite'
                        : 'Add to favorites',
                  ),
                ),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(value: 'move', child: Text('Move')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.tab,
    required this.hasQuery,
    required this.onCreate,
  });

  final LibraryTab tab;
  final bool hasQuery;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = hasQuery
        ? 'No matching notes'
        : tab == LibraryTab.favorites
            ? 'No favorites yet'
            : tab == LibraryTab.recent
                ? 'No recent notes'
                : 'Create your first note';
    final message = hasQuery
        ? 'Try another word or clear the search.'
        : tab == LibraryTab.favorites
            ? 'Mark a note as favorite to keep it close.'
            : 'Start writing, sketching, or collecting ideas.';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                hasQuery ? Icons.search_off_rounded : Icons.note_add_outlined,
                size: 36,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (!hasQuery && tab == LibraryTab.notes) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New note'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
