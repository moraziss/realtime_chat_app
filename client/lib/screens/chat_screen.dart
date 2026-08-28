import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:uuid/uuid.dart';
import '../services/auth_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/websocket_service.dart';
import '../models/task.dart';
import '../widgets/task_card.dart';
import '../widgets/task_panel.dart';
import '../theme_notifier.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;
  final String? roomName;
  const ChatScreen({super.key, required this.roomId, this.roomName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _authService = AuthService();
  late final InMemoryChatController _chatController = InMemoryChatController();
  final _uuid = const Uuid();

  String? _currentUserId;
  bool _isLoading = true;
  String? _displayTitle;

  final Set<String> _seenMessageIds = {};
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _displayTitle = widget.roomName;
    _initializeChat();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    _currentUserId = await _authService.getUserId();
    if (_displayTitle == null) {
      _loadRoomInfo();
    }
    await WebSocketService().connect();
    await _loadHistory();
    _connectWebSocket();
    setState(() => _isLoading = false);
  }

  Future<void> _loadRoomInfo() async {
    try {
      final res = await _authService.get('/rooms');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rooms = data['data'] as List? ?? [];
        final room = rooms.firstWhere(
          (r) =>
              r['id']?.toString() == widget.roomId ||
              r['room_id']?.toString() == widget.roomId,
          orElse: () => null,
        );
        if (room != null && mounted) {
          setState(() => _displayTitle = room['name']);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final res = await _authService.get('/conversations/${widget.roomId}');
    if (res.statusCode == 200) {
      final conversations = jsonDecode(res.body)['data'] as List? ?? [];

      _chatController.messages.clear();
      _seenMessageIds.clear();
      for (final conv in conversations) {
        final authorId = conv['user_id'].toString();
        _seenMessageIds.add(conv['id'].toString());
        final isMe = authorId == _currentUserId;
        final createdAt = DateTime.parse(conv['created_at']).toUtc();

        Map<String, dynamic>? meta;
        if (conv['metadata'] != null) {
          try {
            meta = conv['metadata'] is String
                ? jsonDecode(conv['metadata']) as Map<String, dynamic>
                : Map<String, dynamic>.from(conv['metadata'] as Map);
          } catch (_) {}
        }

        final bool isRead = meta != null && meta['is_read'] == true;
        final status = isMe
            ? (isRead ? MessageStatus.seen : MessageStatus.sent)
            : null;

        if (meta != null && meta['task_id'] != null) {
          _chatController.insertMessage(
            Message.custom(
              id: conv['id'].toString(),
              authorId: authorId,
              createdAt: createdAt,
              status: status,
              metadata: Map<String, dynamic>.from(meta),
            ),
          );
        } else if (meta != null && meta['is_image'] == true) {
          _chatController.insertMessage(
            Message.image(
              id: conv['id'].toString(),
              authorId: authorId,
              createdAt: createdAt,
              status: status,
              source: '${_authService.currentBaseUrl}${meta['url']}',
            ),
          );
        } else if (meta != null && meta['is_file'] == true) {
          _chatController.insertMessage(
            Message.file(
              id: conv['id'].toString(),
              authorId: authorId,
              createdAt: createdAt,
              status: status,
              name: meta['name'] ?? 'file',
              size: (meta['size'] as num?)?.toInt() ?? 0,
              source: '${_authService.currentBaseUrl}${meta['url']}',
            ),
          );
        } else {
          _chatController.insertMessage(
            Message.text(
              id: conv['id'].toString(),
              authorId: authorId,
              createdAt: createdAt,
              status: status,
              text: conv['text'] ?? conv['data'] ?? '',
            ),
          );
        }
      }
    }
  }

  void _sendReadReceipt() {
    WebSocketService().send(<String, dynamic>{
      'type': 'read',
      'room': widget.roomId,
      'sender': _currentUserId,
    });
  }

  void _connectWebSocket() {
    WebSocketService().send(<String, dynamic>{
      'type': 'join',
      'room': widget.roomId,
      'sender': _currentUserId,
    });

    _sendReadReceipt();

    _wsSubscription?.cancel();
    _wsSubscription = WebSocketService().stream.listen((msg) {
      if (!mounted) return;

      if (msg['type'] == 'read' &&
          msg['room']?.toString() == widget.roomId.toString()) {
        if (msg['sender']?.toString() != _currentUserId) {
          setState(() {
            final messages = _chatController.messages;
            for (final m in messages) {
              if (m.authorId == _currentUserId &&
                  m.status != MessageStatus.seen) {
                _chatController.updateMessage(
                  m,
                  m.copyWith(status: MessageStatus.seen),
                );
              }
            }
          });
        }
        return;
      }

      if ((msg['type'] == 'message' || msg['type'] == 'task_created') &&
          msg['room']?.toString() == widget.roomId.toString()) {
        final senderId = msg['sender']?.toString();
        if (senderId != _currentUserId) {
          _sendReadReceipt();
        } else {
          if (msg['type'] == 'message') return;
        }

        final msgId = msg['id']?.toString() ?? _uuid.v4();
        if (_seenMessageIds.contains(msgId)) return;
        _seenMessageIds.add(msgId);

        Map<String, dynamic>? metadata;
        if (msg['metadata'] != null) {
          try {
            metadata = msg['metadata'] is String
                ? jsonDecode(msg['metadata']) as Map<String, dynamic>
                : Map<String, dynamic>.from(msg['metadata'] as Map);
          } catch (_) {}
        }

        final bool isTask =
            (metadata != null && metadata.containsKey('task_id')) ||
            msg['type'] == 'task_created';

        if (isTask) {
          _chatController.insertMessage(
            Message.custom(
              id: msgId,
              authorId: senderId ?? '',
              createdAt: DateTime.now().toUtc(),
              metadata:
                  metadata ??
                  (msg['data'] is Map
                      ? Map<String, dynamic>.from(msg['data'])
                      : {}),
            ),
          );
        } else if (metadata != null && metadata['is_image'] == true) {
          _chatController.insertMessage(
            Message.image(
              id: msgId,
              authorId: senderId ?? '',
              createdAt: DateTime.now().toUtc(),
              source: '${_authService.currentBaseUrl}${metadata['url']}',
            ),
          );
        } else if (metadata != null && metadata['is_file'] == true) {
          _chatController.insertMessage(
            Message.file(
              id: msgId,
              authorId: senderId ?? '',
              createdAt: DateTime.now().toUtc(),
              name: metadata['name'] ?? 'file',
              size: (metadata['size'] as num?)?.toInt() ?? 0,
              source: '${_authService.currentBaseUrl}${metadata['url']}',
            ),
          );
        } else {
          _chatController.insertMessage(
            Message.text(
              id: msgId,
              authorId: senderId ?? '',
              createdAt: DateTime.now().toUtc(),
              text: msg['data'] ?? msg['text'] ?? '',
            ),
          );
        }
      }

      if (msg['type'] == 'task_update' &&
          msg['room']?.toString() == widget.roomId.toString()) {
        try {
          final data = msg['data'] is String
              ? jsonDecode(msg['data']) as Map<String, dynamic>
              : Map<String, dynamic>.from(msg['data'] as Map);
          final taskId = data['task_id'];
          final messages = _chatController.messages;
          for (final message in messages) {
            final meta = message.metadata;
            if (meta != null && meta['task_id'] == taskId) {
              final updatedMeta = Map<String, dynamic>.from(meta);
              updatedMeta.addAll(data);
              _chatController.updateMessage(
                message,
                message.copyWith(metadata: updatedMeta),
              );
              break;
            }
          }
        } catch (e) {
          debugPrint('task_update error: $e');
        }
      }

      if (msg['type'] == 'task_deleted' &&
          msg['room']?.toString() == widget.roomId.toString()) {
        try {
          final taskId = msg['task_id']?.toString();
          if (taskId == null) return;
          final messages = _chatController.messages;
          for (final message in messages) {
            if (message.metadata != null &&
                message.metadata!['task_id']?.toString() == taskId) {
              _chatController.removeMessage(message);
              break;
            }
          }
        } catch (e) {
          debugPrint('task_deleted error: $e');
        }
      }
    });
  }

  void _handleSendPressed(String text) {
    if (text.trim().isEmpty) return;
    final localMsgId = _uuid.v4();
    _seenMessageIds.add(localMsgId);

    _chatController.insertMessage(
      Message.text(
        id: localMsgId,
        authorId: _currentUserId!,
        createdAt: DateTime.now().toUtc(),
        status: MessageStatus.sent,
        text: text,
      ),
    );

    WebSocketService().send(<String, dynamic>{
      'type': 'message',
      'room': widget.roomId,
      'sender': _currentUserId,
      'data': text,
    });
  }

  void _handleFileSelection({required bool isImage}) async {
    Uint8List? fileBytes;
    String? fileName;
    int? fileSize;

    if (isImage) {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (image != null) {
        fileBytes = await image.readAsBytes();
        fileName = image.name;
        fileSize = fileBytes.length;
      }
    } else {
      // withData: true — иначе на web байты вообще не приходят (там нет
      // настоящего файлового пути, который можно было бы прочитать потом).
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        fileBytes = result.files.single.bytes;
        fileName = result.files.single.name;
        fileSize = result.files.single.size;
      }
    }

    if (fileBytes != null && fileName != null) {
      final url = await _authService.uploadFile(fileBytes, fileName);
      if (url != null) {
        final metadata = {
          'is_image': isImage,
          'is_file': !isImage,
          'url': url,
          'name': fileName,
          'size': fileSize,
        };
        final localMsgId = _uuid.v4();
        _seenMessageIds.add(localMsgId);

        if (isImage) {
          _chatController.insertMessage(
            Message.image(
              id: localMsgId,
              authorId: _currentUserId!,
              createdAt: DateTime.now().toUtc(),
              status: MessageStatus.sent,
              source: '${_authService.currentBaseUrl}$url',
            ),
          );
        } else {
          _chatController.insertMessage(
            Message.file(
              id: localMsgId,
              authorId: _currentUserId!,
              createdAt: DateTime.now().toUtc(),
              status: MessageStatus.sent,
              name: fileName,
              size: fileSize ?? 0,
              source: '${_authService.currentBaseUrl}$url',
            ),
          );
        }

        WebSocketService().send({
          'type': 'message',
          'room': widget.roomId,
          'sender': _currentUserId,
          'metadata': metadata,
        });
      }
    }
  }

  /// Показывает snackbar о неудавшемся действии с задачей — раньше такие
  /// ошибки уходили только в debugPrint, и пользователь не понимал, почему
  /// нажатие как будто ничего не сделало.
  void _notifyActionFailed(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openTaskPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => TaskPanel(
        onSubmit: (dynamic data) async {
          if (data is! Map) return;
          final payload = Map<String, dynamic>.from(data);
          payload['status'] = 'todo';
          payload['accepted_by'] = [];

          final response = await _authService.post(
            '/rooms/${widget.roomId}/tasks',
            payload,
          );
          if (response.statusCode == 200 || response.statusCode == 201) {
            if (mounted && Navigator.of(sheetContext).canPop()) {
              Navigator.of(sheetContext).pop();
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Ошибка создания задачи: ${response.statusCode}',
                  ),
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _openEditTaskPanel(Message message) {
    final meta = Map<String, dynamic>.from(message.metadata ?? {});
    final taskId = meta['task_id'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => TaskPanel(
        initialData: meta,
        onSubmit: (dynamic taskData) async {
          if (taskData is! Map) return;
          final payload = Map<String, dynamic>.from(taskData);
          final updatedMeta = Map<String, dynamic>.from(meta)..addAll(payload);
          _chatController.updateMessage(
            message,
            message.copyWith(metadata: updatedMeta),
          );
          try {
            await _authService.patch('/tasks/$taskId', updatedMeta);
          } catch (e) {
            debugPrint('edit task error: $e');
            _notifyActionFailed('Не удалось сохранить изменения');
          }
          WebSocketService().send(<String, dynamic>{
            'type': 'task_update',
            'room': widget.roomId,
            'sender': _currentUserId,
            'data': jsonEncode(<String, dynamic>{
              'task_id': taskId,
              ...payload,
            }),
          });
          if (mounted && Navigator.of(sheetContext).canPop()) {
            Navigator.of(sheetContext).pop();
          }
        },
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const CircularProgressIndicator(color: Colors.white);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachOption(
    BuildContext context,
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  void _openAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  'Прикрепить файл',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              _buildAttachOption(
                sheetContext,
                Icons.image_rounded,
                'Фото или видео',
                Colors.blue,
                () {
                  Navigator.pop(sheetContext);
                  _handleFileSelection(isImage: true);
                },
              ),
              _buildAttachOption(
                sheetContext,
                Icons.insert_drive_file_rounded,
                'Документ',
                Colors.orange,
                () {
                  Navigator.pop(sheetContext);
                  _handleFileSelection(isImage: false);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final headerForeground = isDark ? colorScheme.onSurface : Colors.white;
    final String titleInitial =
        (_displayTitle != null && _displayTitle!.isNotEmpty)
        ? _displayTitle!.substring(0, 1).toUpperCase()
        : '?';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: headerForeground,
        iconTheme: IconThemeData(color: headerForeground),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [colorScheme.surface, colorScheme.surface]
                  : [colorScheme.primary, colorScheme.primaryContainer],
            ),
          ),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: headerForeground.withOpacity(0.2),
              child: Text(
                titleInitial,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: headerForeground,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _displayTitle ?? 'Чат',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: headerForeground,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.attach_file_rounded),
            onPressed: _openAttachSheet,
          ),
          IconButton(
            icon: const Icon(Icons.add_task_rounded),
            onPressed: _openTaskPanel,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: ValueListenableBuilder<double>(
          valueListenable: appFontSizeNotifier,
          builder: (context, fontSizeFactor, child) {
            const double baseFontSize = 17.0;

            // Строим тему чата из текущей ColorScheme приложения, чтобы пузыри
            // сообщений подхватывали акцентный цвет, выбранный в настройках,
            // а не были жёстко закреплены на чёрном/белом.
            final baseChatTheme = ChatTheme.fromThemeData(theme);
            final chatTheme = baseChatTheme.copyWith(
              shape: const BorderRadius.all(Radius.circular(18)),
              typography: baseChatTheme.typography.copyWith(
                bodyMedium: baseChatTheme.typography.bodyMedium.copyWith(
                  fontSize: baseFontSize * fontSizeFactor,
                ),
              ),
            );

            return Chat(
              chatController: _chatController,
              currentUserId: _currentUserId!,
              onMessageSend: _handleSendPressed,
              resolveUser: (String id) async {
                final name = await _authService.getUserName(id);
                return User(id: id, name: name);
              },
              theme: chatTheme,
              builders: Builders(
                imageMessageBuilder:
                    (
                      context,
                      message,
                      index, {
                      required isSentByMe,
                      groupStatus,
                    }) {
                      return GestureDetector(
                        onTap: () =>
                            _showFullScreenImage(context, message.source),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(
                            maxWidth: 300,
                            maxHeight: 400,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              message.source,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.broken_image, size: 50),
                            ),
                          ),
                        ),
                      );
                    },
                fileMessageBuilder:
                    (
                      context,
                      message,
                      index, {
                      required isSentByMe,
                      groupStatus,
                    }) {
                      return Container(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: ListTile(
                          leading: Icon(
                            Icons.insert_drive_file,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          title: Text(
                            message.name,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 16 * fontSizeFactor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${((message.size ?? 0) / 1024).toStringAsFixed(1)} KB',
                            style: TextStyle(fontSize: 13 * fontSizeFactor),
                          ),
                          onTap: () async {
                            final uri = Uri.parse(message.source);
                            if (await canLaunchUrl(uri)) await launchUrl(uri);
                          },
                        ),
                      );
                    },
                customMessageBuilder:
                    (
                      context,
                      message,
                      index, {
                      required isSentByMe,
                      groupStatus,
                    }) {
                      return TaskCard(
                        // TODO(chat-provider): временная адаптация к типизированному
                        // TaskCard, пока ChatScreen целиком не переведён на
                        // chat_provider (следующий коммит) — сама эта логика ниже
                        // ещё работает поверх сырых Map/message.metadata.
                        task: Task.fromJson(message.metadata ?? {}),
                        currentUserId: _currentUserId!,
                        onAccept: (taskId) async {
                          final meta = Map<String, dynamic>.from(
                            message.metadata ?? {},
                          );
                          List<String> acceptedBy = [];
                          final rawAccepted = meta['accepted_by'];
                          if (rawAccepted is String) {
                            try {
                              final decoded = jsonDecode(rawAccepted);
                              if (decoded is List)
                                acceptedBy = decoded
                                    .map<String>((e) => e.toString())
                                    .toList();
                            } catch (_) {}
                          } else if (rawAccepted is List) {
                            acceptedBy = rawAccepted
                                .map<String>((e) => e.toString())
                                .toList();
                          }
                          if (acceptedBy.contains(_currentUserId)) return;
                          acceptedBy.add(_currentUserId!);
                          String newStatus = meta['status'] ?? 'todo';
                          if (acceptedBy.length >= 2) newStatus = 'in_progress';
                          final updatedMeta = Map<String, dynamic>.from(meta);
                          updatedMeta['accepted_by'] = acceptedBy;
                          updatedMeta['status'] = newStatus;
                          _chatController.updateMessage(
                            message,
                            message.copyWith(metadata: updatedMeta),
                          );
                          try {
                            await _authService.patch('/tasks/$taskId', {
                              'status': newStatus,
                              'accepted_by': acceptedBy,
                            });
                          } catch (e) {
                            debugPrint('onAccept error: $e');
                            _notifyActionFailed('Не удалось принять задачу');
                          }
                          WebSocketService().send(<String, dynamic>{
                            'type': 'task_update',
                            'room': widget.roomId,
                            'sender': _currentUserId,
                            'data': jsonEncode({
                              'task_id': taskId,
                              'status': newStatus,
                              'accepted_by': acceptedBy,
                            }),
                          });
                        },
                        onStatusChange: (taskId, newStatus) async {
                          final updatedMeta = Map<String, dynamic>.from(
                            message.metadata ?? {},
                          );
                          updatedMeta['status'] = newStatus;
                          _chatController.updateMessage(
                            message,
                            message.copyWith(metadata: updatedMeta),
                          );
                          try {
                            await _authService.patch('/tasks/$taskId', {
                              'status': newStatus,
                            });
                          } catch (e) {
                            debugPrint('onStatusChange error: $e');
                            _notifyActionFailed(
                              'Не удалось обновить статус задачи',
                            );
                          }
                          WebSocketService().send(<String, dynamic>{
                            'type': 'task_update',
                            'room': widget.roomId,
                            'sender': _currentUserId,
                            'data': jsonEncode({
                              'task_id': taskId,
                              'status': newStatus,
                            }),
                          });
                        },
                        onDelete: (taskId) async {
                          try {
                            await _authService.delete('/tasks/$taskId');
                            _chatController.removeMessage(message);
                            WebSocketService().send(<String, dynamic>{
                              'type': 'task_deleted',
                              'task_id': taskId,
                              'room': widget.roomId,
                            });
                          } catch (e) {
                            debugPrint('onDelete error: $e');
                            _notifyActionFailed('Не удалось удалить задачу');
                          }
                        },
                        onSubtasksUpdated: (taskId, updatedSubtasks) async {
                          final subtaskMaps = updatedSubtasks
                              .map((s) => s.toJson())
                              .toList();
                          final updatedMeta = Map<String, dynamic>.from(
                            message.metadata ?? {},
                          );
                          updatedMeta['subtasks'] = subtaskMaps;
                          _chatController.updateMessage(
                            message,
                            message.copyWith(metadata: updatedMeta),
                          );
                          try {
                            await _authService.patch(
                              '/tasks/$taskId',
                              updatedMeta,
                            );
                          } catch (e) {
                            debugPrint('onSubtasksUpdated error: $e');
                            _notifyActionFailed(
                              'Не удалось обновить подзадачи',
                            );
                          }
                          WebSocketService().send(<String, dynamic>{
                            'type': 'task_update',
                            'room': widget.roomId,
                            'sender': _currentUserId,
                            'data': jsonEncode({
                              'task_id': taskId,
                              'subtasks': subtaskMaps,
                            }),
                          });
                        },
                        onEdit: (taskId) => _openEditTaskPanel(message),
                      );
                    },
              ),
            );
          },
        ),
      ),
    );
  }
}
