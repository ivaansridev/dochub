import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'storage_service.dart';

void main() {
  runApp(const DocHubApp());
}

class DocHubApp extends StatefulWidget {
  const DocHubApp({super.key});

  @override
  State<DocHubApp> createState() => _DocHubAppState();
}

class _DocHubAppState extends State<DocHubApp> {
  final SettingsService _settingsService = SettingsService();
  AppSettings _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _updateSettings(AppSettings settings) async {
    setState(() => _settings = settings);
    await _settingsService.save(settings);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DocHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9A7B00)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9A7B00),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _settings.themeMode == 'dark'
          ? ThemeMode.dark
          : _settings.themeMode == 'light'
              ? ThemeMode.light
              : ThemeMode.system,
      home: HomeScreen(settings: _settings, onSettingsChanged: _updateSettings),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  final AppSettings settings;
  final Future<void> Function(AppSettings settings) onSettingsChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final StorageService _storage = StorageService();
  final AudioRecorder _recorder = AudioRecorder();

  bool _recording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  final TextEditingController _searchController = TextEditingController();
  final SearchIndex _searchIndex = SearchIndex();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final messages = await _storage.load();
    if (!mounted) return;
    setState(() {
      _messages.addAll(messages);
      _searchIndex.build(_messages);
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _storage.save(_messages);
    _searchIndex.build(_messages);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() => _messages.add(Message.text(text, isMine: true)));
    await _save();
    _scrollToBottom();
    _focusNode.requestFocus();
  }

  Future<void> _pickFile({required FileType type}) async {
    final result = await FilePicker.pickFiles(type: type);
    if (result == null) return;
    final file = result.files.single;
    setState(() {
      _messages.add(Message(
        isMine: true,
        filePath: file.path,
        fileName: file.name,
      ));
    });
    await _save();
    _scrollToBottom();
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      _recordingTimer?.cancel();
      setState(() => _recording = false);
      if (path != null && path.isNotEmpty) {
        setState(() {
          _messages.add(Message.voice(
            path,
            _recordingDuration,
          ));
        });
        await _save();
        _scrollToBottom();
      }
      setState(() => _recordingDuration = Duration.zero);
      _focusNode.requestFocus();
    } else {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        return;
      }
      final path = await _storage.newAudioPath();
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _recording = true;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordingDuration += const Duration(seconds: 1));
      });
    }
  }

  void _openAttachMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Document'),
              onTap: () {
                Navigator.pop(context);
                _pickFile(type: FileType.any);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickFile(type: FileType.image);
              },
            ),
            const ListTile(
              leading: Icon(Icons.location_on),
              title: Text('Location (Beta)'),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }

  void _openSearch() {
    setState(() {
      _searching = true;
      _searchController.clear();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() => _searching = false);
  }

  void _onSearchChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final searching = _searchController.text.isNotEmpty && _searching;
    final results = _searchIndex.query(_searchController.text, _messages);

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => _onSearchChanged(),
                decoration: const InputDecoration(
                  hintText: 'Search messages...',
                  border: InputBorder.none,
                ),
              )
            : const Text('DocHub'),
        centerTitle: _searching ? false : true,
        actions: [
          _searching
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _closeSearch,
                )
              : IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _openSearch,
                ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: const Color(0xFF9A7B00)),
                child: const Text(
                  'DocHub',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.settings_backup_restore),
                title: Text('Backup/Restore (WIP)'),
                enabled: false,
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(
                        settings: widget.settings,
                        onSettingsChanged: widget.onSettingsChanged,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: searching
                ? (results.isEmpty
                    ? const Center(
                        child: Text(
                          'No results',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          return _MessageBubble(message: results[index]);
                        },
                      ))
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _MessageBubble(message: _messages[index]);
                        },
                      ),
          ),
          _MessageBar(
            controller: _controller,
            focusNode: _focusNode,
            recording: _recording,
            recordingDuration: _recordingDuration,
            onSend: _sendMessage,
            onPickFile: _pickFile,
            onToggleRecording: _toggleRecording,
            onAttach: _openAttachMenu,
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  final AppSettings settings;
  final Future<void> Function(AppSettings settings) onSettingsChanged;

  void _setTheme(String theme) {
    onSettingsChanged(AppSettings(themeMode: theme));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Theme', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto), label: Text('System')),
              ButtonSegment(value: 'light', icon: Icon(Icons.light_mode), label: Text('Light')),
              ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode), label: Text('Dark')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) => _setTheme(selection.first),
          ),
        ],
      ),
    );
  }
}

