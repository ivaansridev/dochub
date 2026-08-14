import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

class Message {
  Message({
    required this.isMine,
    String? id,
    this.text,
    this.filePath,
    this.fileName,
    this.duration,
    this.isImage = false,
    this.isBinned = false,
    this.isNote = false,
    this.isTodo = false,
    this.todoDone = false,
    DateTime? timestamp,
  })  : id = id ?? _newId(),
        timestamp = timestamp ?? DateTime.now();

  final String id;
  final bool isMine;
  final String? text;
  final String? filePath;
  final String? fileName;
  final Duration? duration;
  final bool isImage;
  final bool isBinned;
  final bool isNote;
  final bool isTodo;
  final bool todoDone;
  final DateTime timestamp;

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';

  bool get isText => text != null;
  bool get isFile =>
      filePath != null && text == null && duration == null && !isImage;
  bool get isVoice => filePath != null && duration != null;

  Message copyWith({
    String? text,
    bool? isBinned,
    bool? isNote,
    bool? isTodo,
    bool? todoDone,
  }) =>
      Message(
        id: id,
        isMine: isMine,
        text: text ?? this.text,
        filePath: filePath,
        fileName: fileName,
        duration: duration,
        isImage: isImage,
        isBinned: isBinned ?? this.isBinned,
        isNote: isNote ?? this.isNote,
        isTodo: isTodo ?? this.isTodo,
        todoDone: todoDone ?? this.todoDone,
        timestamp: timestamp,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'isMine': isMine,
        'text': text,
        'filePath': filePath,
        'fileName': fileName,
        'durationMs': duration?.inMilliseconds,
        'isImage': isImage,
        'isBinned': isBinned,
        'isNote': isNote,
        'isTodo': isTodo,
        'todoDone': todoDone,
        'timestampMs': timestamp.millisecondsSinceEpoch,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        isMine: json['isMine'] as bool? ?? true,
        id: json['id'] as String?,
        text: json['text'] as String?,
        filePath: json['filePath'] as String?,
        fileName: json['fileName'] as String?,
        duration: json['durationMs'] == null
            ? null
            : Duration(milliseconds: json['durationMs'] as int),
        isImage: json['isImage'] as bool? ?? false,
        isBinned: json['isBinned'] as bool? ?? false,
        isNote: json['isNote'] as bool? ?? false,
        isTodo: json['isTodo'] as bool? ?? false,
        todoDone: json['todoDone'] as bool? ?? false,
        timestamp: json['timestampMs'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['timestampMs'] as int),
      );

  factory Message.text(String text, {required bool isMine}) => Message(
        isMine: isMine,
        text: text,
      );

  factory Message.voice(String filePath, Duration duration, {bool isMine = true}) =>
      Message(
        isMine: isMine,
        filePath: filePath,
        duration: duration,
      );

  factory Message.image(String filePath, {bool isMine = true}) => Message(
        isMine: isMine,
        filePath: filePath,
        isImage: true,
      );
}

class StorageService {
  Future<String> get _path async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/messages.json';
  }

  Future<List<Message>> load() async {
    final file = File(await _path);
    if (!await file.exists()) return [];
    try {
      final data = await file.readAsString();
      final list = (jsonDecode(data) as List).cast<Map<String, dynamic>>();
      return list.map(Message.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Message> messages) async {
    final file = File(await _path);
    await file.writeAsString(jsonEncode(messages.map((m) => m.toJson()).toList()));
  }

  Future<String> newAudioPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    return '${dir.path}/$name';
  }

  Future<void> deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

class AppSettings {
  static const String settingsKey = 'settings';

  String themeMode; // 'system' | 'light' | 'dark'

  AppSettings({this.themeMode = 'system'});

  Map<String, dynamic> toJson() => {'themeMode': themeMode};

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      AppSettings(themeMode: json['themeMode'] as String? ?? 'system');
}

class SettingsService {
  Future<String> get _path async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/settings.json';
  }

  Future<AppSettings> load() async {
    final file = File(await _path);
    if (!await file.exists()) return AppSettings();
    try {
      final data = jsonDecode(await file.readAsString());
      return AppSettings.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final file = File(await _path);
    await file.writeAsString(jsonEncode(settings.toJson()));
  }
}