import 'package:flutter/material.dart';

import '../editor/ink_painter.dart';
import '../models.dart';

class NotebookCard extends StatelessWidget {
  const NotebookCard({
    super.key,
    required this.document,
    required this.onTap,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
    required this.onToggleFavorite,
    required this.onChangeColor,
  });

  final InkDocument document;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;
  final ValueChanged<int> onChangeColor;

  static const List<int> palette = [
    0xFF53657D,
    0xFFE56A5D,
    0xFF5B6FDE,
    0xFFE6BD4C,
    0xFF4D9A68,
    0xFF9B73C8,
    0xFF6AA7C8,
    0xFFD9869C,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(document.colorValue);
    final firstPage = document.pages.isEmpty
        ? <InkObject>[]
        : document.pages.first;

    return Semantics(
      button: true,
      label: 'Open ${document.title}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: firstPage.isEmpty
                                  ? Center(
                                      child: Icon(
                                        Icons.draw_outlined,
                                        size: 28,
                                        color: color.computeLuminance() > .55
                                            ? color.withValues(alpha: .60)
                                            : color.withValues(alpha: .45),
                                      ),
                                    )
                                  : IgnorePointer(
                                      child: CustomPaint(
                                        painter: InkPainter(strokes: firstPage),
                                        size: Size.infinite,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      if (document.isFavorite)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: .92),
                              shape: BoxShape.circle,
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.star_rounded,
                                size: 18,
                                color: Color(0xFFE0A400),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: _DocumentMenu(
                          document: document,
                          onRename: onRename,
                          onMove: onMove,
                          onDelete: onDelete,
                          onToggleFavorite: onToggleFavorite,
                          onChangeColor: onChangeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
                child: Text(
                  document.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.1,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                child: Text(
                  '${document.pages.length} page${document.pages.length == 1 ? '' : 's'} • ${formatNoteDate(document.updatedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentMenu extends StatelessWidget {
  const _DocumentMenu({
    required this.document,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
    required this.onToggleFavorite,
    required this.onChangeColor,
  });

  final InkDocument document;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;
  final ValueChanged<int> onChangeColor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Note actions',
      icon: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
          shape: BoxShape.circle,
        ),
        child: const Padding(
          padding: EdgeInsets.all(5),
          child: Icon(Icons.more_horiz_rounded, size: 19),
        ),
      ),
      onSelected: (action) {
        if (action == 'favorite') {
          onToggleFavorite();
        } else if (action == 'rename') {
          onRename();
        } else if (action == 'move') {
          onMove();
        } else if (action == 'delete') {
          onDelete();
        } else if (action.startsWith('color_')) {
          onChangeColor(int.parse(action.substring(6)));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'favorite',
          child: _MenuRow(
            icon: document.isFavorite
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            label: document.isFavorite ? 'Remove favorite' : 'Add to favorites',
          ),
        ),
        const PopupMenuItem(
          value: 'rename',
          child: _MenuRow(
            icon: Icons.edit_outlined,
            label: 'Rename',
          ),
        ),
        const PopupMenuItem(
          value: 'move',
          child: _MenuRow(
            icon: Icons.drive_file_move_outline,
            label: 'Move to folder',
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          enabled: false,
          height: 34,
          child: Text(
            'Cover color',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        for (final value in NotebookCard.palette)
          PopupMenuItem(
            value: 'color_$value',
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Color(value),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: value == document.colorValue
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  value == document.colorValue
                      ? 'Current color'
                      : 'Use this color',
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: _MenuRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            destructive: true,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

String formatNoteDate(DateTime value) {
  final now = DateTime.now();
  final local = value.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final difference = today.difference(date).inDays;

  if (difference == 0) {
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return 'Today $hour:$minute';
  }
  if (difference == 1) return 'Yesterday';
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}
