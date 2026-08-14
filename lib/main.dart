import 'dart:async';
import 'dart:io';
import 'dart:math';

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

enum _MessageFilter { all, plain, notes, todos }

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
  _MessageFilter _filter = _MessageFilter.all;

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

  List<Message> get _visibleMessages =>
      _messages.where((m) => !m.isBinned).toList();

bool _matchesFilter(Message message) => switch (_filter) {
      _MessageFilter.all => true,
      _MessageFilter.plain => !message.isNote && !message.isTodo,
      _MessageFilter.notes => message.isNote,
      _MessageFilter.todos => message.isTodo,
    };

  List<Message> get _filteredVisibleMessages =>
      _visibleMessages.where(_matchesFilter).toList();

  void _openFilterMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _filterTile(
              ctx,
              _MessageFilter.all,
              Icons.all_inbox,
              'All',
            ),
            _filterTile(
              ctx,
              _MessageFilter.plain,
              Icons.chat_outlined,
              'Default',
            ),
            _filterTile(
              ctx,
              _MessageFilter.notes,
              Icons.sticky_note_2_outlined,
              'Notes',
            ),
            _filterTile(
              ctx,
              _MessageFilter.todos,
              Icons.check_circle_outline,
              'Todos',
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterTile(
    BuildContext ctx,
    _MessageFilter value,
    IconData icon,
    String label,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: _filter == value
          ? Icon(
              Icons.check,
              color: Theme.of(ctx).colorScheme.primary,
            )
          : null,
      onTap: () {
        setState(() => _filter = value);
        Navigator.pop(ctx);
      },
    );
  }

  List<Message> get _binnedMessages =>
      _messages.where((m) => m.isBinned).toList();

  void _setBinned(Message message, bool binned) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    setState(() {
      _messages[index] = message.copyWith(isBinned: binned);
    });
    _save();
  }

  void _deleteForever(Message message) {
    setState(() {
      _messages.removeWhere((m) => m.id == message.id);
    });
    _save();
    _storage.deleteFile(message.filePath);
  }

  void _editMessage(Message message) {
    final isAttachment = message.isImage || message.isFile || message.isVoice;
    final ctrl = TextEditingController(text: message.text ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAttachment ? 'Add caption' : 'Edit Message'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: isAttachment ? 'Caption' : 'Message',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) {
                Navigator.pop(ctx);
                return;
              }
              final index = _messages.indexWhere((m) => m.id == message.id);
              if (index >= 0) {
                setState(() {
                  _messages[index] = _messages[index].copyWith(text: text);
                });
                _save();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _convertMessage(Message message, {required bool toNote, required bool toTodo}) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    setState(() {
      _messages[index] = message.copyWith(isNote: toNote, isTodo: toTodo);
    });
    _save();
  }

  void _toggleTodo(Message message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    setState(() {
      _messages[index] = message.copyWith(todoDone: !message.todoDone);
    });
    _save();
  }

  Widget _messageBubble(Message message) {
    return _MessageBubble(
      message: message,
      onBin: (m) => _setBinned(m, true),
      onRestore: (m) => _setBinned(m, false),
      onEdit: _editMessage,
      onConvertToDefault: (m) =>
          _convertMessage(m, toNote: false, toTodo: false),
      onConvertToNote: (m) =>
          _convertMessage(m, toNote: true, toTodo: false),
      onConvertToTodo: (m) =>
          _convertMessage(m, toNote: false, toTodo: true),
      onToggleTodo: _toggleTodo,
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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

  void _openSendTypeMenu() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Send as Note'),
              onTap: () {
                Navigator.pop(ctx);
                _sendTypedMessage(text, isNote: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Send as Todo'),
              onTap: () {
                Navigator.pop(ctx);
                _sendTypedMessage(text, isTodo: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _sendTypedMessage(String text,
      {bool isNote = false, bool isTodo = false}) {
    _controller.clear();
    setState(() {
      _messages.add(Message(
        isMine: true,
        text: text,
        isNote: isNote,
        isTodo: isTodo,
      ));
    });
    _save();
    _scrollToBottom();
    _focusNode.requestFocus();
  }

  Future<void> _pickFile({required FileType type}) async {
    final result = await FilePicker.platform.pickFiles(type: type);
    if (result == null) return;
    final file = result.files.single;
    setState(() {
      _messages.add(type == FileType.image
          ? Message.image(file.path ?? '')
          : Message(
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
    final results = _searchIndex
        .query(_searchController.text, _visibleMessages)
        .where(_matchesFilter)
        .toList();

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
          IconButton(
            icon: _filter == _MessageFilter.all
                ? const Icon(Icons.filter_alt_outlined)
                : const Icon(Icons.filter_alt),
            onPressed: _openFilterMenu,
          ),
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
                leading: const Icon(Icons.delete_outline),
                title: const Text('Bin'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => BinScreen(
                        messages: _binnedMessages,
                        onRestore: (m) => _setBinned(m, false),
                        onDeleteForever: _deleteForever,
                      ),
                    ),
                  );
                },
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
                          return _messageBubble(results[index]);
                        },
                      ))
                : _filteredVisibleMessages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _filteredVisibleMessages.length,
                        itemBuilder: (context, index) {
                          final list = _filteredVisibleMessages;
                          final message = list[index];
                          final prev = index > 0 ? list[index - 1] : null;
                          final showPill =
                              prev == null || !_sameDay(message.timestamp, prev.timestamp);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showPill)
                                _DatePill(date: message.timestamp),
                              _messageBubble(message),
                            ],
                          );
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
            onSwipeUpSend: _openSendTypeMenu,
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

class _DatePill extends StatelessWidget {
  const _DatePill({required this.date});

  final DateTime date;

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '${date.day} ${_months[date.month - 1]} ${date.year}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onBin,
    required this.onRestore,
    required this.onEdit,
    required this.onConvertToDefault,
    required this.onConvertToNote,
    required this.onConvertToTodo,
    required this.onToggleTodo,
  });

  final Message message;
  final void Function(Message message) onBin;
  final void Function(Message message) onRestore;
  final void Function(Message message) onEdit;
  final void Function(Message message) onConvertToDefault;
  final void Function(Message message) onConvertToNote;
  final void Function(Message message) onConvertToTodo;
  final void Function(Message message) onToggleTodo;

  void _showTurnIntoMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Default'),
              onTap: () {
                Navigator.pop(ctx);
                onConvertToDefault(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Note'),
              enabled: !_isAttachment,
              onTap: _isAttachment
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      onConvertToNote(message);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Todo'),
              onTap: () {
                Navigator.pop(ctx);
                onConvertToTodo(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool get _isAttachment =>
      message.isImage || message.isFile || message.isVoice;

  String _formatTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isImage)
              ListTile(
                leading: const Icon(Icons.open_in_full),
                title: const Text('View fullscreen'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => _ImageViewer(path: message.filePath!),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Turn into'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                _showTurnIntoMenu(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                onEdit(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                onBin(message);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Message moved to bin'),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () => onRestore(message),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = message.isMine
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;

    final timeStyle = TextStyle(
      fontSize: 10,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
    );
    final isShortText = (message.text?.length ?? 0) < 30 && !_isAttachment;

    final bubble = GestureDetector(
      onTap: () => _showMenu(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: message.isImage
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: isShortText
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: _content(context)),
                  const SizedBox(width: 6),
                  Text(_formatTime(message.timestamp), style: timeStyle),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: message.isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  _content(context),
                  const SizedBox(height: 2),
                  Text(_formatTime(message.timestamp), style: timeStyle),
                ],
              ),
      ),
    );

    return Dismissible(
      key: ValueKey(message.id),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.4,
        DismissDirection.endToStart: 0.4,
      },
      background: _SwipeActionBackground(
        icon: Icons.delete_outline,
        color: Colors.red,
        onRight: false,
      ),
      secondaryBackground: _SwipeActionBackground(
        icon: Icons.edit_outlined,
        color: Theme.of(context).colorScheme.primary,
        onRight: true,
      ),
      confirmDismiss: (direction) {
        if (direction == DismissDirection.endToStart) {
          onEdit(message);
          return Future.value(false);
        }
        return Future.value(true);
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.startToEnd) {
          onBin(message);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Message moved to bin'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => onRestore(message),
              ),
            ),
          );
        }
      },
      child: Align(
        alignment:
            message.isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (message.isTodo) {
      return _TodoContent(message: message, onToggleTodo: onToggleTodo);
    }
    if (message.isVoice) {
      return _VoiceBubble(
        path: message.filePath!,
        duration: message.duration!,
      );
    }
    if (message.isImage) {
      return _ImageBubble(path: message.filePath!);
    }
    if (message.isNote) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sticky_note_2_outlined, size: 18),
          const SizedBox(width: 8),
          Flexible(child: _NoteText(text: message.text ?? 'Note')),
        ],
      );
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
    return _ExpandableText(text: message.text ?? '');
  }
}

