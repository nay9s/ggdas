import 'dart:math' as math;

import 'package:flutter/material.dart';

enum InkTool { pen, fountainPen, brushPen, highlighter, eraser, lasso, shape, text, image }
enum EraserMode { precision, stroke }
enum BackgroundTemplate { blank, ruled, grid, dotted, cornell }
enum CoverStyle { solid, spiral, leather, pattern }
enum ThemePreference { system, light, dark }

class InkPoint {
  const InkPoint(this.x, this.y, this.pressure);

  final double x;
  final double y;
  final double pressure;

  Map<String, Object> toJson() => {'x': x, 'y': y, 'p': pressure};

  factory InkPoint.fromJson(Map<String, dynamic> value) => InkPoint(
        (value['x'] as num).toDouble(),
        (value['y'] as num).toDouble(),
        (value['p'] as num).toDouble(),
      );
}

InkPoint smoothInkPoint(InkPoint previous, InkPoint raw, double amount) {
  final smoothing = amount.clamp(0.0, 1.0);
  if (smoothing == 0) return raw;

  final dx = raw.x - previous.x;
  final dy = raw.y - previous.y;
  final distance = math.sqrt(dx * dx + dy * dy);
  final baseAlpha = 1.0 - smoothing * .82;
  final speedBoost = (distance * 140).clamp(0.0, 1.0);
  final alpha = baseAlpha + (1.0 - baseAlpha) * speedBoost;
  final pressureAlpha = (.35 + alpha * .65).clamp(0.0, 1.0);

  return InkPoint(
    previous.x + dx * alpha,
    previous.y + dy * alpha,
    previous.pressure + (raw.pressure - previous.pressure) * pressureAlpha,
  );
}

abstract class InkObject {
  String get type;
  bool get isSelected;
  InkObject copyWith({bool? isSelected});
  Map<String, Object> toJson();

  static InkObject fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null || type == 'stroke') return InkStroke.fromJson(json);

    switch (type) {
      case 'text':
        return InkText.fromJson(json);
      default:
        return InkStroke.fromJson(json);
    }
  }
}

class InkText extends InkObject {
  InkText({
    required this.text,
    required this.x,
    required this.y,
    required this.color,
    required this.fontSize,
    this.bold = false,
    this.italic = false,
    this.fontFamily = 'Modern',
    this.textAlign = TextAlign.left,
    this.lineHeight = 1.2,
    this.isSelected = false,
  });

  final String text;
  final double x;
  final double y;
  final Color color;
  final double fontSize;
  final bool bold;
  final bool italic;
  final String fontFamily;
  final TextAlign textAlign;
  final double lineHeight;

  @override
  final bool isSelected;

  @override
  String get type => 'text';

  @override
  InkText copyWith({
    bool? isSelected,
    String? text,
    double? x,
    double? y,
    Color? color,
    double? fontSize,
    bool? bold,
    bool? italic,
    String? fontFamily,
    TextAlign? textAlign,
    double? lineHeight,
  }) {
    return InkText(
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      fontFamily: fontFamily ?? this.fontFamily,
      textAlign: textAlign ?? this.textAlign,
      lineHeight: lineHeight ?? this.lineHeight,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  Map<String, Object> toJson() => {
        'type': type,
        'text': text,
        'x': x,
        'y': y,
        'color': color.toARGB32(),
        'fontSize': fontSize,
        'bold': bold,
        'italic': italic,
        'fontFamily': fontFamily,
        'textAlign': textAlign.name,
        'lineHeight': lineHeight,
      };

  factory InkText.fromJson(Map<String, dynamic> value) => InkText(
        text: value['text'] as String,
        x: (value['x'] as num).toDouble(),
        y: (value['y'] as num).toDouble(),
        color: Color(value['color'] as int),
        fontSize: (value['fontSize'] as num).toDouble(),
        bold: value['bold'] as bool? ?? false,
        italic: value['italic'] as bool? ?? false,
        fontFamily: value['fontFamily'] as String? ?? 'Modern',
        textAlign: TextAlign.values.byName(value['textAlign'] as String? ?? 'left'),
        lineHeight: (value['lineHeight'] as num?)?.toDouble() ?? 1.2,
      );
}

class InkStroke extends InkObject {
  InkStroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    this.dashed = false,
    this.pressureSensitivity = .7,
    this.isSelected = false,
  });

  final InkTool tool;
  final Color color;
  final double width;
  final List<InkPoint> points;
  final bool dashed;
  final double pressureSensitivity;

