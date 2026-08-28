import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
// flutter_chat_ui exports its own ChatMessage widget, which collides with
// our domain model of the same name — we only need the Chat widget from
// this package, not its ChatMessage.
import 'package:flutter_chat_ui/flutter_chat_ui.dart' hide ChatMessage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../models/task.dart';
import '../providers/chat_provider.dart';
import '../providers/core_providers.dart';
import '../providers/current_user_providers.dart';
import '../repositories/api_exception.dart';
import '../widgets/task_card.dart';
import '../widgets/task_panel.dart';
import '../theme_notifier.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String roomId;
  final String? roomName;
  const ChatScreen({super.key, required this.roomId, this.roomName});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final InMemoryChatController _chatController = InMemoryChatController();
  String? _displayTitle;

  @override
  void initState() {
    super.initState();
    _displayTitle = widget.roomName;
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  void _onChatEvent(AsyncValue<ChatEvent>? previous, AsyncValue<ChatEvent> next) {
    final event = next.valueOrNull;
    if (event == null) return;
    final myUserId = ref.read(currentUserIdProvider).valueOrNull ?? '';

    switch (event) {
      case ChatHistoryLoaded(:final messages, :final roomName):
        if (roomName != null && mounted) setState(() => _displayTitle = roomName);
        _chatController.messages.clear();
        for (final m in messages) {
          _chatController.insertMessage(_toUiMessage(m, myUserId));
        }
      case ChatMessageReceived(:final message):
        _chatController.insertMessage(_toUiMessage(message, myUserId));
      case ChatReadReceiptReceived():
        for (final m in _chatController.messages) {
          if (m.authorId == myUserId && m.status != MessageStatus.seen) {
            _chatController.updateMessage(m, m.copyWith(status: MessageStatus.seen));
          }
        }
      case ChatTaskUpdated(:final taskId, :final data):
        for (final m in _chatController.messages) {
          final meta = m.metadata;
          if (meta != null && meta['task_id']?.toString() == taskId) {
            final updated = Map<String, dynamic>.from(meta)..addAll(data);
            _chatController.updateMessage(m, m.copyWith(metadata: updated));
            break;
          }
        }
      case ChatTaskDeleted(:final taskId):
        for (final m in _chatController.messages) {
          if (m.metadata?['task_id']?.toString() == taskId) {
            _chatController.removeMessage(m);
            break;
          }
        }
    }
  }

  Message _toUiMessage(ChatMessage m, String myUserId) {
    final isMe = m.authorId == myUserId;
    final status = isMe ? (m.isRead ? MessageStatus.seen : MessageStatus.sent) : null;
    final baseUrl = ref.read(authServiceProvider).currentBaseUrl;

    switch (m.kind) {
      case ChatMessageKind.task:
        return Message.custom(
          id: m.id,
          authorId: m.authorId,
          createdAt: m.createdAt,
          status: status,
          metadata: m.task!.toJson(),
        );
      case ChatMessageKind.image:
        return Message.image(
          id: m.id,
          authorId: m.authorId,
          createdAt: m.createdAt,
          status: status,
          source: '$baseUrl${m.fileUrl}',
        );
      case ChatMessageKind.file:
        return Message.file(
          id: m.id,
          authorId: m.authorId,
          createdAt: m.createdAt,
          status: status,
          name: m.fileName ?? 'file',
          size: m.fileSize ?? 0,
          source: '$baseUrl${m.fileUrl}',
        );
      case ChatMessageKind.text:
        return Message.text(
          id: m.id,
          authorId: m.authorId,
          createdAt: m.createdAt,
          status: status,
          text: m.text ?? '',
        );
    }
  }

  Future<void> _runTaskAction(
    Future<void> Function() action, {
    required String failureMessage,
  }) async {
    try {
      await action();
    } catch (e) {
      debugPrint('task action error: $e');
      _notifyActionFailed(failureMessage);
    }
  }

  void _handleSendPressed(String text) {
    ref.read(chatProvider(widget.roomId).notifier).sendText(text);
  }

  void _handleFileSelection({required bool isImage}) async {
    Uint8List? fileBytes;
    String? fileName;

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
      }
    }

    if (fileBytes != null && fileName != null) {
      await ref
          .read(chatProvider(widget.roomId).notifier)
          .sendAttachment(fileBytes, fileName, isImage: isImage);
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
          try {
            await ref.read(chatProvider(widget.roomId).notifier).createTask(payload);
            if (mounted && Navigator.of(sheetContext).canPop()) {
              Navigator.of(sheetContext).pop();
            }
          } on ApiException catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ошибка создания задачи: ${e.statusCode}')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ошибка создания задачи')),
              );
            }
          }
        },
      ),
    );
  }

  void _openEditTaskPanel(Task task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => TaskPanel(
        initialData: task,
        onSubmit: (dynamic taskData) async {
          if (taskData is! Map) return;
          final payload = Map<String, dynamic>.from(taskData);
          try {
            await ref.read(chatProvider(widget.roomId).notifier).editTask(task, payload);
          } catch (e) {
            debugPrint('edit task error: $e');
            _notifyActionFailed('Не удалось сохранить изменения');
          }
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
    final chatAsync = ref.watch(chatProvider(widget.roomId));
    ref.listen(chatProvider(widget.roomId), _onChatEvent);
    final myUserId = ref.watch(currentUserIdProvider).valueOrNull ?? '';

    if (chatAsync.isLoading && !chatAsync.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (chatAsync.hasError && !chatAsync.hasValue) {
      return const Scaffold(
        body: Center(child: Text('Не удалось загрузить чат')),
      );
    }

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
        onRefresh: () =>
            ref.read(chatProvider(widget.roomId).notifier).refreshHistory(),
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
              currentUserId: myUserId,
              onMessageSend: _handleSendPressed,
              resolveUser: (String id) async {
                final name = await ref.read(userRepositoryProvider).getUserName(id);
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
                      final task = Task.fromJson(message.metadata ?? {});
                      return TaskCard(
                        task: task,
                        currentUserId: myUserId,
                        onAccept: (_) => _runTaskAction(
                          () => ref
                              .read(chatProvider(widget.roomId).notifier)
                              .acceptTask(task),
                          failureMessage: 'Не удалось принять задачу',
                        ),
                        onStatusChange: (taskId, newStatus) => _runTaskAction(
                          () => ref
                              .read(chatProvider(widget.roomId).notifier)
                              .changeTaskStatus(taskId, newStatus),
                          failureMessage: 'Не удалось обновить статус задачи',
                        ),
                        onDelete: (taskId) => _runTaskAction(
                          () => ref
                              .read(chatProvider(widget.roomId).notifier)
                              .deleteTask(taskId),
                          failureMessage: 'Не удалось удалить задачу',
                        ),
                        onSubtasksUpdated: (_, updated) => _runTaskAction(
                          () => ref
                              .read(chatProvider(widget.roomId).notifier)
                              .updateSubtasks(task, updated),
                          failureMessage: 'Не удалось обновить подзадачи',
                        ),
                        onEdit: (_) => _openEditTaskPanel(task),
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
