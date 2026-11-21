import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kee/core/constants/app_spacing.dart';
import 'package:kee/core/intelligence/conversation_provider.dart';
import 'package:kee/core/intelligence/kee_conversation_engine.dart';
import 'package:kee/core/widgets/kee_logo.dart';
import 'package:kee/features/capture/presentation/voice_capture_dialog.dart';
import 'package:kee/features/memories/data/memory_model.dart';
import 'package:kee/features/reminders/data/reminder_model.dart';
import 'package:kee/features/reminders/data/task_model.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final MessageIntent? intent;
  final MemoryModel? savedMemory;
  final ReminderModel? scheduledReminder;
  final TaskModel? savedTask;
  final List<MemoryModel> citations;
  final List<ReminderModel> citedReminders;
  final List<TaskModel> citedTasks;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.intent,
    this.savedMemory,
    this.scheduledReminder,
    this.savedTask,
    this.citations = const [],
    this.citedReminders = const [],
    this.citedTasks = const [],
  });
}

class AskKeeScreen extends ConsumerStatefulWidget {
  final String? initialQuery;

  const AskKeeScreen({super.key, this.initialQuery});

  @override
  ConsumerState<AskKeeScreen> createState() => _AskKeeScreenState();
}

class _AskKeeScreenState extends ConsumerState<AskKeeScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;

  final List<String> _suggestedPrompts = [
    'What do I have scheduled tomorrow?',
    'Remind me to review notes tomorrow at 10 AM',
    'I prefer working in quiet environments',
    'My mum\'s birthday is February 14',
    'What did I say I wanted to buy?',
    'Which tasks are pending?',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(
        text: 'Meet Kee, your Knowledge Extension Entity. Talk naturally to capture what matters, set reminders, or recall anything you have entrusted to memory.\n\nYour memory. Extended.',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleSendMessage(widget.initialQuery!);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSendMessage(String query) async {
    final text = query.trim();
    if (text.isEmpty || _isProcessing) return;

    _controller.clear();
    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _isProcessing = true;
    });

    _scrollToBottom();

    try {
      final engine = ref.read(conversationEngineProvider);
      final ConversationAction action = await engine.processMessage(text);

      if (!mounted) return;

      setState(() {
        _messages.add(
          ChatMessage(
            text: action.responseText,
            isUser: false,
            timestamp: DateTime.now(),
            intent: action.intent,
            savedMemory: action.savedMemory,
            scheduledReminder: action.scheduledReminder,
            savedTask: action.savedTask,
            citations: action.citedMemories,
            citedReminders: action.citedReminders,
            citedTasks: action.citedTasks,
          ),
        );
        _isProcessing = false;
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            text: "I encountered an issue processing that. Your local memory is intact—please try again.",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
        _isProcessing = false;
      });
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
    final isDark = theme.brightness == Brightness.dark;

    final accentColor = isDark
        ? const Color(0xFFE8D0B2)
        : const Color(0xFFA6855B);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: AppSpacing.sm),
            const KeeLogo(size: 32),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask Kee',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  'Knowledge Extension Entity',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.5,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Clear conversation',
            onPressed: () {
              setState(() {
                _messages.clear();
                _messages.add(
                  ChatMessage(
                    text: 'Conversation cleared. What would you like to remember or ask today?',
                    isUser: false,
                    timestamp: DateTime.now(),
                  ),
                );
              });
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Message List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildMessageBubble(context, msg);
                },
              ),
            ),

            // Loading indicator
            if (_isProcessing)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Kee is thinking...',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

            // Suggested prompt chips
            if (_messages.length <= 3 && !_isProcessing)
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  itemCount: _suggestedPrompts.length,
                  separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    final prompt = _suggestedPrompts[index];
                    return ActionChip(
                      label: Text(
                        prompt,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                      ),
                      onPressed: () => _handleSendMessage(prompt),
                    );
                  },
                ),
              ),

            const SizedBox(height: AppSpacing.xs),

            // Input Bar
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              textCapitalization: TextCapitalization.sentences,
                              minLines: 1,
                              maxLines: 4,
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Talk to Kee or ask a question...',
                                hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onSubmitted: (val) => _handleSendMessage(val),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.mic_none_rounded, size: 22),
                            tooltip: 'Voice Input',
                            color: theme.colorScheme.onSurfaceVariant,
                            onPressed: () async {
                              final text = await VoiceCaptureDialog.show(context);
                              if (text != null && text.isNotEmpty) {
                                _handleSendMessage(text);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_upward_rounded,
                        color: theme.colorScheme.onPrimary,
                        size: 20,
                      ),
                      onPressed: () => _handleSendMessage(_controller.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage msg) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final accentColor = isDark
        ? const Color(0xFFE8D0B2)
        : const Color(0xFFA6855B);

    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF272625)
                      : theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd).copyWith(
                    bottomRight: const Radius.circular(AppSpacing.xxs),
                  ),
                ),
                child: Text(
                  msg.text,
                  style: TextStyle(
                    color: isDark ? const Color(0xFFFBF2E6) : Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Kee response bubble
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            child: const KeeLogo(size: 28),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.6),
                    ),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd).copyWith(
                      topLeft: const Radius.circular(AppSpacing.xxs),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        msg.text,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),

                      // Activity Badge (Saved Memory / Scheduled Reminder)
                      if (msg.savedMemory != null || msg.scheduledReminder != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            if (msg.savedMemory != null)
                              _buildActionBadge(
                                icon: Icons.auto_awesome_rounded,
                                label: 'Memory saved: "${msg.savedMemory!.title}"',
                                color: accentColor,
                              ),
                            if (msg.scheduledReminder != null)
                              _buildActionBadge(
                                icon: Icons.alarm_rounded,
                                label: 'Reminder scheduled: ${DateFormat('MMM d @ h:mm a').format(msg.scheduledReminder!.scheduledAt)}',
                                color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    DateFormat('h:mm a').format(msg.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