class _TodoContent extends StatelessWidget {
  const _TodoContent({required this.message, required this.onToggleTodo});

  final Message message;
  final void Function(Message message) onToggleTodo;

  @override
  Widget build(BuildContext context) {
    final done = message.todoDone;
    final textStyle = done
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;

    final checkbox = _TodoCheck(
      done: done,
      onToggle: () => onToggleTodo(message),
    );

    if (message.isVoice) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          checkbox,
          const SizedBox(width: 4),
          _VoiceBubble(path: message.filePath!, duration: message.duration!),
        ],
      );
    }
    if (message.isImage) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((message.text ?? '').isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                checkbox,
                const SizedBox(width: 4),
                Flexible(child: Text(message.text!, style: textStyle)),
              ],
            )
          else
            checkbox,
          const SizedBox(height: 4),
          _ImageBubble(path: message.filePath!),
        ],
      );
    }
    if (message.isFile) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          checkbox,
          const SizedBox(width: 4),
          const Icon(Icons.insert_drive_file),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.fileName ?? message.filePath ?? 'File',
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        checkbox,
        const SizedBox(width: 4),
        Flexible(child: Text(message.text ?? 'Todo', style: textStyle)),
      ],
    );
  }
}

class _TodoCheck extends StatefulWidget {
  const _TodoCheck({required this.done, required this.onToggle});