class SearchIndex {
  final Map<String, Set<int>> _tokens = {};

  void build(List<Message> messages) {
    _tokens.clear();
    for (int i = 0; i < messages.length; i++) {
      final text = messages[i].text ?? '';
      for (final token in tokenize(text)) {
        _tokens.putIfAbsent(token, () => {}).add(i);
      }
    }
  }

  static List<String> tokenize(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  List<Message> query(String q, [List<Message>? source]) {
    final terms = tokenize(q);
    if (terms.isEmpty) return const [];
    final indexed = source ?? const <Message>[];
    final scores = <int, double>{};
    Set<int>? matches;
    for (final term in terms) {
      final scored = _matchTerm(term);
      if (scored.isEmpty) return const [];
      for (final entry in scored.entries) {
        scores[entry.key] = (scores[entry.key] ?? 0) + entry.value;
      }
      matches = (matches == null)
          ? scored.keys.toSet()
          : matches.intersection(scored.keys.toSet());
    }
    if (matches == null) return const [];
    final ordered = matches.toList()
      ..sort((a, b) => (scores[b] ?? 0).compareTo(scores[a] ?? 0));
    return ordered.map((i) => indexed[i]).toList();
  }

  Map<int, double> _matchTerm(String term) {
    final result = <int, double>{};
    for (final entry in _tokens.entries) {
      final token = entry.key;
      final similarity = _similarity(term, token);
      if (similarity > 0) {
        for (final i in entry.value) {
          final existing = result[i];
          result[i] = existing == null || similarity > existing
              ? similarity
              : existing;
        }
      }
    }
    return result;
  }

  double _similarity(String a, String b) {
    if (a == b) return 2.0;
    if (b.startsWith(a)) return 1.5;
    if (b.contains(a) || a.contains(b)) return 1.2;
    final maxDist = a.length < 4 ? 1 : 2;
    if (_levenshtein(a, b) <= maxDist) return 1.0;
    return 0;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = List<int>.generate(b.length + 1, (j) => j);
    for (int i = 1; i <= a.length; i++) {
      int prev = m[0];
      m[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final temp = m[j];
        m[j] = a[i - 1] == b[j - 1]
            ? prev
            : 1 + [m[j], m[j - 1], prev].reduce((x, y) => x < y ? x : y);
        prev = temp;
      }
    }
    return m[b.length];
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = colorScheme.primaryContainer;
    final bg = message.isMine ? colors : colorScheme.surfaceContainerHighest;

    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (message.isVoice) {
      return _VoiceBubble(path: message.filePath!, duration: message.duration!);
    }
    if (message.isFile) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.fileName ?? message.filePath ?? 'File',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return Text(message.text ?? '');
  }
}

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({required this.path, required this.duration});

  final String path;
  final Duration duration;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
    } else {
      await _player.play(DeviceFileSource(widget.path));
      setState(() => _isPlaying = true);
    }
  }

  String get _label {
    final d = widget.duration;
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
          onPressed: _toggle,
        ),
        const SizedBox(width: 4),
        Text(_label),
      ],
    );
  }
}

class _MessageBar extends StatelessWidget {
  const _MessageBar({
    required this.controller,
    required this.focusNode,
    required this.recording,
    required this.recordingDuration,
    required this.onSend,
    required this.onToggleRecording,
    required this.onPickFile,
    required this.onAttach,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool recording;
  final Duration recordingDuration;
  final VoidCallback onSend;
  final VoidCallback onToggleRecording;
  final Future<void> Function({required FileType type}) onPickFile;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: recording
                  ? _RecordingIndicator(duration: recordingDuration)
                  : TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.send,
                      onChanged: (_) {},
                      onSubmitted: (_) => onSend(),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            if (recording)
              IconButton.filled(
                icon: const Icon(Icons.stop),
                onPressed: onToggleRecording,
              )
            else ...[
              IconButton.filled(
                icon: const Icon(Icons.attach_file),
                onPressed: onAttach,
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  final hasText = value.text.trim().isNotEmpty;
                  return IconButton.filled(
                    icon: Icon(hasText ? Icons.send : Icons.mic),
                    onPressed: hasText ? onSend : onToggleRecording,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final label = '$minutes:${seconds.toString().padLeft(2, '0')}';
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(Icons.mic, color: Colors.red),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}