  @override
  final bool isSelected;

  @override
  String get type => 'stroke';

  @override
  InkStroke copyWith({
    bool? isSelected,
    InkTool? tool,
    Color? color,
    double? width,
    List<InkPoint>? points,
    bool? dashed,
    double? pressureSensitivity,
  }) {
    return InkStroke(
      tool: tool ?? this.tool,
      color: color ?? this.color,
      width: width ?? this.width,
      points: points ?? this.points,
      dashed: dashed ?? this.dashed,
      pressureSensitivity:
          pressureSensitivity ?? this.pressureSensitivity,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  Map<String, Object> toJson() => {
        'type': type,
        'tool': tool.name,
        'color': color.toARGB32(),
        'width': width,
        'dashed': dashed,
        'pressureSensitivity': pressureSensitivity,
        'points': points.map((point) => point.toJson()).toList(),
      };

  factory InkStroke.fromJson(Map<String, dynamic> value) => InkStroke(
        tool: InkTool.values.byName(value['tool'] as String),
        color: Color(value['color'] as int),
        width: (value['width'] as num).toDouble(),
        dashed: value['dashed'] as bool? ?? false,
        pressureSensitivity:
            (value['pressureSensitivity'] as num?)?.toDouble() ?? .7,
        points: (value['points'] as List)
            .map(
              (point) =>
                  InkPoint.fromJson(Map<String, dynamic>.from(point as Map)),
            )
            .toList(),
      );
}

class InkFolder {
  const InkFolder({required this.id, required this.name, this.parentId});

  final String id;
  final String name;
  final String? parentId;

  InkFolder copyWith({String? name, String? parentId, bool clearParent = false}) {
    return InkFolder(
      id: id,
      name: name ?? this.name,
      parentId: clearParent ? null : parentId ?? this.parentId,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
      };

  factory InkFolder.fromJson(Map<String, dynamic> value) => InkFolder(
        id: value['id'] as String,
        name: value['name'] as String,
        parentId: value['parentId'] as String?,
      );
}

class InkDocument {
  InkDocument({
    required this.id,
    required this.title,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
    required this.pages,
    List<String?>? pageBackgrounds,
    List<double?>? pageAspectRatios,
    this.folderId,
    this.isFavorite = false,
    this.iconKey = 'description',
    this.coverStyle = CoverStyle.solid,
    this.backgroundTemplate = BackgroundTemplate.blank,
  })  : pageBackgrounds = pageBackgrounds ??
            List<String?>.filled(pages.length, null, growable: true),
        pageAspectRatios = pageAspectRatios ??
            List<double?>.filled(pages.length, null, growable: true);

  final String id;
  final String title;
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<List<InkObject>> pages;
  final List<String?> pageBackgrounds;
  final List<double?> pageAspectRatios;
  final String? folderId;
  final bool isFavorite;
  final String iconKey;
  final CoverStyle coverStyle;
  final BackgroundTemplate backgroundTemplate;

  InkDocument copyWith({
    String? title,
    int? colorValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<List<InkObject>>? pages,
    List<String?>? pageBackgrounds,
    List<double?>? pageAspectRatios,
    String? folderId,
    bool clearFolder = false,
    bool? isFavorite,
    String? iconKey,
    CoverStyle? coverStyle,
    BackgroundTemplate? backgroundTemplate,
  }) {
    return InkDocument(
      id: id,
      title: title ?? this.title,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pages: pages ?? this.pages,
      pageBackgrounds: pageBackgrounds ?? this.pageBackgrounds,
      pageAspectRatios: pageAspectRatios ?? this.pageAspectRatios,
      folderId: clearFolder ? null : folderId ?? this.folderId,
      isFavorite: isFavorite ?? this.isFavorite,
      iconKey: iconKey ?? this.iconKey,
      coverStyle: coverStyle ?? this.coverStyle,
      backgroundTemplate: backgroundTemplate ?? this.backgroundTemplate,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'color': colorValue,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pages': pages
            .map((page) => page.map((obj) => obj.toJson()).toList())
            .toList(),
        'pageBackgrounds': pageBackgrounds,
        'pageAspectRatios': pageAspectRatios,
        'folderId': folderId,
        'isFavorite': isFavorite,
        'iconKey': iconKey,
        'coverStyle': coverStyle.name,
        'backgroundTemplate': backgroundTemplate.name,
      };

  factory InkDocument.fromJson(Map<String, dynamic> value) {
    List<List<InkObject>> documentPages;
    if (value.containsKey('pages')) {
      documentPages = (value['pages'] as List).map((page) {
        return (page as List).map((obj) {
          return InkObject.fromJson(Map<String, dynamic>.from(obj as Map));
        }).toList();
      }).toList();
    } else if (value.containsKey('strokes')) {
      final oldStrokes = (value['strokes'] as List).map((stroke) {
        return InkObject.fromJson(Map<String, dynamic>.from(stroke as Map));
      }).toList();
      documentPages = [oldStrokes];
    } else {
      documentPages = [[]];
    }

    if (documentPages.isEmpty) documentPages = [[]];
    final updatedAt = DateTime.parse(value['updatedAt'] as String);

    return InkDocument(
      id: value['id'] as String,
      title: value['title'] as String,
      colorValue: value['color'] as int,
      createdAt: value['createdAt'] is String
          ? DateTime.parse(value['createdAt'] as String)
          : updatedAt,
      updatedAt: updatedAt,
      pages: documentPages,
      pageBackgrounds: value['pageBackgrounds'] is List
          ? (value['pageBackgrounds'] as List)
              .map((item) => item as String?)
              .toList()
          : List<String?>.filled(documentPages.length, null, growable: true),
      pageAspectRatios: value['pageAspectRatios'] is List
          ? (value['pageAspectRatios'] as List)
              .map((item) => item == null ? null : (item as num).toDouble())
              .toList()
          : List<double?>.filled(documentPages.length, null, growable: true),
      folderId: value['folderId'] as String?,
      isFavorite: value['isFavorite'] as bool? ?? false,
      iconKey: value['iconKey'] as String? ?? 'description',
      coverStyle: value['coverStyle'] is String
          ? CoverStyle.values.byName(value['coverStyle'] as String)
          : CoverStyle.solid,
      backgroundTemplate: value['backgroundTemplate'] is String
          ? BackgroundTemplate.values
              .byName(value['backgroundTemplate'] as String)
          : BackgroundTemplate.blank,
    );
  }
}

class PenPreset {
  const PenPreset({required this.size, required this.smoothing});

  final double size;
  final double smoothing;

  bool matches(double otherSize, double otherSmoothing) =>
      (size - otherSize).abs() < .01 &&
      (smoothing - otherSmoothing).abs() < .01;

  Map<String, Object> toJson() => {'size': size, 'smoothing': smoothing};

  factory PenPreset.fromJson(Map<String, dynamic> value) => PenPreset(
        size: (value['size'] as num).toDouble(),
        smoothing: (value['smoothing'] as num).toDouble(),
      );
}

class AppSettings {
  const AppSettings({
    this.themePreference = ThemePreference.system,
    this.defaultSmoothing = 0.45,
    this.defaultWidth = 2.0,
    this.sortBy = 'date_modified',
    this.allowFinger = false,
  });

  final ThemePreference themePreference;
  final double defaultSmoothing;
  final double defaultWidth;
  final String sortBy;
  final bool allowFinger;

  AppSettings copyWith({
    ThemePreference? themePreference,
    double? defaultSmoothing,
    double? defaultWidth,
    String? sortBy,
    bool? allowFinger,
  }) {
    return AppSettings(
      themePreference: themePreference ?? this.themePreference,
      defaultSmoothing: defaultSmoothing ?? this.defaultSmoothing,
      defaultWidth: defaultWidth ?? this.defaultWidth,
      sortBy: sortBy ?? this.sortBy,
      allowFinger: allowFinger ?? this.allowFinger,
    );
  }

  Map<String, Object> toJson() => {
        'themePreference': themePreference.name,
        'defaultSmoothing': defaultSmoothing,
        'defaultWidth': defaultWidth,
        'sortBy': sortBy,
        'allowFinger': allowFinger,
      };

  factory AppSettings.fromJson(Map<String, dynamic> value) {
    final savedTheme = value['themePreference'] as String?;
    final legacyDarkMode = value['isDarkMode'] as bool? ?? false;

    return AppSettings(
      themePreference: savedTheme == null
          ? (legacyDarkMode ? ThemePreference.dark : ThemePreference.system)
          : ThemePreference.values.byName(savedTheme),
      defaultSmoothing:
          (value['defaultSmoothing'] as num?)?.toDouble() ?? 0.45,
      defaultWidth: (value['defaultWidth'] as num?)?.toDouble() ?? 2.0,
      sortBy: value['sortBy'] as String? ?? 'date_modified',
      allowFinger: value['allowFinger'] as bool? ?? false,
    );
  }
}