  final bool done;
  final VoidCallback onToggle;

  @override
  State<_TodoCheck> createState() => _TodoCheckState();
}

class _TodoCheckState extends State<_TodoCheck> {
  final GlobalKey _key = GlobalKey();

  void _handleTap() {
    Offset? origin;
    final renderObject = _key.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      origin = renderObject.localToGlobal(Offset.zero) +
          Offset(renderObject.size.width / 2, renderObject.size.height / 2);
    }
    widget.onToggle();
    if (!widget.done && origin != null) {
      showConfetti(context, origin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _key,
      icon: Icon(
        widget.done ? Icons.check_box : Icons.check_box_outline_blank,
        size: 20,
        color: widget.done ? Theme.of(context).colorScheme.primary : null,
      ),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 24,
        minHeight: 24,
      ),
      onPressed: _handleTap,
    );
  }
}

class _SwipeActionBackground extends StatelessWidget {
  const _SwipeActionBackground({
    required this.icon,
    required this.color,
    required this.onRight,
  });

  final IconData icon;
  final Color color;
  final bool onRight;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.horizontal(
          left: onRight ? Radius.zero : const Radius.circular(16),
          right: onRight ? const Radius.circular(16) : Radius.zero,
        ),
      ),
      alignment: onRight ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 3,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final exceeds = painter.didExceedMaxLines;

        if (!exceeds && !_expanded) {
          return Text(widget.text);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (exceeds)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Show less' : 'Show more',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NoteText extends StatefulWidget {
  const _NoteText({required this.text});

  final String text;

  @override
  State<_NoteText> createState() => _NoteTextState();
}

class _NoteTextState extends State<_NoteText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseStyle = DefaultTextStyle.of(context).style;
        final text = widget.text;

        String? heading;
        String body = text;
        if (text.isNotEmpty) {
          final p2 = TextPainter(
            text: TextSpan(text: text, style: baseStyle),
            maxLines: 2,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: constraints.maxWidth);
          if (p2.didExceedMaxLines) {
            final boundary =
                p2.getLineBoundary(const TextPosition(offset: 0));
            heading = text.substring(0, boundary.end);
            body = text
                .substring(boundary.end)
                .replaceFirst(RegExp(r'^\n+'), '');
          }
        }

        final p3 = TextPainter(
          text: TextSpan(text: text, style: baseStyle),
          maxLines: 3,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final extendsBeyond3 = heading != null && p3.didExceedMaxLines;

        if (heading == null) {
          return Text(text);
        }

        final toggle = extendsBeyond3
            ? GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Show less' : 'Show more',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: baseStyle.copyWith(
                fontSize: (baseStyle.fontSize ?? 14) + 3,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (extendsBeyond3 || _expanded) toggle,
          ],
        );
      },
    );
  }
}

