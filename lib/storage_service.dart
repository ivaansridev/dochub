import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Message {
  Message({
    required this.isMine,
    this.text,
    this.filePath,
    this.fileName,
    this.duration,
  });

  final bool isMine;
  final String? text;
  final String? filePath;
  final String? fileName;
  final Duration? duration;

  bool get isText => text != null;
  bool get isFile => filePath != null && text == null;
  bool get isVoice => filePath != null && duration != null;

  Map<String, dynamic> toJson() => {
        'isMine': isMine,
        'text': text,
        'filePath': filePath,
        'fileName': fileName,
        'durationMs': duration?.inMilliseconds,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        isMine: json['isMine'] as bool? ?? true,
        text: json['text'] as String?,
        filePath: json['filePath'] as String?,
        fileName: json['fileName'] as String?,
        duration: json['durationMs'] == null
            ? null
            : Duration(milliseconds: json['durationMs'] as int),
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