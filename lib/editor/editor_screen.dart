import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../store.dart';
import 'ink_painter.dart';
import 'page_strip.dart';
import 'toolbar.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.document,
    required this.openDocuments,
    required this.activeDocumentId,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onNewTab,
    required this.onExit,
    required this.onDocumentSaved,
  });

  final InkDocument document;
  final List<InkDocument> openDocuments;
  final String activeDocumentId;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onNewTab;
  final VoidCallback onExit;
  final ValueChanged<InkDocument> onDocumentSaved;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late List<List<InkObject>> _pages;
  late List<String?> _pageBackgrounds;
  late List<double?> _pageAspectRatios;
  int _currentPageIndex = 0;

  final List<List<List<InkObject>>> _undo = [];
  final List<List<List<InkObject>>> _redo = [];

  InkStroke? _activeStroke;
  InkTool _tool = InkTool.pen;
  Color _color = const Color(0xFF17233C);
  Color _highlighterColor = const Color(0xFFFFFF73);
  double _width = 2;
  double _highlighterWidth = 14;
  double _smoothing = .45;
  double _pressureSensitivity = .7;
  double _eraserSize = 28;
  EraserMode _eraserMode = EraserMode.precision;
  bool _eraseHighlighterOnly = false;
  bool _eraserAutoDeselect = false;
  InkTool _lastDrawingTool = InkTool.pen;
  InkTool _lastPenTool = InkTool.pen;
  InkPoint? _eraserCursor;
  static const List<PenPreset> _defaultPenSizePresets = [
    PenPreset(size: 1.5, smoothing: .45),
    PenPreset(size: 2, smoothing: .45),
    PenPreset(size: 3, smoothing: .45),
  ];
  static const List<PenPreset> _defaultHighlighterSizePresets = [
    PenPreset(size: 8, smoothing: .45),
    PenPreset(size: 14, smoothing: .45),
    PenPreset(size: 20, smoothing: .45),
  ];

  List<PenPreset> _presets = List<PenPreset>.of(_defaultPenSizePresets);
  List<PenPreset> _highlighterPresets =
      List<PenPreset>.of(_defaultHighlighterSizePresets);
  List<Color> _colorPresets = List<Color>.of(_defaultColorPresets);
  List<Color> _highlighterColorPresets =
      List<Color>.of(_defaultHighlighterColorPresets);

  static const List<Color> _defaultColorPresets = [
    Color(0xFF000000), Color(0xFF5F6368), Color(0xFF9AA0A6),
    Color(0xFFDADCE0), Color(0xFFFFFFFF), Color(0xFF8E24AA),
    Color(0xFFE53935), Color(0xFFFF5A67), Color(0xFFFF8A8F),
    Color(0xFFFF9F1C), Color(0xFF1877F2), Color(0xFF0D55A5),
    Color(0xFF098765), Color(0xFF72C62B), Color(0xFFFFFF73),
    Color(0xFFB000F5), Color(0xFFF542B3), Color(0xFF49CBE8),
  ];
  static const List<Color> _defaultHighlighterColorPresets = [
    Color(0xFFFFFF73),
    Color(0xFFA7F36B),
    Color(0xFF70E1F5),
    Color(0xFFFF8FD1),
    Color(0xFFFFB45E),
    Color(0xFFC9A7FF),
    Color(0xFFFF6B6B),
  ];
  int? _activePointer;
  PointerDeviceKind? _activePointerKind;
  final Set<int> _touchPointers = <int>{};
  bool _normalizingTransform = false;
  bool _temporaryEraser = false;
  bool _interactionChanged = false;
  bool _dirty = false;
  Timer? _saveTimer;
  Timer? _lineAssistTimer;

  bool _zoomMode = false;
  bool _verticalPageMode = true;
  bool _pagesPanelCollapsed = true;
  bool _dashedStroke = false;
  double _textSize = 24;
  bool _textBold = false;
  bool _textItalic = false;
  TextAlign _textAlign = TextAlign.left;
  double _textLineHeight = 1.2;
  bool _straightLinePreview = false;
  final List<InkPoint> _lassoPath = [];
  bool _selectionMoveMode = false;
  List<InkObject> get _currentObjects => _pages[_currentPageIndex];

  double get _continuousViewScale => _continuousTransformationController
      .value
      .getMaxScaleOnAxis()
      .clamp(.55, 4.0)
      .toDouble();

  double get _eraserCanvasDiameter {
    final scale = _verticalPageMode
        ? _continuousViewScale
        : _transformationController.value
            .getMaxScaleOnAxis()
            .clamp(.5, 6.0)
            .toDouble();
    return _eraserSize / scale;
  }

  Offset? _lastSelectPosition;

  final GlobalKey _canvasKey = GlobalKey();
  final TransformationController _transformationController =
      TransformationController();
  final TransformationController _continuousTransformationController =
      TransformationController();
  double _continuousPaperWidth = 0;
  double _continuousGap = 8;
  double _continuousViewportWidth = 0;
  double _continuousViewportHeight = 0;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_handlePageTransformChanged);
    _continuousTransformationController.addListener(
      _handleContinuousTransformChanged,
    );
    _pages = widget.document.pages
        .map((page) => List<InkObject>.of(page))
        .toList();
    if (_pages.isEmpty) _pages.add([]);
    _pageBackgrounds = List<String?>.of(widget.document.pageBackgrounds);
    while (_pageBackgrounds.length < _pages.length) {
      _pageBackgrounds.add(null);
    }
    _pageAspectRatios = List<double?>.of(widget.document.pageAspectRatios);
    while (_pageAspectRatios.length < _pages.length) {
      _pageAspectRatios.add(null);
    }
    unawaited(_hydrateMissingPageAspectRatios());

    AppSettingsStore.load().then((settings) {
      if (!mounted) return;
      setState(() {
        _smoothing = settings.defaultSmoothing;
        _width = settings.defaultWidth;
      });
    });

    InkStore.loadPresets().then((saved) {
      if (mounted && saved.isNotEmpty) setState(() => _presets = saved);
    });

    InkStore.loadHighlighterPresets().then((saved) {
      if (mounted && saved.isNotEmpty) {
        setState(() => _highlighterPresets = saved);
      }
    });

    InkStore.loadColorPresets().then((saved) {
      if (!mounted || saved.isEmpty) return;
      setState(() => _colorPresets = saved);
    });

    InkStore.loadHighlighterColorPresets().then((saved) {
      if (!mounted || saved.isEmpty) return;
      setState(() => _highlighterColorPresets = saved);
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _lineAssistTimer?.cancel();
    unawaited(_saveDocument().then<void>((_) {}));
    _transformationController
      ..removeListener(_handlePageTransformChanged)
      ..dispose();
    _continuousTransformationController
      ..removeListener(_handleContinuousTransformChanged)
      ..dispose();
    super.dispose();
  }

  double _pageAspectRatio(int index) {
    final saved = index >= 0 && index < _pageAspectRatios.length
        ? _pageAspectRatios[index]
        : null;
    if (saved == null || !saved.isFinite || saved <= .15) return 1.35;
    return saved.clamp(.15, 6.0).toDouble();
  }

  Future<void> _hydrateMissingPageAspectRatios() async {
    final discovered = <int, double>{};
    for (var index = 0; index < _pages.length; index++) {
      if (_pageAspectRatios[index] != null) continue;
      final background = index < _pageBackgrounds.length
          ? _pageBackgrounds[index]
          : null;
      if (background == null) continue;

      try {
        final file = File(background);
        if (!await file.exists()) continue;
        final codec = await ui.instantiateImageCodec(
          await file.readAsBytes(),
          targetWidth: 24,
        );
        final frame = await codec.getNextFrame();
        final width = frame.image.width.toDouble();
        final height = frame.image.height.toDouble();
        frame.image.dispose();
        codec.dispose();
        if (width > 0 && height > 0) {
          discovered[index] = height / width;
        }
      } catch (_) {
        // Keep the default paper ratio if an old background cannot be decoded.
      }
    }

    if (!mounted || discovered.isEmpty) return;
    setState(() {
      for (final entry in discovered.entries) {
        _pageAspectRatios[entry.key] = entry.value;
      }
    });
    _scheduleSave();
  }

  List<List<InkObject>> _copyPages() =>
      _pages.map((page) => List<InkObject>.of(page)).toList();

  void _snapshot() {
    _undo.add(_copyPages());
    if (_undo.length > 50) _undo.removeAt(0);
    _redo.clear();
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveDocument().then<void>((_) {}));
    });
  }

  Future<bool> _saveDocument() async {
    if (!_dirty) return true;

    _dirty = false;
    final document = widget.document.copyWith(
      updatedAt: DateTime.now(),
      pages: _copyPages(),
      pageBackgrounds: List<String?>.of(_pageBackgrounds),
      pageAspectRatios: List<double?>.of(_pageAspectRatios),
    );

    try {
      await InkDocumentStore.save(document);
      widget.onDocumentSaved(document);
      return true;
    } catch (error) {
      _dirty = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this note: $error')),
        );
      }
      return false;
    }
  }

  Future<void> _saveThen(VoidCallback action) async {
    _saveTimer?.cancel();
    final saved = await _saveDocument();
    if (saved && mounted) action();
  }

  void _selectDocumentTab(String id) {
    if (id == widget.activeDocumentId) return;
    unawaited(_saveThen(() => widget.onSelectTab(id)));
  }

  void _closeDocumentTab(String id) {
    unawaited(_saveThen(() => widget.onCloseTab(id)));
  }

  void _newDocumentTab() {
    unawaited(_saveThen(widget.onNewTab));
  }

  void _exitEditor() {
    unawaited(_saveThen(widget.onExit));
  }

  void _setPenValues({
    required bool highlighter,
    double? width,
    double? smoothing,
    double? pressureSensitivity,
  }) {
    setState(() {
      if (width != null) {
        if (highlighter) {
          _highlighterWidth = width;
        } else {
          _width = width;
        }
      }
      if (smoothing != null) _smoothing = smoothing;
      if (pressureSensitivity != null) {
        _pressureSensitivity = pressureSensitivity;
      }
    });
  }

  List<PenPreset> _sizePresetsFor(bool highlighter) =>
      highlighter ? _highlighterPresets : _presets;

  double _activeWidthFor(bool highlighter) =>
      highlighter ? _highlighterWidth : _width;

  Future<double?> _showSizePresetEditor({
    required bool highlighter,
    required double initialValue,
    required bool adding,
  }) async {
    final minValue = highlighter ? 3.0 : .5;
    final maxValue = highlighter ? 32.0 : 12.0;
    final divisions = highlighter ? 58 : 23;
    var value = initialValue.clamp(minValue, maxValue).toDouble();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Close size preset editor',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final scheme = Theme.of(context).colorScheme;
            final media = MediaQuery.of(context);
            final compact = media.size.width < 650;
            final displayValue = value == value.roundToDouble()
                ? value.toStringAsFixed(0)
                : value.toStringAsFixed(1);

            void closeAndSave() => Navigator.of(dialogContext).pop();

            return Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: closeAndSave,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: compact ? 112 : 138,
                          left: 12,
                          right: 12,
                        ),
                        child: Material(
                          elevation: 20,
                          color: scheme.surface.withValues(alpha: .99),
                          shadowColor: Colors.black.withValues(alpha: .22),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                            side: BorderSide(
                              color: scheme.outlineVariant.withValues(alpha: .65),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SizedBox(
                            width: 360,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          adding
                                              ? 'Add size preset'
                                              : 'Edit size preset',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Save and close',
                                        onPressed: closeAndSave,
                                        icon: const Icon(Icons.check_rounded),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    height: 62,
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest
                                          .withValues(alpha: .4),
                                      borderRadius: BorderRadius.circular(17),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: (value * 2 + 8)
                                            .clamp(10, 58)
                                            .toDouble(),
                                        height: (value * 2 + 8)
                                            .clamp(10, 58)
                                            .toDouble(),
                                        decoration: BoxDecoration(
                                          color: scheme.onSurface,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Center(
                                    child: Text(
                                      '$displayValue pt',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Slider(
                                    value: value,
                                    min: minValue,
                                    max: maxValue,
                                    divisions: divisions,
                                    label: displayValue,
                                    onChanged: (nextValue) => setDialogState(
                                      () => value = nextValue,
                                    ),
                                  ),
                                  Text(
                                    'Tap outside to save and close automatically.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -.025),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

    return value;
  }

  Future<double?> _handleSizePresetTap({
    required bool highlighter,
    required int index,
  }) async {
    final presets = _sizePresetsFor(highlighter);
    if (index < 0 || index >= presets.length) return null;

    final preset = presets[index];
    final activeWidth = _activeWidthFor(highlighter);
    if ((activeWidth - preset.size).abs() >= .2) {
      _setPenValues(highlighter: highlighter, width: preset.size);
      return preset.size;
    }

    final replacement = await _showSizePresetEditor(
      highlighter: highlighter,
      initialValue: preset.size,
      adding: false,
    );
    if (!mounted || replacement == null) return null;

    final updated = List<PenPreset>.of(presets);
    updated[index] = PenPreset(
      size: replacement,
      smoothing: preset.smoothing,
    );
    setState(() {
      if (highlighter) {
        _highlighterPresets = updated;
        _highlighterWidth = replacement;
      } else {
        _presets = updated;
        _width = replacement;
      }
    });
    if (highlighter) {
      await InkStore.saveHighlighterPresets(updated);
    } else {
      await InkStore.savePresets(updated);
    }
    return replacement;
  }

  Future<double?> _addSizePreset({required bool highlighter}) async {
    final newValue = await _showSizePresetEditor(
      highlighter: highlighter,
      initialValue: _activeWidthFor(highlighter),
      adding: true,
    );
    if (!mounted || newValue == null) return null;

    final updated = [
      ..._sizePresetsFor(highlighter),
      PenPreset(size: newValue, smoothing: _smoothing),
    ];
    setState(() {
      if (highlighter) {
        _highlighterPresets = updated;
        _highlighterWidth = newValue;
      } else {
        _presets = updated;
        _width = newValue;
      }
    });
    if (highlighter) {
      await InkStore.saveHighlighterPresets(updated);
    } else {
      await InkStore.savePresets(updated);
    }
    return newValue;
  }

  bool _isPenTool(InkTool tool) =>
      tool == InkTool.pen ||
      tool == InkTool.fountainPen ||
      tool == InkTool.brushPen;

  bool _isPenFamilyTool(InkTool tool) =>
      _isPenTool(tool) || tool == InkTool.highlighter;

  bool _isDrawingTool(InkTool tool) => _isPenFamilyTool(tool);

  void _selectOrOpenPenSettings() {
    // Highlighter is a separate top-level tool. Pressing Pen while the
    // highlighter is active must return to the last real pen immediately.
    if (_tool == InkTool.highlighter) {
      setState(() {
        _tool = _isPenTool(_lastPenTool) ? _lastPenTool : InkTool.pen;
        _lastDrawingTool = _tool;
        _zoomMode = false;
        _activeStroke = null;
      });
      return;
    }

    if (_isPenTool(_tool) && !_zoomMode) {
      setState(() {
        // Pressing the active pen again enters read mode.
        _zoomMode = true;
        _activeStroke = null;
        _temporaryEraser = false;
        _eraserCursor = null;
      });
      return;
    }

    setState(() {
      _tool = _isPenTool(_lastPenTool) ? _lastPenTool : InkTool.pen;
      _lastPenTool = _tool;
      _lastDrawingTool = _tool;
      _zoomMode = false;
    });
  }

  Future<void> _showPenSettings() async {
    setState(() {
      if (!_isPenFamilyTool(_tool)) {
        _tool = _isPenFamilyTool(_lastDrawingTool)
            ? _lastDrawingTool
            : (_isPenTool(_lastPenTool) ? _lastPenTool : InkTool.pen);
      }
      if (_isPenTool(_tool)) _lastPenTool = _tool;
      _lastDrawingTool = _tool;
      _zoomMode = false;
    });

    var localWidth =
        _tool == InkTool.highlighter ? _highlighterWidth : _width;
    var localSmoothing = _smoothing;
    var localPressureSensitivity = _pressureSensitivity;
    var localColor =
        _tool == InkTool.highlighter ? _highlighterColor : _color;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Close pen tools settings',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final scheme = Theme.of(context).colorScheme;
            final media = MediaQuery.of(context);
            final compact = media.size.width < 650;
            final topOffset = media.padding.top + (compact ? 112.0 : 142.0);
            final maxPanelHeight = math.max(
              300.0,
              media.size.height - topOffset - 18,
            ).toDouble();
            final isHighlighter = _tool == InkTool.highlighter;
            final visibleColors = isHighlighter
                ? _highlighterColorPresets
                : _colorPresets.take(12).toList();
            final activeSizePresets = _sizePresetsFor(isHighlighter);
            final penName = switch (_tool) {
              InkTool.fountainPen => 'Fountain Pen',
              InkTool.brushPen => 'Brush Pen',
              InkTool.highlighter => 'Highlighter',
              _ => 'Ball Pen',
            };
            final penIcon = switch (_tool) {
              InkTool.fountainPen => Icons.edit_outlined,
              InkTool.brushPen => Icons.brush_outlined,
              InkTool.highlighter => Icons.border_color_outlined,
              _ => Icons.mode_edit_outline_rounded,
            };

            void selectPen(InkTool tool) {
              setState(() {
                _tool = tool;
                if (_isPenTool(tool)) _lastPenTool = tool;
                _lastDrawingTool = tool;
              });
              setDialogState(() {
                final selectingHighlighter = tool == InkTool.highlighter;
                localWidth =
                    selectingHighlighter ? _highlighterWidth : _width;
                localColor =
                    selectingHighlighter ? _highlighterColor : _color;
              });
            }

            return Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(dialogContext).pop(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 10 : 18,
                      compact ? 82 : 108,
                      compact ? 10 : 18,
                      12,
                    ),
                    child: Material(
                      elevation: 22,
                      shadowColor: Colors.black.withValues(alpha: .28),
                      color: scheme.surface.withValues(alpha: .985),
                      surfaceTintColor: scheme.surfaceTint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: .7),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 470,
                          maxHeight: maxPanelHeight,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      penIcon,
                                      color: scheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Pen tools',
                                          style: TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          penName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Close',
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest
                                      .withValues(alpha: .55),
                                  borderRadius: BorderRadius.circular(17),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _SettingModeChip(
                                        icon: Icons.mode_edit_outline_rounded,
                                        label: 'Ball',
                                        selected: _tool == InkTool.pen,
                                        onTap: () => selectPen(InkTool.pen),
                                      ),
                                    ),
                                    Expanded(
                                      child: _SettingModeChip(
                                        icon: Icons.edit_outlined,
                                        label: 'Fountain',
                                        selected: _tool == InkTool.fountainPen,
                                        onTap: () =>
                                            selectPen(InkTool.fountainPen),
                                      ),
                                    ),
                                    Expanded(
                                      child: _SettingModeChip(
                                        icon: Icons.brush_outlined,
                                        label: 'Brush',
                                        selected: _tool == InkTool.brushPen,
                                        onTap: () =>
                                            selectPen(InkTool.brushPen),
                                      ),
                                    ),
                                    Expanded(
                                      child: _SettingModeChip(
                                        icon: Icons.border_color_outlined,
                                        label: 'Highlight',
                                        selected:
                                            _tool == InkTool.highlighter,
                                        onTap: () =>
                                            selectPen(InkTool.highlighter),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                height: 72,
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: scheme.outlineVariant
                                        .withValues(alpha: .55),
                                  ),
                                ),
                                child: Center(
                                  child: SizedBox(
                                    width: 270,
                                    height: 58,
                                    child: CustomPaint(
                                      painter: _PenPreviewPainter(
                                        color: localColor,
                                        width: localWidth,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Thickness',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    localWidth.toStringAsFixed(1),
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (var presetIndex = 0;
                                        presetIndex < activeSizePresets.length;
                                        presetIndex++)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: _PenWidthChoice(
                                          width: activeSizePresets[presetIndex]
                                              .size,
                                          selected: (localWidth -
                                                      activeSizePresets[
                                                              presetIndex]
                                                          .size)
                                                  .abs() <
                                              .2,
                                          onTap: () async {
                                            final selectedWidth =
                                                await _handleSizePresetTap(
                                              highlighter: isHighlighter,
                                              index: presetIndex,
                                            );
                                            if (!dialogContext.mounted ||
                                                selectedWidth == null) {
                                              return;
                                            }
                                            setDialogState(
                                              () => localWidth = selectedWidth,
                                            );
                                          },
                                        ),
                                      ),
                                    IconButton.filledTonal(
                                      tooltip: 'Add size preset',
                                      onPressed: () async {
                                        final selectedWidth =
                                            await _addSizePreset(
                                          highlighter: isHighlighter,
                                        );
                                        if (!dialogContext.mounted ||
                                            selectedWidth == null) {
                                          return;
                                        }
                                        setDialogState(
                                          () => localWidth = selectedWidth,
                                        );
                                      },
                                      icon: const Icon(Icons.add_rounded),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Tap a size to use it. Tap the selected size again to edit and save it.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _SettingSection(
                                title: 'Stroke stabilization',
                                trailing: Text(
                                  '${(localSmoothing * 100).round()}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: Slider(
                                  value: localSmoothing,
                                  min: 0,
                                  max: 1,
                                  divisions: 20,
                                  onChanged: (value) {
                                    setDialogState(
                                      () => localSmoothing = value,
                                    );
                                    _setPenValues(
                                      highlighter: isHighlighter,
                                      smoothing: value,
                                    );
                                  },
                                ),
                              ),
                              if (!isHighlighter) ...[
                                const SizedBox(height: 10),
                                _SettingSection(
                                  title: 'Pressure sensitivity',
                                  trailing: Text(
                                    '${(localPressureSensitivity * 100).round()}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  child: Slider(
                                    value: localPressureSensitivity,
                                    min: 0,
                                    max: 1,
                                    divisions: 20,
                                    onChanged: (value) {
                                      setDialogState(
                                        () => localPressureSensitivity = value,
                                      );
                                      _setPenValues(
                                        highlighter: false,
                                        pressureSensitivity: value,
                                      );
                                    },
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              const Text(
                                'Color',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 9,
                                runSpacing: 9,
                                children: [
                                  for (var colorIndex = 0;
                                      colorIndex < visibleColors.length;
                                      colorIndex++)
                                    _FloatingColorButton(
                                      color: visibleColors[colorIndex],
                                      selected: visibleColors[colorIndex]
                                              .toARGB32() ==
                                          localColor.toARGB32(),
                                      onTap: () async {
                                        final itemColor =
                                            visibleColors[colorIndex];
                                        final alreadySelected =
                                            itemColor.toARGB32() ==
                                                localColor.toARGB32();
                                        if (!alreadySelected) {
                                          setState(() {
                                            if (isHighlighter) {
                                              _highlighterColor = itemColor;
                                            } else {
                                              _color = itemColor;
                                            }
                                          });
                                          setDialogState(
                                            () => localColor = itemColor,
                                          );
                                          return;
                                        }

                                        final replacement =
                                            await _replaceQuickColorSlot(
                                          highlighter: isHighlighter,
                                          index: colorIndex,
                                          initialColor: itemColor,
                                        );
                                        if (!dialogContext.mounted ||
                                            replacement == null) {
                                          return;
                                        }
                                        setDialogState(
                                          () => localColor = replacement,
                                        );
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'Tap the selected color again to replace it',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              if (!isHighlighter) ...[
                                const SizedBox(height: 12),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text(
                                    'Dashed stroke',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  value: _dashedStroke,
                                  onChanged: (value) {
                                    setState(() => _dashedStroke = value);
                                    setDialogState(() {});
                                  },
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Spacer(),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(),
                                    child: const Text('Done'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ],
            ),
          );
          },
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -.035),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: .97, end: 1).animate(curved),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );

    final settings = await AppSettingsStore.load();
    await AppSettingsStore.save(
      settings.copyWith(
        defaultSmoothing: _smoothing,
        defaultWidth: _width,
      ),
    );
  }

  bool _isStylus(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  bool _accept(PointerEvent event) {
    if (_zoomMode) return false;
    if (_isStylus(event) || event.kind == PointerDeviceKind.mouse) return true;
    // Finger input is navigation in every tool. Apple Pencil/stylus remains
    // responsible for writing, erasing, selecting, and placing text.
    if (event.kind == PointerDeviceKind.touch) return false;
    return false;
  }

  Widget _protectStylusDrawingFromViewportPan(Widget child) {
    if (_zoomMode) return child;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(
            supportedDevices: const <PointerDeviceKind>{
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
              PointerDeviceKind.mouse,
            },
          ),
          (_) {},
        ),
      },
      child: child,
    );
  }

  bool _eventIsEraser(PointerEvent event) {
    return _tool == InkTool.eraser ||
        event.kind == PointerDeviceKind.invertedStylus ||
        (event.buttons & kPrimaryStylusButton) != 0 ||
        (event.buttons & kSecondaryStylusButton) != 0;
  }

  double _pressure(PointerEvent event) {
    final range = event.pressureMax - event.pressureMin;
    if (range <= 0 || event.kind == PointerDeviceKind.mouse) return .5;
    final normalized = (event.pressure - event.pressureMin) / range;
    if (!normalized.isFinite) return .5;
    return normalized.clamp(.03, 1.0);
  }

  InkPoint _point(PointerEvent event, Size size) {
    return InkPoint(
      (event.localPosition.dx / size.width).clamp(0, 1),
      (event.localPosition.dy / size.height).clamp(0, 1),
      _pressure(event),
    );
  }

  InkPoint _smoothedPoint(PointerEvent event, Size size) {
    final raw = _point(event, size);
    final points = _activeStroke?.points;
    if (points == null || points.isEmpty) return raw;
    return smoothInkPoint(points.last, raw, _smoothing);
  }

  void _appendSmoothedPoints(PointerMoveEvent event, Size size) {
    final stroke = _activeStroke;
    if (stroke == null || stroke.points.isEmpty) return;

    final start = stroke.points.last;
    final target = _smoothedPoint(event, size);
    final dxPixels = (target.x - start.x) * size.width;
    final dyPixels = (target.y - start.y) * size.height;
    final distancePixels = math.sqrt(
      dxPixels * dxPixels + dyPixels * dyPixels,
    );
    if (distancePixels < .15) return;

    // Keep the real Pencil samples as the dominant control points. Adding too
    // many collinear points makes every sample boundary visible after zooming.
    // Only bridge genuinely large gaps; the painter creates the smooth curve.
    final sampleSpacing = 3.2 + (1 - _smoothing) * 1.8;
    final steps =
        (distancePixels / sampleSpacing).ceil().clamp(1, 8).toInt();
    for (var step = 1; step <= steps; step++) {
      final amount = step / steps;
      stroke.points.add(
        InkPoint(
          start.x + (target.x - start.x) * amount,
          start.y + (target.y - start.y) * amount,
          start.pressure + (target.pressure - start.pressure) * amount,
        ),
      );
    }
  }

  void _cancelLineAssist() {
    _lineAssistTimer?.cancel();
    _lineAssistTimer = null;
  }

  bool get _canStraightenActiveStroke =>
      _activeStroke != null &&
      (_activeStroke!.tool == InkTool.pen ||
          _activeStroke!.tool == InkTool.fountainPen ||
          _activeStroke!.tool == InkTool.brushPen ||
          _activeStroke!.tool == InkTool.highlighter) &&
      _activeStroke!.points.length >= 2;

  void _restartLineAssistTimer() {
    _cancelLineAssist();
    if (!_canStraightenActiveStroke) return;
    _lineAssistTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || !_canStraightenActiveStroke) return;
      setState(_straightenActiveStroke);
    });
  }

  void _straightenActiveStroke() {
    final stroke = _activeStroke;
    if (stroke == null || stroke.points.length < 2) return;
    _activeStroke = stroke.copyWith(
      points: [stroke.points.first, stroke.points.last],
    );
    _straightLinePreview = true;
  }

  void _zoomBy(double factor) {
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(1.0, 6.0);
    final normalized = nextScale / currentScale;
    matrix.scaleByDouble(normalized, normalized, normalized, 1.0);
    _transformationController.value = matrix;
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _zoomContinuousBy(double factor) {
    if (_continuousViewportWidth <= 0 || _continuousViewportHeight <= 0) {
      return;
    }
    final controller = _continuousTransformationController;
    final currentScale = _continuousViewScale;
    final nextScale = (currentScale * factor).clamp(.55, 4.0).toDouble();
    if ((nextScale - currentScale).abs() < .001) return;

    final focal = Offset(
      _continuousViewportWidth / 2,
      _continuousViewportHeight / 2,
    );
    final scenePoint = controller.toScene(focal);
    controller.value = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(nextScale, nextScale, nextScale, 1.0)
      ..translateByDouble(-scenePoint.dx, -scenePoint.dy, 0, 1);
  }

  void _zoomEditorBy(double factor) {
    if (_verticalPageMode) {
      _zoomContinuousBy(factor);
    } else {
      _zoomBy(factor);
    }
  }

  void _resetEditorZoom() {
    if (_verticalPageMode) {
      _continuousTransformationController.value = Matrix4.identity();
      _scrollContinuousViewToPage(_currentPageIndex);
    } else {
      _resetZoom();
    }
  }

  void _cancelTouchInteractionForPinch() {
    if (_activePointerKind != PointerDeviceKind.touch) return;
    _cancelLineAssist();

    // A drawing/edit snapshot is created when the first finger goes down.
    // Restore it so starting a two-finger gesture never leaves a stray mark.
    if (_undo.isNotEmpty) {
      _pages = _undo.removeLast();
    }

    setState(() {
      _activeStroke = null;
      _activePointer = null;
      _activePointerKind = null;
      _temporaryEraser = false;
      _eraserCursor = null;
      _interactionChanged = false;
      _lastSelectPosition = null;
      _lassoPath.clear();
      _straightLinePreview = false;
    });
  }

  void _pointerDown(PointerDownEvent event, Size size) {

    if (event.kind == PointerDeviceKind.touch) {
      _touchPointers.add(event.pointer);
      if (_touchPointers.length >= 2) {
        _cancelTouchInteractionForPinch();
        return;
      }
    }

    if (_activePointer != null) {
      final stylusReplacingPalm =
          _isStylus(event) && _activePointerKind == PointerDeviceKind.touch;
      if (!stylusReplacingPalm) return;
      _activeStroke = null;
      _activePointer = null;
      _activePointerKind = null;
    }
    if (!_accept(event)) return;

    final point = _point(event, size);
    if (_tool == InkTool.text) {
      unawaited(_handleTextTap(point));
      return;
    }

    _activePointer = event.pointer;
    _activePointerKind = event.kind;
    _temporaryEraser = _eventIsEraser(event);
    _interactionChanged = false;
    _snapshot();

    setState(() {
      if (_tool == InkTool.lasso) {
        _lastSelectPosition = Offset(point.x, point.y);
        if (_selectionMoveMode && _hasSelection) {
          _lassoPath.clear();
        } else {
          _selectionMoveMode = false;
          _clearSelection();
          _lassoPath
            ..clear()
            ..add(point);
        }
      } else if (_temporaryEraser) {
        _eraserCursor = point;
        _interactionChanged = _eraseAt(point, size);
      } else {
        _clearSelection();
        final activeTool = _tool == InkTool.highlighter
            ? InkTool.highlighter
            : _tool == InkTool.shape
                ? InkTool.shape
                : _tool == InkTool.fountainPen
                    ? InkTool.fountainPen
                    : _tool == InkTool.brushPen
                        ? InkTool.brushPen
                        : InkTool.pen;
        _activeStroke = InkStroke(
          tool: activeTool,
          color: activeTool == InkTool.highlighter
              ? _highlighterColor
              : _color,
          width: activeTool == InkTool.highlighter
              ? _highlighterWidth
              : _width,
          points: [point],
          dashed: activeTool == InkTool.highlighter ? false : _dashedStroke,
          pressureSensitivity: _pressureSensitivity,
        );
        _straightLinePreview = false;
        _interactionChanged = true;
      }
    });
    _restartLineAssistTimer();
  }

  void _clearSelection() {
    for (var index = 0; index < _currentObjects.length; index++) {
      if (_currentObjects[index].isSelected) {
        _currentObjects[index] =
            _currentObjects[index].copyWith(isSelected: false);
      }
    }
  }

  bool get _hasSelection => _currentObjects.any((item) => item.isSelected);

  void _moveSelection(double dx, double dy) {
    for (var index = 0; index < _currentObjects.length; index++) {
      final object = _currentObjects[index];
      if (!object.isSelected) continue;
      if (object is InkStroke) {
        _currentObjects[index] = object.copyWith(
          points: object.points
              .map(
                (item) => InkPoint(
                  (item.x + dx).clamp(0, 1),
                  (item.y + dy).clamp(0, 1),
                  item.pressure,
                ),
              )
              .toList(),
          isSelected: true,
        );
      } else if (object is InkText) {
        _currentObjects[index] = object.copyWith(
          x: (object.x + dx).clamp(0, 1),
          y: (object.y + dy).clamp(0, 1),
          isSelected: true,
        );
      }
    }
  }

  bool _pointInPolygon(InkPoint point, List<InkPoint> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects = ((a.y > point.y) != (b.y > point.y)) &&
          (point.x <
              (b.x - a.x) * (point.y - a.y) / ((b.y - a.y).abs() < 1e-9 ? 1e-9 : b.y - a.y) +
                  a.x);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  void _selectInsideLasso() {
    for (var index = 0; index < _currentObjects.length; index++) {
      final object = _currentObjects[index];
      bool selected;
      if (object is InkStroke) {
        selected = object.points.any((point) => _pointInPolygon(point, _lassoPath));
      } else if (object is InkText) {
        selected = _pointInPolygon(
          InkPoint(object.x, object.y, 1),
          _lassoPath,
        );
      } else {
        selected = false;
      }
      _currentObjects[index] = object.copyWith(isSelected: selected);
    }
  }

  void _removeSelection() {
    if (!_hasSelection) return;
    _snapshot();
    setState(() {
      _currentObjects.removeWhere((item) => item.isSelected);
      _selectionMoveMode = false;
    });
    _scheduleSave();
  }

  void _recolorSelection(Color color) {
    if (!_hasSelection) return;
    _snapshot();
    setState(() {
      for (var index = 0; index < _currentObjects.length; index++) {
        final object = _currentObjects[index];
        if (!object.isSelected) continue;
        if (object is InkStroke) {
          _currentObjects[index] = object.copyWith(color: color, isSelected: true);
        } else if (object is InkText) {
          _currentObjects[index] = object.copyWith(color: color, isSelected: true);
        }
      }
    });
    _scheduleSave();
  }

  void _resizeSelection(double multiplier) {
    if (!_hasSelection) return;
    _snapshot();
    setState(() {
      for (var index = 0; index < _currentObjects.length; index++) {
        final object = _currentObjects[index];
        if (!object.isSelected) continue;
        if (object is InkStroke) {
          _currentObjects[index] = object.copyWith(
            width: (object.width * multiplier).clamp(.5, 24),
            isSelected: true,
          );
        } else if (object is InkText) {
          _currentObjects[index] = object.copyWith(
            fontSize: (object.fontSize * multiplier).clamp(8, 160),
            isSelected: true,
          );
        }
      }
    });
    _scheduleSave();
  }

  Future<void> _handleTextTap(InkPoint point) async {
    final text = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => const _AddTextDialog(),
    );

    if (!mounted || text == null || text.trim().isEmpty) return;
    _snapshot();
    setState(() {
      _clearSelection();
      _currentObjects.add(
        InkText(
          text: text.trim(),
          x: point.x,
          y: point.y,
          color: _color,
          fontSize: _textSize,
          bold: _textBold,
          italic: _textItalic,
          textAlign: _textAlign,
          lineHeight: _textLineHeight,
        ),
      );
    });
    _scheduleSave();
  }

  void _pointerMove(PointerMoveEvent event, Size size) {
    if (_activePointer != event.pointer) return;
    final point = _point(event, size);

    setState(() {
      if (_tool == InkTool.lasso && _lastSelectPosition != null) {
        if (_selectionMoveMode && _hasSelection) {
          final dx = point.x - _lastSelectPosition!.dx;
          final dy = point.y - _lastSelectPosition!.dy;
          _moveSelection(dx, dy);
          _interactionChanged = true;
          _lastSelectPosition = Offset(point.x, point.y);
        } else {
          _lassoPath.add(point);
        }
      } else if (_temporaryEraser) {
        final previous = _eraserCursor;
        final erased = previous == null
            ? _eraseAt(point, size)
            : _eraseAlongPath(previous, point, size);
        _eraserCursor = point;
        _interactionChanged = erased || _interactionChanged;
      } else if (_activeStroke != null) {
        if (_straightLinePreview && _activeStroke!.points.length >= 2) {
          _activeStroke = _activeStroke!.copyWith(
            points: [_activeStroke!.points.first, _point(event, size)],
          );
        } else {
          _appendSmoothedPoints(event, size);
          _restartLineAssistTimer();
        }
        _interactionChanged = true;
      }
    });
  }

  void _pointerUp(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _touchPointers.remove(event.pointer);
    }
    if (_activePointer != event.pointer) return;
    _cancelLineAssist();
    setState(() {
      if (_tool == InkTool.lasso &&
          !_selectionMoveMode &&
          _lassoPath.length >= 3) {
        _selectInsideLasso();
      }
      if (_activeStroke != null) _currentObjects.add(_activeStroke!);
      final autoReturnToPen =
          _eraserAutoDeselect && _tool == InkTool.eraser;
      _activeStroke = null;
      _activePointer = null;
      _activePointerKind = null;
      _temporaryEraser = false;
      _eraserCursor = null;
      _lastSelectPosition = null;
      if (_tool == InkTool.lasso) _lassoPath.clear();
      if (autoReturnToPen) _tool = _lastDrawingTool;
      _straightLinePreview = false;
    });
    if (_interactionChanged) {
      _scheduleSave();
    } else if (_undo.isNotEmpty) {
      _undo.removeLast();
    }
  }

  bool _eraseAlongPath(InkPoint start, InkPoint end, Size size) {
    final dx = (end.x - start.x) * size.width;
    final dy = (end.y - start.y) * size.height;
    final distance = math.sqrt(dx * dx + dy * dy);
    final spacing = math.max(2.0, _eraserSize * .16);
    final steps = (distance / spacing).ceil().clamp(1, 40).toInt();
    var changed = false;
    for (var step = 1; step <= steps; step++) {
      final amount = step / steps;
      changed = _eraseAt(
            InkPoint(
              start.x + (end.x - start.x) * amount,
              start.y + (end.y - start.y) * amount,
              1,
            ),
            size,
          ) ||
          changed;
    }
    return changed;
  }

  double _distanceToSegment(Offset point, Offset start, Offset end) {
    final delta = end - start;
    final lengthSquared = delta.distanceSquared;
    if (lengthSquared <= .00001) return (point - start).distance;
    final projection = ((point - start).dx * delta.dx +
            (point - start).dy * delta.dy) /
        lengthSquared;
    final amount = projection.clamp(0.0, 1.0).toDouble();
    return (point - (start + delta * amount)).distance;
  }

  bool _strokeTouchesEraser(
    InkStroke stroke,
    Offset center,
    Size size,
    double radius,
    double strokeScale,
  ) {
    if (stroke.points.isEmpty) return false;
    final hitRadius = radius + stroke.width * strokeScale / 2;
    final offsets = stroke.points
        .map((candidate) => Offset(
              candidate.x * size.width,
              candidate.y * size.height,
            ))
        .toList();
    if (offsets.length == 1) {
      return (offsets.first - center).distance <= hitRadius;
    }
    for (var index = 0; index < offsets.length - 1; index++) {
      if (_distanceToSegment(center, offsets[index], offsets[index + 1]) <=
          hitRadius) {
        return true;
      }
    }
    return false;
  }

  List<InkPoint> _densifyStrokeForErasing(
    InkStroke stroke,
    Size size,
  ) {
    if (stroke.points.length < 2) return List<InkPoint>.of(stroke.points);
    final result = <InkPoint>[];
    for (var index = 0; index < stroke.points.length - 1; index++) {
      final start = stroke.points[index];
      final end = stroke.points[index + 1];
      final dx = (end.x - start.x) * size.width;
      final dy = (end.y - start.y) * size.height;
      final distance = math.sqrt(dx * dx + dy * dy);
      final steps = (distance / 1.8).ceil().clamp(1, 160).toInt();
      for (var step = 0; step < steps; step++) {
        final amount = step / steps;
        result.add(
          InkPoint(
            start.x + (end.x - start.x) * amount,
            start.y + (end.y - start.y) * amount,
            start.pressure + (end.pressure - start.pressure) * amount,
          ),
        );
      }
    }
    result.add(stroke.points.last);
    return result;
  }

  bool _eraseAt(InkPoint point, Size size) {
    final viewScale = _verticalPageMode
        ? _continuousViewScale
        : _transformationController.value
            .getMaxScaleOnAxis()
            .clamp(.5, 6.0)
            .toDouble();
    final radius = (_eraserSize / 2) / viewScale;
    const strokeScale = 1.0;
    final center = Offset(point.x * size.width, point.y * size.height);
    final newObjects = <InkObject>[];
    var changed = false;

    for (final object in _currentObjects) {
      // The ink eraser does not delete typed text. Text is removed with the
      // lasso, matching the behavior users expect from note-taking apps.
      if (object is! InkStroke) {
        newObjects.add(object);
        continue;
      }
      if (_eraseHighlighterOnly && object.tool != InkTool.highlighter) {
        newObjects.add(object);
        continue;
      }

      final touches = _strokeTouchesEraser(
        object,
        center,
        size,
        radius,
        strokeScale,
      );
      if (!touches) {
        newObjects.add(object);
        continue;
      }

      changed = true;
      if (_eraserMode == EraserMode.stroke ||
          object.tool == InkTool.shape ||
          object.points.length < 2) {
        continue;
      }

      final hitRadius = radius + object.width * strokeScale / 2;
      final workingPoints = _densifyStrokeForErasing(object, size);
      final hitPoints = List<bool>.filled(workingPoints.length, false);
      final offsets = workingPoints
          .map((candidate) => Offset(
                candidate.x * size.width,
                candidate.y * size.height,
              ))
          .toList();
      for (var index = 0; index < offsets.length; index++) {
        if ((offsets[index] - center).distance <= hitRadius) {
          hitPoints[index] = true;
        }
      }
      for (var index = 0; index < offsets.length - 1; index++) {
        if (_distanceToSegment(center, offsets[index], offsets[index + 1]) <=
            hitRadius) {
          hitPoints[index] = true;
          hitPoints[index + 1] = true;
        }
      }

      var fragment = <InkPoint>[];
      void finishFragment() {
        if (fragment.length >= 2) {
          newObjects.add(
            object.copyWith(
              points: List<InkPoint>.of(fragment),
              isSelected: false,
            ),
          );
        }
        fragment = <InkPoint>[];
      }

      for (var index = 0; index < workingPoints.length; index++) {
        if (hitPoints[index]) {
          finishFragment();
        } else {
          fragment.add(workingPoints[index]);
        }
      }
      finishFragment();
    }

    if (changed) _pages[_currentPageIndex] = newObjects;
    return changed;
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_copyPages());
      _pages = _undo.removeLast();
      _currentPageIndex =
          math.min(_currentPageIndex, _pages.length - 1);
      _activeStroke = null;
    });
    _scheduleSave();
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_copyPages());
      _pages = _redo.removeLast();
      _currentPageIndex =
          math.min(_currentPageIndex, _pages.length - 1);
      _activeStroke = null;
    });
    _scheduleSave();
  }

  void _selectPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    setState(() {
      _currentPageIndex = index;
      _activeStroke = null;
      _resetZoom();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollContinuousViewToPage(index);
    });
  }

  double _continuousOffsetForPage(int index) {
    if (_continuousPaperWidth <= 0 || index <= 0) return 0;
    var offset = 0.0;
    final last = math.min(index, _pages.length);
    for (var page = 0; page < last; page++) {
      offset += _continuousPaperWidth * _pageAspectRatio(page) +
          _continuousGap;
    }
    return offset;
  }

  double get _continuousDocumentHeight {
    if (_continuousPaperWidth <= 0) return 0;
    var height = 0.0;
    for (var page = 0; page < _pages.length; page++) {
      height += _continuousPaperWidth * _pageAspectRatio(page);
      if (page < _pages.length - 1) height += _continuousGap;
    }
    return height;
  }

  int _continuousPageForOffset(double offset) {
    if (_pages.isEmpty || _continuousPaperWidth <= 0) return 0;
    var cursor = 0.0;
    for (var page = 0; page < _pages.length; page++) {
      final extent = _continuousPaperWidth * _pageAspectRatio(page) +
          (page < _pages.length - 1 ? _continuousGap : 0);
      if (offset < cursor + extent) return page;
      cursor += extent;
    }
    return _pages.length - 1;
  }

  void _scrollContinuousViewToPage(int index) {
    if (!_verticalPageMode ||
        _continuousPaperWidth <= 0 ||
        _continuousViewportHeight <= 0) {
      return;
    }
    final scale = _continuousViewScale;
    final maxOffset = math.max(
      0.0,
      _continuousDocumentHeight - _continuousViewportHeight / scale,
    );
    final target = _continuousOffsetForPage(index)
        .clamp(0.0, maxOffset)
        .toDouble();
    _continuousTransformationController.value = Matrix4.identity()
      ..translateByDouble(0, -target * scale, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1.0);
  }

  bool _keepPaperHorizontallyCentered(
    TransformationController controller,
  ) {
    if (_normalizingTransform) return false;
    final matrix = controller.value;
    final translation = matrix.getTranslation();
    if (translation.x.abs() < .05) return false;

    final scale = matrix.getMaxScaleOnAxis();
    _normalizingTransform = true;
    controller.value = Matrix4.identity()
      ..translateByDouble(0, translation.y, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1.0);
    _normalizingTransform = false;
    return true;
  }

  void _handlePageTransformChanged() {
    if (_normalizingTransform) return;
    _keepPaperHorizontallyCentered(_transformationController);
  }

  void _handleContinuousTransformChanged() {
    if (_normalizingTransform) return;
    if (_keepPaperHorizontallyCentered(
      _continuousTransformationController,
    )) {
      return;
    }
    if (!mounted ||
        !_verticalPageMode ||
        _continuousPaperWidth <= 0 ||
        _continuousViewportHeight <= 0) {
      return;
    }
    final matrix = _continuousTransformationController.value;
    final scale = matrix.getMaxScaleOnAxis().clamp(.55, 4.0).toDouble();
    final translation = matrix.getTranslation();
    final readingPoint =
        (_continuousViewportHeight * .42 - translation.y) / scale;
    final index = _continuousPageForOffset(readingPoint);
    if (index == _currentPageIndex) return;

    setState(() {
      _currentPageIndex = index;
      _activeStroke = null;
      _lassoPath.clear();
      _selectionMoveMode = false;
    });
  }

  void _activatePageForInput(int pageIndex) {
    if (pageIndex == _currentPageIndex) return;
    setState(() {
      _currentPageIndex = pageIndex;
      _activeStroke = null;
      _lassoPath.clear();
      _selectionMoveMode = false;
    });
  }

  void _togglePageMode() {
    setState(() => _verticalPageMode = !_verticalPageMode);
    if (_verticalPageMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollContinuousViewToPage(_currentPageIndex);
      });
    }
  }

  void _addPage() {
    _snapshot();
    setState(() {
      _pages.add([]);
      _pageBackgrounds.add(null);
      _pageAspectRatios.add(null);
      _currentPageIndex = _pages.length - 1;
      _activeStroke = null;
      _resetZoom();
    });
    if (_verticalPageMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollContinuousViewToPage(_currentPageIndex);
      });
    }
    _scheduleSave();
  }

  Future<void> _importPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Importing PDF…')),
    );

    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(sourcePath);
      final appDirectory = await getApplicationDocumentsDirectory();
      final importId = DateTime.now().microsecondsSinceEpoch;
      final targetDirectory = Directory(
        '${appDirectory.path}/ink_note_pdf/${widget.document.id}/$importId',
      );
      await targetDirectory.create(recursive: true);

      final importedPages = <List<InkObject>>[];
      final importedBackgrounds = <String?>[];
      final importedAspectRatios = <double?>[];
      for (var pageNumber = 1;
          pageNumber <= document.pagesCount;
          pageNumber++) {
        final page = await document.getPage(pageNumber);
        try {
          final rendered = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          if (rendered == null) continue;
          final output = File(
            '${targetDirectory.path}/page_$pageNumber.png',
          );
          await output.writeAsBytes(rendered.bytes, flush: true);
          importedPages.add(<InkObject>[]);
          importedBackgrounds.add(output.path);
          final ratio = page.width > 0 ? page.height / page.width : 1.35;
          importedAspectRatios.add(
            ratio.isFinite && ratio > .15 ? ratio.toDouble() : 1.35,
          );
        } finally {
          await page.close();
        }
      }

      if (importedPages.isEmpty) {
        throw StateError('The PDF did not contain a renderable page.');
      }

      _snapshot();
      setState(() {
        _pages.addAll(importedPages);
        _pageBackgrounds.addAll(importedBackgrounds);
        _pageAspectRatios.addAll(importedAspectRatios);
        _currentPageIndex = _pages.length - importedPages.length;
        _activeStroke = null;
        _resetZoom();
      });
      _scheduleSave();
      messenger.showSnackBar(
        SnackBar(content: Text('Imported ${importedPages.length} PDF pages')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not import PDF: $error')),
      );
    } finally {
      await document?.close();
    }
  }

  Future<void> _saveColorPresets() =>
      InkStore.saveColorPresets(_colorPresets);

  Future<void> _saveHighlighterColorPresets() =>
      InkStore.saveHighlighterColorPresets(_highlighterColorPresets);

  Future<Color?> _replaceQuickColorSlot({
    required bool highlighter,
    required int index,
    required Color initialColor,
  }) async {
    final replacement = await _showAdvancedColorPicker(
      initialColor,
      allowPresetActions: false,
    );
    if (!mounted || replacement == null) return null;

    setState(() {
      if (highlighter) {
        if (index < 0 || index >= _highlighterColorPresets.length) return;
        final updated = List<Color>.of(_highlighterColorPresets);
        updated[index] = replacement;
        _highlighterColorPresets = updated;
        _highlighterColor = replacement;
      } else {
        if (index < 0 || index >= _colorPresets.length) return;
        final updated = List<Color>.of(_colorPresets);
        updated[index] = replacement;
        _colorPresets = updated;
        _color = replacement;
      }
    });

    if (highlighter) {
      await _saveHighlighterColorPresets();
    } else {
      await _saveColorPresets();
    }
    return replacement;
  }

  Future<void> _handleQuickColorTap(Color itemColor) async {
    final highlighter = _tool == InkTool.highlighter;
    final currentColor = highlighter ? _highlighterColor : _color;
    final isSelected = itemColor.toARGB32() == currentColor.toARGB32();

    if (!isSelected) {
      setState(() {
        if (highlighter) {
          _highlighterColor = itemColor;
        } else {
          _color = itemColor;
        }
      });
      return;
    }

    final colors = highlighter ? _highlighterColorPresets : _colorPresets;
    final index = colors.indexWhere(
      (color) => color.toARGB32() == itemColor.toARGB32(),
    );
    if (index < 0) return;
    await _replaceQuickColorSlot(
      highlighter: highlighter,
      index: index,
      initialColor: itemColor,
    );
  }

  Future<void> _addColorPreset(Color color) async {
    if (_colorPresets.any((item) => item.toARGB32() == color.toARGB32())) return;
    setState(() => _colorPresets = [..._colorPresets, color]);
    await _saveColorPresets();
  }

  Future<void> _removeColorPreset(Color color) async {
    final index = _colorPresets.indexWhere(
      (item) => item.toARGB32() == color.toARGB32(),
    );
    if (index < _defaultColorPresets.length || index < 0) return;
    final updated = List<Color>.of(_colorPresets)..removeAt(index);
    setState(() => _colorPresets = updated);
    await _saveColorPresets();
  }

  Future<Color?> _showAdvancedColorPicker(
    Color initialColor, {
    bool canRemove = false,
    bool allowPresetActions = true,
  }) async {
    var hsv = HSVColor.fromColor(initialColor);

    return showGeneralDialog<Color>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Close color editor',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final scheme = Theme.of(context).colorScheme;
            final media = MediaQuery.of(context);
            final compact = media.size.width < 650;
            final selected = hsv.toColor();
            final hex = selected
                .toARGB32()
                .toRadixString(16)
                .padLeft(8, '0')
                .substring(2)
                .toUpperCase();

            void closeAndApply() =>
                Navigator.of(dialogContext).pop(selected);

            return Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: closeAndApply,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: compact ? 112 : 138,
                          left: 12,
                          right: 12,
                        ),
                        child: Material(
                          elevation: 22,
                          shadowColor: Colors.black.withValues(alpha: .24),
                          color: scheme.surface.withValues(alpha: .99),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: scheme.outlineVariant.withValues(alpha: .65),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: 470,
                              maxHeight: media.size.height -
                                  media.padding.vertical -
                                  (compact ? 132 : 158),
                            ),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Edit color',
                                          style: TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Apply and close',
                                        onPressed: closeAndApply,
                                        icon: const Icon(Icons.check_rounded),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: compact ? 230 : 270,
                                    child: _ColorWheelField(
                                      hsv: hsv,
                                      onChanged: (value) =>
                                          setDialogState(() => hsv = value),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: selected,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: scheme.outlineVariant,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 11,
                                          ),
                                          decoration: BoxDecoration(
                                            color: scheme.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            'HEX $hex',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (allowPresetActions) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        await _addColorPreset(selected);
                                      },
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                      ),
                                      label: const Text('Add to presets'),
                                    ),
                                  ],
                                  if (canRemove && allowPresetActions) ...[
                                    const SizedBox(height: 6),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: scheme.error,
                                      ),
                                      onPressed: () async {
                                        await _removeColorPreset(initialColor);
                                        if (dialogContext.mounted) {
                                          Navigator.of(dialogContext).pop();
                                        }
                                      },
                                      icon: const Icon(Icons.delete_outline_rounded),
                                      label: const Text('Remove color'),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap outside to apply and close automatically.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -.025),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<Color?> _showColorPalette(Color initialColor) async {
    final highlighter = _tool == InkTool.highlighter;

    return showGeneralDialog<Color>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Close color palette',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final scheme = Theme.of(context).colorScheme;
            final media = MediaQuery.of(context);
            final compact = media.size.width < 650;
            final colors = highlighter
                ? _highlighterColorPresets
                : _colorPresets;

            void closeWithoutChange() =>
                Navigator.of(dialogContext).pop(initialColor);

            return Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: closeWithoutChange,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: compact ? 112 : 138,
                          left: 12,
                          right: 12,
                        ),
                        child: Material(
                          elevation: 20,
                          shadowColor: Colors.black.withValues(alpha: .22),
                          color: scheme.surface.withValues(alpha: .99),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                            side: BorderSide(
                              color: scheme.outlineVariant.withValues(alpha: .65),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 470),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          highlighter
                                              ? 'Highlighter color'
                                              : 'Pen color',
                                          style: const TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Close',
                                        onPressed: closeWithoutChange,
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 8,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                    itemCount: colors.length + 1,
                                    itemBuilder: (context, index) {
                                      if (index == colors.length) {
                                        return _AddColorButton(
                                          onTap: () async {
                                            final selected =
                                                await _showAdvancedColorPicker(
                                              initialColor,
                                              allowPresetActions: !highlighter,
                                            );
                                            if (selected != null &&
                                                dialogContext.mounted) {
                                              Navigator.of(dialogContext)
                                                  .pop(selected);
                                            }
                                          },
                                        );
                                      }

                                      final color = colors[index];
                                      final custom = !highlighter &&
                                          index >= _defaultColorPresets.length;
                                      return _PaletteColorButton(
                                        color: color,
                                        selected: color.toARGB32() ==
                                            initialColor.toARGB32(),
                                        onTap: () => Navigator.of(dialogContext)
                                            .pop(color),
                                        onLongPress: custom
                                            ? () async {
                                                final replacement =
                                                    await _showAdvancedColorPicker(
                                                  color,
                                                  canRemove: true,
                                                );
                                                if (replacement != null &&
                                                    dialogContext.mounted) {
                                                  setDialogState(() {});
                                                }
                                              }
                                            : null,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Choose a color directly. Tap outside to close.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -.025),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _chooseDrawingColor() async {
    final isHighlighter = _tool == InkTool.highlighter;
    final selected = await _showColorPalette(
      isHighlighter ? _highlighterColor : _color,
    );
    if (selected != null && mounted) {
      setState(() {
        if (isHighlighter) {
          _highlighterColor = selected;
        } else {
          _color = selected;
        }
      });
    }
  }

  Future<void> _chooseSelectionColor() async {
    final selected = await _showColorPalette(_color);
    if (selected != null && mounted) _recolorSelection(selected);
  }

  Future<void> _exportAndShare() async {
    try {
      final context = _canvasKey.currentContext;
      if (context == null) throw StateError('Canvas is not ready');
      final boundary = context.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('Could not encode image');

      final safeTitle = widget.document.title
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/${safeTitle.isEmpty ? 'ink_note' : safeTitle}_page_${_currentPageIndex + 1}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: widget.document.title,
        sharePositionOrigin:
            boundary.localToGlobal(Offset.zero) & boundary.size,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export this page: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          if (wide)
            _DesktopEditorHeader(
              documents: widget.openDocuments,
              activeId: widget.activeDocumentId,
              onSelect: _selectDocumentTab,
              onClose: _closeDocumentTab,
              onNewTab: _newDocumentTab,
              onHome: _exitEditor,
              onShare: _exportAndShare,
              onImportPdf: _importPdf,
              verticalPageMode: _verticalPageMode,
              onTogglePageMode: _togglePageMode,
            )
          else
            _MobileEditorHeader(
              title: widget.document.title,
              onBack: _exitEditor,
              onShare: _exportAndShare,
              onImportPdf: _importPdf,
              verticalPageMode: _verticalPageMode,
              onTogglePageMode: _togglePageMode,
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      ColoredBox(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: .55),
                        child: LayoutBuilder(
                            builder: (context, viewportConstraints) {
                              Widget buildPage(
                                int pageIndex, {
                                Size? pageViewport,
                                double contentScale = 1.0,
                              }) {
                                final isCurrent = pageIndex == _currentPageIndex;
                                final effectiveViewport = pageViewport ??
                                    Size(
                                      viewportConstraints.maxWidth,
                                      viewportConstraints.maxHeight,
                                    );

                                Widget buildPaper() {
                                  final paperWidth = effectiveViewport.width;
                                  final paperHeight =
                                      paperWidth * _pageAspectRatio(pageIndex);
                                  return Align(
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      width: paperWidth,
                                      height: paperHeight,
                                      child: ColoredBox(
                                        color: Colors.white,
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                              final size = Size(
                                                constraints.maxWidth,
                                                constraints.maxHeight,
                                              );
                                              final canvas = RepaintBoundary(
                                                key: isCurrent ? _canvasKey : null,
                                                child: ColoredBox(
                                                  color: Colors.white,
                                                  child: Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      if (_pageBackgrounds[
                                                              pageIndex] !=
                                                          null)
                                                        Image.file(
                                                          File(
                                                            _pageBackgrounds[
                                                                pageIndex]!,
                                                          ),
                                                          fit: BoxFit.contain,
                                                          errorBuilder:
                                                              (_, _, _) =>
                                                                  const SizedBox(),
                                                        ),
                                                      CustomPaint(
                                                        painter: InkPainter(
                                                          strokes:
                                                              _pages[pageIndex],
                                                          activeStroke: isCurrent
                                                              ? _activeStroke
                                                              : null,
                                                          lassoPath: isCurrent
                                                              ? _lassoPath
                                                              : const <InkPoint>[],
                                                          template: widget
                                                              .document
                                                              .backgroundTemplate,
                                                          contentScale:
                                                              contentScale,
                                                          eraserCursor: isCurrent &&
                                                                  _temporaryEraser
                                                              ? _eraserCursor
                                                              : null,
                                                          eraserDiameter:
                                                              _eraserCanvasDiameter,
                                                        ),
                                                        size: Size.infinite,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );

                                              return _protectStylusDrawingFromViewportPan(
                                                Listener(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onPointerDown: (event) {
                                                    _activatePageForInput(
                                                      pageIndex,
                                                    );
                                                    _pointerDown(event, size);
                                                  },
                                                  onPointerMove: (event) =>
                                                      _pointerMove(event, size),
                                                  onPointerUp: _pointerUp,
                                                  onPointerCancel: _pointerUp,
                                                  child: canvas,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    );
                                }

                                if (_verticalPageMode) {
                                  // Keep each page gesture-neutral so the parent ListView
                                  // receives one-finger vertical drags like a blog feed.
                                  return buildPaper();
                                }

                                return InteractiveViewer(
                                  transformationController: isCurrent
                                      ? _transformationController
                                      : null,
                                  minScale: .1,
                                  maxScale: 6,
                                  boundaryMargin: const EdgeInsets.all(600),
                                  clipBehavior: Clip.hardEdge,
                                  constrained: false,
                                  alignment: Alignment.center,
                                  panEnabled: isCurrent,
                                  panAxis: PanAxis.vertical,
                                  scaleEnabled: isCurrent,
                                  trackpadScrollCausesScale: true,
                                  child: buildPaper(),
                                );
                              }

                              if (_verticalPageMode) {
                                final paperWidth = math.max(
                                  1.0,
                                  viewportConstraints.maxWidth,
                                );
                                const pageGap = 8.0;
                                var totalHeight = 0.0;
                                for (var index = 0;
                                    index < _pages.length;
                                    index++) {
                                  totalHeight += paperWidth *
                                      _pageAspectRatio(index);
                                  if (index < _pages.length - 1) {
                                    totalHeight += pageGap;
                                  }
                                }

                                _continuousPaperWidth = paperWidth;
                                _continuousGap = pageGap;
                                _continuousViewportWidth =
                                    viewportConstraints.maxWidth;
                                _continuousViewportHeight =
                                    viewportConstraints.maxHeight;

                                return InteractiveViewer(
                                  transformationController:
                                      _continuousTransformationController,
                                  minScale: .1,
                                  maxScale: 4,
                                  boundaryMargin: EdgeInsets.symmetric(
                                    horizontal:
                                        viewportConstraints.maxWidth * .75,
                                    vertical:
                                        viewportConstraints.maxHeight * .35,
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                  constrained: false,
                                  alignment: Alignment.center,
                                  // Touch always navigates with one finger;
                                  // the child gesture barrier keeps Pencil strokes
                                  // from moving the viewport.
                                  panEnabled: true,
                                  panAxis: PanAxis.vertical,
                                  scaleEnabled: true,
                                  trackpadScrollCausesScale: true,
                                  interactionEndFrictionCoefficient: .00008,
                                  child: SizedBox(
                                    width: paperWidth,
                                    height: totalHeight,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (var index = 0;
                                            index < _pages.length;
                                            index++) ...[
                                          SizedBox(
                                            width: paperWidth,
                                            height: paperWidth *
                                                _pageAspectRatio(index),
                                            child: buildPage(
                                              index,
                                              pageViewport: Size(
                                                paperWidth,
                                                paperWidth *
                                                    _pageAspectRatio(index),
                                              ),
                                            ),
                                          ),
                                          if (index < _pages.length - 1)
                                            const SizedBox(height: pageGap),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }

                              _continuousPaperWidth = 0;
                              _continuousGap = 8;
                              _continuousViewportWidth = 0;
                              _continuousViewportHeight = 0;
                              return buildPage(_currentPageIndex);
                            },
                          ),
                      ),
                      if (wide)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.surface.withValues(alpha: .96),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Theme.of(context).dividerColor),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: .06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: _pagesPanelCollapsed
                                          ? 'Open pages'
                                          : 'Hide pages',
                                      onPressed: () => setState(
                                        () => _pagesPanelCollapsed = !_pagesPanelCollapsed,
                                      ),
                                      icon: Icon(
                                        _pagesPanelCollapsed
                                            ? Icons.view_sidebar_outlined
                                            : Icons.view_sidebar_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    IconButton(
                                      tooltip: 'Undo',
                                      onPressed: _undo.isNotEmpty ? _undoAction : null,
                                      icon: const Icon(Icons.undo_rounded),
                                    ),
                                    IconButton(
                                      tooltip: 'Redo',
                                      onPressed: _redo.isNotEmpty ? _redoAction : null,
                                      icon: const Icon(Icons.redo_rounded),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_pagesPanelCollapsed) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: 212,
                                  height: math.min(
                                    MediaQuery.sizeOf(context).height - 150,
                                    360.0,
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    elevation: 0,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: PageStrip(
                                        pages: _pages,
                                        pageBackgrounds: _pageBackgrounds,
                                        pageAspectRatios: _pageAspectRatios,
                                        currentPageIndex: _currentPageIndex,
                                        onSelectPage: _selectPage,
                                        onAddPage: _addPage,
                                        collapsed: false,
                                        onToggleCollapsed: () => setState(
                                          () => _pagesPanelCollapsed = true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: FloatingEditorToolbar(
                            tool: _tool,
                            color: _tool == InkTool.highlighter
                                ? _highlighterColor
                                : _color,
                            width: _tool == InkTool.eraser
                                ? _eraserSize
                                : _tool == InkTool.highlighter
                                    ? _highlighterWidth
                                    : _width,
                            canUndo: _undo.isNotEmpty,
                            canRedo: _redo.isNotEmpty,
                            zoomMode: _zoomMode,
                            onTool: (tool) {
                              setState(() {
                                final comingFromUtility =
                                    _tool == InkTool.eraser ||
                                    _tool == InkTool.text ||
                                    _tool == InkTool.lasso;
                                final resolvedTool =
                                    tool == InkTool.pen && comingFromUtility
                                        ? _lastPenTool
                                        : tool;
                                _tool = resolvedTool;
                                if (_isDrawingTool(resolvedTool)) {
                                  _lastDrawingTool = resolvedTool;
                                }
                                if (_isPenTool(resolvedTool)) {
                                  _lastPenTool = resolvedTool;
                                }
                                _zoomMode = false;
                              });
                            },
                            onColor: (color) =>
                                unawaited(_handleQuickColorTap(color)),
                            onOpenColorPalette: _chooseDrawingColor,
                            paletteColors: _tool == InkTool.highlighter
                                ? _highlighterColorPresets
                                : _colorPresets.take(7).toList(),
                            onWidth: (width) => setState(() {
                              if (_tool == InkTool.eraser) {
                                _eraserSize = width;
                              } else if (_tool == InkTool.highlighter) {
                                _highlighterWidth = width;
                              } else {
                                _width = width;
                              }
                            }),
                            eraserMode: _eraserMode,
                            onEraserModeChanged: (value) =>
                                setState(() => _eraserMode = value),
                            eraseHighlighterOnly: _eraseHighlighterOnly,
                            onEraseHighlighterOnlyChanged: (value) => setState(
                              () => _eraseHighlighterOnly = value,
                            ),
                            eraserAutoDeselect: _eraserAutoDeselect,
                            onEraserAutoDeselectChanged: (value) => setState(
                              () => _eraserAutoDeselect = value,
                            ),
                            onPenTap: _selectOrOpenPenSettings,
                            onPenSettings: _showPenSettings,
                            onUndo: _undoAction,
                            onRedo: _redoAction,
                            onToggleZoomMode: () {
                              setState(() => _zoomMode = !_zoomMode);
                            },
                            presets: _presets,
                            highlighterPresets: _highlighterPresets,
                            onWidthPresetTap: (index) => unawaited(
                              _handleSizePresetTap(
                                highlighter: _tool == InkTool.highlighter,
                                index: index,
                              ),
                            ),
                            onAddWidthPreset: () => unawaited(
                              _addSizePreset(
                                highlighter: _tool == InkTool.highlighter,
                              ),
                            ),
                            onZoomIn: () => _zoomEditorBy(1.2),
                            onZoomOut: () => _zoomEditorBy(1 / 1.2),
                            onResetZoom: _resetEditorZoom,
                            dashed: _dashedStroke,
                            onDashedChanged: (value) =>
                                setState(() => _dashedStroke = value),
                            textSize: _textSize,
                            onTextSizeChanged: (value) =>
                                setState(() => _textSize = value),
                            textBold: _textBold,
                            onTextBoldChanged: (value) =>
                                setState(() => _textBold = value),
                            textItalic: _textItalic,
                            onTextItalicChanged: (value) =>
                                setState(() => _textItalic = value),
                            textAlign: _textAlign,
                            onTextAlignChanged: (value) =>
                                setState(() => _textAlign = value),
                            lineHeight: _textLineHeight,
                            onLineHeightChanged: (value) =>
                                setState(() => _textLineHeight = value),
                          ),
                        ),
                      ),
                      if (_tool == InkTool.lasso && _hasSelection)
                        Positioned(
                          top: 52,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _SelectionActions(
                              moveActive: _selectionMoveMode,
                              onMove: () => setState(
                                () => _selectionMoveMode = !_selectionMoveMode,
                              ),
                              onRemove: _removeSelection,
                              onColor: _recolorSelection,
                              onCustomColor: _chooseSelectionColor,
                              onSmaller: () => _resizeSelection(.8),
                              onLarger: () => _resizeSelection(1.25),
                            ),
                          ),
                        ),
                      if (!wide)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: CompactPageBar(
                            pageCount: _pages.length,
                            currentPageIndex: _currentPageIndex,
                            onPrevious: _currentPageIndex > 0
                                ? () => _selectPage(_currentPageIndex - 1)
                                : null,
                            onNext: _currentPageIndex < _pages.length - 1
                                ? () => _selectPage(_currentPageIndex + 1)
                                : null,
                            onAddPage: _addPage,
                            collapsed: _pagesPanelCollapsed,
                            onToggleCollapsed: () => setState(
                              () => _pagesPanelCollapsed = !_pagesPanelCollapsed,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteColorButton extends StatelessWidget {
  const _PaletteColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: .22),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                color: ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
              )
            : null,
      ),
    );
  }
}

class _AddColorButton extends StatelessWidget {
  const _AddColorButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline,
            width: 2,
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _ColorWheelField extends StatelessWidget {
  const _ColorWheelField({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, 330.0);
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (details) => _update(details.localPosition, side),
              onPanUpdate: (details) => _update(details.localPosition, side),
              onTapDown: (details) => _update(details.localPosition, side),
              child: CustomPaint(
                painter: _ColorWheelPainter(hsv),
              ),
            ),
          ),
        );
      },
    );
  }

  void _update(Offset position, double side) {
    final center = Offset(side / 2, side / 2);
    final delta = position - center;
    final radius = side / 2;
    final distance = delta.distance;
    final ringInner = radius * .78;

    if (distance >= ringInner) {
      var degrees = math.atan2(delta.dy, delta.dx) * 180 / math.pi + 90;
      if (degrees < 0) degrees += 360;
      onChanged(hsv.withHue(degrees));
      return;
    }

    final fieldRadius = radius * .62;
    final x = (delta.dx / fieldRadius).clamp(-1.0, 1.0);
    final y = (delta.dy / fieldRadius).clamp(-1.0, 1.0);
    final saturation = ((x + 1) / 2).clamp(0.0, 1.0);
    final value = (1 - ((y + 1) / 2)).clamp(0.0, 1.0);
    onChanged(
      HSVColor.fromAHSV(hsv.alpha, hsv.hue, saturation, value),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  const _ColorWheelPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final ringWidth = radius * .12;
    final ringRect = Rect.fromCircle(center: center, radius: radius - ringWidth);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..shader = const SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 3 / 2,
        colors: [
          Colors.red,
          Colors.yellow,
          Colors.green,
          Colors.cyan,
          Colors.blue,
          Colors.purple,
          Colors.red,
        ],
      ).createShader(ringRect);
    canvas.drawCircle(center, radius - ringWidth, ringPaint);

    final fieldRadius = radius * .62;
    final fieldRect = Rect.fromCircle(center: center, radius: fieldRadius);
    final base = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.45, -.45),
        radius: 1.25,
        colors: [
          Colors.white,
          HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
          Colors.black,
        ],
        stops: const [0, .58, 1],
      ).createShader(fieldRect);
    canvas.drawCircle(center, fieldRadius, base);

    final hueAngle = (hsv.hue - 90) * math.pi / 180;
    final hueCenter = center +
        Offset(math.cos(hueAngle), math.sin(hueAngle)) *
            (radius - ringWidth);
    canvas.drawCircle(
      hueCenter,
      ringWidth * .72,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      hueCenter,
      ringWidth * .72,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black26,
    );

    final selector = center +
        Offset(
          (hsv.saturation * 2 - 1) * fieldRadius,
          ((1 - hsv.value) * 2 - 1) * fieldRadius,
        );
    canvas.drawCircle(selector, 15, Paint()..color = hsv.toColor());
    canvas.drawCircle(
      selector,
      17,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white,
    );
    canvas.drawCircle(
      selector,
      19,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}

class _SelectionActions extends StatelessWidget {
  const _SelectionActions({
    required this.moveActive,
    required this.onMove,
    required this.onRemove,
    required this.onColor,
    required this.onCustomColor,
    required this.onSmaller,
    required this.onLarger,
  });

  final bool moveActive;
  final VoidCallback onMove;
  final VoidCallback onRemove;
  final ValueChanged<Color> onColor;
  final VoidCallback onCustomColor;
  final VoidCallback onSmaller;
  final VoidCallback onLarger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 10,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Move',
              onPressed: onMove,
              style: IconButton.styleFrom(
                backgroundColor: moveActive ? scheme.primaryContainer : null,
              ),
              icon: const Icon(Icons.open_with_rounded),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            PopupMenuButton<Color>(
              tooltip: 'Color',
              icon: const Icon(Icons.palette_outlined),
              onSelected: onColor,
              itemBuilder: (_) => const [
                PopupMenuItem(value: Colors.black, child: Text('Black')),
                PopupMenuItem(value: Colors.blue, child: Text('Blue')),
                PopupMenuItem(value: Colors.red, child: Text('Red')),
                PopupMenuItem(value: Colors.green, child: Text('Green')),
                PopupMenuItem(value: Colors.purple, child: Text('Purple')),
              ],
            ),
            IconButton(
              tooltip: 'Custom color',
              onPressed: onCustomColor,
              icon: const Icon(Icons.colorize_rounded),
            ),
            IconButton(
              tooltip: 'Smaller',
              onPressed: onSmaller,
              icon: const Icon(Icons.remove_rounded),
            ),
            IconButton(
              tooltip: 'Larger',
              onPressed: onLarger,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTextDialog extends StatefulWidget {
  const _AddTextDialog();

  @override
  State<_AddTextDialog> createState() => _AddTextDialogState();
}

class _AddTextDialogState extends State<_AddTextDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    Navigator.of(context).pop(value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add text'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(hintText: 'Type something…'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _PenPreviewPainter extends CustomPainter {
  const _PenPreviewPainter({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;
    final path = Path()
      ..moveTo(size.width * .1, size.height * .62)
      ..cubicTo(
        size.width * .28,
        size.height * .88,
        size.width * .52,
        size.height * .2,
        size.width * .85,
        size.height * .58,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PenPreviewPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.width != width;
}

class _SettingModeChip extends StatelessWidget {
  const _SettingModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingSection extends StatelessWidget {
  const _SettingSection({
    required this.title,
    required this.trailing,
    required this.child,
  });

  final String title;
  final Widget trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: .35),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              trailing,
            ],
          ),
          child,
        ],
      ),
    );
  }
}

class _PenWidthChoice extends StatelessWidget {
  const _PenWidthChoice({
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotSize = (width * 1.45 + 3).clamp(6.0, 18.0).toDouble();
    final label = width == width.roundToDouble()
        ? width.toStringAsFixed(0)
        : width.toStringAsFixed(1);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 48,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: .4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: scheme.onSurface,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingColorButton extends StatelessWidget {
  const _FloatingColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 31,
        height: 31,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primaryContainer : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: color.computeLuminance() > .88
                  ? scheme.outlineVariant
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileEditorHeader extends StatelessWidget {
  const _MobileEditorHeader({
    required this.title,
    required this.onBack,
    required this.onShare,
    required this.onImportPdf,
    required this.verticalPageMode,
    required this.onTogglePageMode,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onImportPdf;
  final bool verticalPageMode;
  final VoidCallback onTogglePageMode;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFF2F5EA7),
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back to notes',
              onPressed: onBack,
              color: Colors.white,
              icon: const BackButtonIcon(),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            IconButton(
              tooltip: verticalPageMode
                  ? 'Switch to page-by-page mode'
                  : 'Switch to continuous page scroll',
              onPressed: onTogglePageMode,
              color: Colors.white,
              icon: Icon(
                verticalPageMode
                    ? Icons.view_agenda_rounded
                    : Icons.filter_none_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Import PDF',
              onPressed: onImportPdf,
              color: Colors.white,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            IconButton(
              tooltip: 'Share page',
              onPressed: onShare,
              color: Colors.white,
              icon: const Icon(Icons.share_outlined),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _DesktopEditorHeader extends StatelessWidget {
  const _DesktopEditorHeader({
    required this.documents,
    required this.activeId,
    required this.onSelect,
    required this.onClose,
    required this.onNewTab,
    required this.onHome,
    required this.onShare,
    required this.onImportPdf,
    required this.verticalPageMode,
    required this.onTogglePageMode,
  });

  final List<InkDocument> documents;
  final String activeId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onNewTab;
  final VoidCallback onHome;
  final VoidCallback onShare;
  final VoidCallback onImportPdf;
  final bool verticalPageMode;
  final VoidCallback onTogglePageMode;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFF2F5EA7),
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back to notes',
              onPressed: onHome,
              color: Colors.white,
              icon: const BackButtonIcon(),
            ),
            Expanded(
              child: _DocumentTabStrip(
                documents: documents,
                activeId: activeId,
                onSelect: onSelect,
                onClose: onClose,
                onNewTab: onNewTab,
              ),
            ),
            IconButton(
              tooltip: verticalPageMode
                  ? 'Switch to page-by-page mode'
                  : 'Switch to continuous page scroll',
              onPressed: onTogglePageMode,
              color: Colors.white,
              icon: Icon(
                verticalPageMode
                    ? Icons.view_agenda_rounded
                    : Icons.filter_none_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Import PDF',
              onPressed: onImportPdf,
              color: Colors.white,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            IconButton(
              tooltip: 'Share page',
              onPressed: onShare,
              color: Colors.white,
              icon: const Icon(Icons.share_outlined),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _DocumentTabStrip extends StatelessWidget {
  const _DocumentTabStrip({
    required this.documents,
    required this.activeId,
    required this.onSelect,
    required this.onClose,
    required this.onNewTab,
  });

  final List<InkDocument> documents;
  final String activeId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onNewTab;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      children: [
        for (final document in documents)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Material(
              color: document.id == activeId
                  ? const Color(0xFF3E6CB8)
                  : const Color(0xFF2B4F8B),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => onSelect(document.id),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.only(left: 9),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 15,
                        color: Colors.white.withValues(alpha: document.id == activeId ? 1 : .85),
                      ),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 125),
                        child: Text(
                          document.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: document.id == activeId
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        tooltip: 'Close tab',
                        onPressed: () => onClose(document.id),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        IconButton(
          tooltip: 'Open a new note',
          onPressed: onNewTab,
          color: Colors.white,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
