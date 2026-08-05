import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import 'ink_painter.dart';

class PageStrip extends StatelessWidget {
  const PageStrip({
    super.key,
    required this.pages,
    required this.pageBackgrounds,
    required this.pageAspectRatios,
    required this.currentPageIndex,
    required this.onSelectPage,
    required this.onAddPage,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final List<List<InkObject>> pages;
  final List<String?> pageBackgrounds;
  final List<double?> pageAspectRatios;
  final int currentPageIndex;
  final ValueChanged<int> onSelectPage;
  final VoidCallback onAddPage;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (collapsed) {
      return Container(
        width: 54,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            IconButton(
              tooltip: 'Open pages',
              onPressed: onToggleCollapsed,
              icon: const Icon(Icons.view_sidebar_outlined),
            ),
            IconButton(
              tooltip: 'Add page',
              onPressed: onAddPage,
              icon: const Icon(Icons.add_rounded),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: pages.length,
                itemBuilder: (context, index) {
                  final selected = index == currentPageIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 7),
                    child: InkWell(
                      onTap: () => onSelectPage(index),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? scheme.primaryContainer : null,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: selected ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 190,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Pages', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'Add page',
                  visualDensity: VisualDensity.compact,
                  onPressed: onAddPage,
                  icon: const Icon(Icons.add_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Collapse pages',
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleCollapsed,
                  icon: const Icon(Icons.chevron_left_rounded, size: 22),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: .58,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              itemCount: pages.length,
              itemBuilder: (context, index) {
                final selected = index == currentPageIndex;
                final savedRatio = index < pageAspectRatios.length
                    ? pageAspectRatios[index]
                    : null;
                final pageRatio = savedRatio != null &&
                        savedRatio.isFinite &&
                        savedRatio > .15
                    ? savedRatio.clamp(.15, 6.0).toDouble()
                    : 1.35;
                return InkWell(
                  onTap: () => onSelectPage(index),
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: AspectRatio(
                            aspectRatio: 1 / pageRatio,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? scheme.primary
                                      : Theme.of(context).dividerColor,
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (index < pageBackgrounds.length &&
                                        pageBackgrounds[index] != null)
                                      Image.file(
                                        File(pageBackgrounds[index]!),
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, _, _) =>
                                            const SizedBox(),
                                      ),
                                    if (pages[index].isNotEmpty)
                                      IgnorePointer(
                                        child: CustomPaint(
                                          painter: InkPainter(
                                            strokes: pages[index],
                                          ),
                                          size: Size.infinite,
                                        ),
                                      )
                                    else if (index >= pageBackgrounds.length ||
                                        pageBackgrounds[index] == null)
                                      Center(
                                        child: Icon(
                                          Icons.draw_outlined,
                                          color: Colors.grey
                                              .withValues(alpha: .35),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}

class CompactPageBar extends StatelessWidget {
  const CompactPageBar({
    super.key,
    required this.pageCount,
    required this.currentPageIndex,
    required this.onPrevious,
    required this.onNext,
    required this.onAddPage,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final int pageCount;
  final int currentPageIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onAddPage;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .10),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${currentPageIndex + 1} / $pageCount',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: Theme.of(context).dividerColor,
              ),
              IconButton(
                tooltip: 'Add page',
                onPressed: onAddPage,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
