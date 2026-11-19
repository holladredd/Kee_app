import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_spacing.dart';
import '../../intelligence/local_ai_runner.dart';
import '../../intelligence/ai_abstraction.dart';
import '../../memories/data/memory_model.dart';
import '../../memories/data/memory_repository.dart';
import '../../reminders/data/reminder_repository.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<MemoryModel> citations;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.citations = const [],
  });
}

class AskKeeScreen extends ConsumerStatefulWidget {
  const AskKeeScreen({super.key});

  @override
  ConsumerState<AskKeeScreen> createState() => _AskKeeScreenState();
}

class _AskKeeScreenState extends ConsumerState<AskKeeScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;

  final List<String> _suggestedPrompts = [
    'What am I supposed to do tomorrow?',
    'What promises have I made?',
    'What did I say I wanted to buy?',
    'Which tasks have I not completed?',
    'What ideas have I captured?',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(
        text: 'Hello! Ask me anything you have saved in Kee. I recall tasks, promises, ideas, preferences, and memories offline.',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleAsk(String query) async {
    final text = query.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _isProcessing = true;
    });

    _scrollToBottom();

    try {
      // 1. Fetch all local records from SQLite
      final memoryRepo = ref.read(memoryRepositoryProvider);
      final reminderRepo = ref.read(reminderRepositoryProvider);

      final memories = await memoryRepo.getAllMemories();
      final tasks = await reminderRepo.getTasks();
      final reminders = await reminderRepo.getReminders();

      // 2. Query Recall Engine (retrieval-first local synthesis)
      final aiEngine = ref.read(aiEngineProvider);
      final RecallAnswer answer = await aiEngine.answerFromMemories(
        question: text,
        memories: memories,
        tasks: tasks,
        reminders: reminders,
      );

      setState(() {
        _messages.add(
          ChatMessage(
            text: answer.text,
            isUser: false,
            timestamp: DateTime.now(),
            citations: answer.citedMemories,
          ),
        );
      });
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            text: 'Sorry, I encountered an error while searching your records: $e',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    } finally {
      setState(() => _isProcessing = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final engine = ref.watch(aiEngineProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ask Kee'),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${engine.name} • 100% Offline',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Chat message list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageBubble(context, msg);
              },
            ),
          ),

          if (_isProcessing)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Searching local memories...',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          // Suggested prompt chips
          if (_messages.length <= 2)
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: _suggestedPrompts.length,
                itemBuilder: (context, index) {
                  final prompt = _suggestedPrompts[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ActionChip(
                      label: Text(prompt, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _handleAsk(prompt),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: AppSpacing.xs),

          // Input field
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outline)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _handleAsk,
                      decoration: const InputDecoration(
                        hintText: 'Ask Kee about your memories or tasks...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send_rounded, color: theme.colorScheme.primary),
                    onPressed: () => _handleAsk(_controller.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage msg) {
    final theme = Theme.of(context);
    final isUser = msg.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isUser
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppSpacing.radiusMd),
                topRight: const Radius.circular(AppSpacing.radiusMd),
                bottomLeft: Radius.circular(isUser ? AppSpacing.radiusMd : 2),
                bottomRight: Radius.circular(isUser ? 2 : AppSpacing.radiusMd),
              ),
            ),
            child: Text(
              msg.text,
              style: TextStyle(
                fontSize: 14.5,
                color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),

          // Citations list
          if (msg.citations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: msg.citations.map((c) {
                return ActionChip(
                  avatar: const Icon(Icons.bookmark_outline_rounded, size: 14),
                  label: Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () => context.go('/memories/detail/${c.id}'),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