class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(path),
        width: 240,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 240,
          height: 200,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image, size: 48),
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          minScale: 0.5,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
            ),
          ),
        ),
      ),
    );
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
    required this.onSwipeUpSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool recording;
  final Duration recordingDuration;
  final VoidCallback onSend;
  final VoidCallback onToggleRecording;
  final Future<void> Function({required FileType type}) onPickFile;
  final VoidCallback onAttach;
  final VoidCallback onSwipeUpSend;

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
                  return GestureDetector(
                    onVerticalDragEnd: (details) {
                      final v = details.primaryVelocity;
                      if (hasText && v != null && v < 0) {
                        onSwipeUpSend();
                      }
                    },
                    child: IconButton.filled(
                      icon: Icon(hasText ? Icons.send : Icons.mic),
                      onPressed: hasText ? onSend : onToggleRecording,
                    ),
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

void showConfetti(BuildContext context, Offset origin) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ConfettiBurst(
      origin: origin,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst({required this.origin, required this.onDone});

  final Offset origin;
  final VoidCallback onDone;

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final List<_ConfettiPiece> _pieces =
      List.generate(60, (_) => _ConfettiPiece.random());

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDone();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final fade =
              (t < 0.55 ? 1.0 : (1.0 - (t - 0.55) / 0.45)).clamp(0.0, 1.0);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final piece in _pieces)
                Positioned(
                  left: widget.origin.dx + piece.dx(t) - piece.width / 2,
                  top: widget.origin.dy + piece.dy(t) - piece.height / 2,
                  child: Opacity(
                    opacity: fade,
                    child: Transform.rotate(
                      angle: piece.rotation(t),
                      child: Container(
                        width: piece.width,
                        height: piece.height,
                        decoration: BoxDecoration(
                          color: piece.color,
                          shape: piece.isCircle
                              ? BoxShape.circle
                              : BoxShape.rectangle,
                          borderRadius: piece.isCircle
                              ? null
                              : BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ConfettiPiece {
  const _ConfettiPiece({
    required this.color,
    required this.isCircle,
    required this.width,
    required this.height,
    required this.vx,
    required this.vy,
    required this.gravity,
    required this.swayAmp,
    required this.swayFreq,
    required this.phase,
    required this.startAngle,
    required this.spin,
  });

  final Color color;
  final bool isCircle;
  final double width;
  final double height;
  final double vx;
  final double vy;
  final double gravity;
  final double swayAmp;
  final double swayFreq;
  final double phase;
  final double startAngle;
  final double spin;

  static const List<Color> _colors = [
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
  ];

  factory _ConfettiPiece.random() {
    final rng = Random();
    final angle = (rng.nextDouble() - 0.5) * 2.2;
    final speed = 240 + rng.nextDouble() * 340;
    final isCircle = rng.nextBool();
    final d = 3 + rng.nextDouble() * 3;
    return _ConfettiPiece(
      color: _colors[rng.nextInt(_colors.length)],
      isCircle: isCircle,
      width: isCircle ? d : 5 + rng.nextDouble() * 5,
      height: isCircle ? d : 2 + rng.nextDouble() * 3,
      vx: sin(angle) * speed * (rng.nextBool() ? 1 : -1),
      vy: -cos(angle) * speed,
      gravity: 700 + rng.nextDouble() * 700,
      swayAmp: 4 + rng.nextDouble() * 16,
      swayFreq: 6 + rng.nextDouble() * 10,
      phase: rng.nextDouble() * pi * 2,
      startAngle: rng.nextDouble() * pi * 2,
      spin: (rng.nextDouble() * 10 - 5) * pi,
    );
  }

  double dx(double t) => vx * t + swayAmp * sin(swayFreq * t + phase);
  double dy(double t) => vy * t + gravity * t * t;
  double rotation(double t) => startAngle + spin * t;
}

class BinScreen extends StatefulWidget {
  const BinScreen({
    super.key,
    required this.messages,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final List<Message> messages;
  final void Function(Message message) onRestore;
  final void Function(Message message) onDeleteForever;

  @override
  State<BinScreen> createState() => _BinScreenState();
}

class _BinScreenState extends State<BinScreen> {
  late final List<Message> _items = [...widget.messages];

  void _restore(Message message) {
    setState(() => _items.removeWhere((m) => m.id == message.id));
    widget.onRestore(message);
  }

  void _delete(Message message) {
    setState(() => _items.removeWhere((m) => m.id == message.id));
    widget.onDeleteForever(message);
  }

  String _preview(Message message) {
    if (message.isVoice) return 'Voice message';
    if (message.isImage) return 'Image';
    if (message.isFile) return message.fileName ?? 'File';
    if (message.isTodo) return message.text ?? 'Todo';
    if (message.isNote) return message.text ?? 'Note';
    return message.text ?? '';
  }

  IconData _icon(Message message) {
    if (message.isVoice) return Icons.mic;
    if (message.isImage) return Icons.image;
    if (message.isNote) return Icons.sticky_note_2_outlined;
    if (message.isTodo) return Icons.check_circle_outline;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bin')),
      body: _items.isEmpty
          ? const Center(
              child: Text(
                'Bin is empty',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final message = _items[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Icon(_icon(message)),
                    title: Text(
                      _preview(message),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.restore),
                          tooltip: 'Restore',
                          onPressed: () => _restore(message),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_forever,
                              color: Colors.red),
                          tooltip: 'Delete forever',
                          onPressed: () => _delete(message),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}