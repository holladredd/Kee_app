import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/intelligence/conversation_provider.dart';
import '../../../core/intelligence/kee_conversation_engine.dart';
import '../../../core/voice/assistant_state.dart';
import '../../../core/voice/voice_assistant_controller.dart';
import '../../../core/widgets/kee_logo.dart';
import '../../../core/widgets/kee_voice_orb.dart';
import '../../memories/data/memory_model.dart';
import '../../reminders/data/reminder_model.dart';
import '../../reminders/data/task_model.dart';

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
  bool _isProcessingText = false;
  bool _showTextInput = false;

  final List<String> _suggestedPrompts = [
    'What do I have scheduled tomorrow?',
    'Remind me to call John tomorrow at 9 AM',
    'Remember that my mum\'s birthday is February 14',
    'I prefer working in quiet environments',
    'What did I say I wanted to buy?',
    'Which tasks are pending?',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(
        text: 'Meet Kee, your Voice-First Knowledge Extension Entity. Say "Hi Kee" or tap the orb to speak naturally.\n\nYour memory. Extended.',
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
    if (text.isEmpty || _isProcessingText) return;

    _controller.clear();
    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _isProcessingText = true;
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
        _isProcessingText = false;
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
        _isProcessingText = false;
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
    final assistant = ref.watch(voiceAssistantProvider);
    final voiceCtrl = ref.read(voiceAssistantProvider.notifier);

    final accentColor = isDark
        ? const Color(0xFFE8D0B2)
        : const Color(0xFFA6855B);

    // Listen for spoken turn completion to log spoken turns in transcript
    ref.listen(voiceAssistantProvider, (prev, next) {
      if (prev?.state == AssistantState.processing && next.state == AssistantState.speaking) {
        // Log spoken turn into transcript
        if (next.liveTranscript.isNotEmpty) {
          setState(() {
            _messages.add(
              ChatMessage(text: next.liveTranscript, isUser: true, timestamp: DateTime.now()),
            );
            if (next.lastAssistantResponse.isNotEmpty) {
              _messages.add(
                ChatMessage(text: next.lastAssistantResponse, isUser: false, timestamp: DateTime.now()),
              );
            }
          });
          _scrollToBottom();
        }
      }
    });

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
                  assistant.isHandsFreeEnabled ? 'Hands-Free Active ("Hi Kee")' : 'Voice-First AI Assistant',
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
            icon: Icon(
              assistant.isHandsFreeEnabled ? Icons.hearing_rounded : Icons.hearing_disabled_rounded,
              color: assistant.isHandsFreeEnabled ? accentColor : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: assistant.isHandsFreeEnabled ? 'Wake Word Active ("Hi Kee")' : 'Hands-Free Disabled',
            onPressed: () {
              voiceCtrl.toggleHandsFree(!assistant.isHandsFreeEnabled);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Clear conversation',
            onPressed: () {
              setState(() {
                _messages.clear();
                _messages.add(
                  ChatMessage(
                    text: 'Conversation cleared. Say "Hi Kee" or tap the orb to begin.',
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
            // ─── 1. Primary Voice Hero Section ───────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF13110E) : const Color(0xFFFBF8F4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: assistant.isListening
                      ? accentColor
                      : (isDark ? const Color(0xFF262018) : const Color(0xFFEADBCE)),
                  width: assistant.isListening ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: assistant.isListening
                                  ? const Color(0xFF81C784)
                                  : assistant.isSpeaking
                                      ? accentColor
                                      : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _getVoiceStatusText(assistant.state),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                      if (assistant.isSpeaking)
                        InkWell(
                          onTap: () => voiceCtrl.interrupt(),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.pan_tool_outlined, size: 12, color: accentColor),
                                const SizedBox(width: 4),
                                Text(
                                  'Tap to Interrupt',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentColor),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // The Interactive Voice Orb
                  Center(
                    child: KeeVoiceOrb(
                      state: assistant.state,
                      soundLevel: assistant.soundLevel,
                      size: 64,
                      onTap: () {
                        if (assistant.isSpeaking) {
                          voiceCtrl.interrupt();
                        } else if (assistant.isListening) {
                          voiceCtrl.dismissSession();
                        } else {
                          voiceCtrl.startListening();
                        }
                      },
                    ),
                  ),

                  // Real-time spoken transcript banner
                  if (assistant.liveTranscript.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.white60,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '"${assistant.liveTranscript}"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ─── 2. Scrollable Message Transcript ─────────────────
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildMessageBubble(context, msg);
                },
              ),
            ),

            // Loading indicator for typed messages
            if (_isProcessingText)
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
            if (_messages.length <= 3 && !_isProcessingText && !assistant.isListening)
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  itemCount: _suggestedPrompts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
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
                      onPressed: () {
                        voiceCtrl.processSpokenInput(prompt);
                      },
                    );
                  },
                ),
              ),

            const SizedBox(height: AppSpacing.xs),

            // ─── 3. Bottom Controls: Voice Bar & Secondary Text Field ──
            if (_showTextInput)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
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
                                  hintText: 'Type silently to Kee...',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onSubmitted: (val) => _handleSendMessage(val),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              tooltip: 'Hide keyboard',
                              onPressed: () => setState(() => _showTextInput = false),
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
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Text Input Toggle Button
                    IconButton(
                      icon: const Icon(Icons.keyboard_alt_outlined),
                      tooltip: 'Type instead of speaking',
                      color: theme.colorScheme.onSurfaceVariant,
                      onPressed: () => setState(() => _showTextInput = true),
                    ),

                    // Primary Voice Mic Button
                    InkWell(
                      borderRadius: BorderRadius.circular(32),
                      onTap: () {
                        if (assistant.isListening) {
                          voiceCtrl.dismissSession();
                        } else if (assistant.isSpeaking) {
                          voiceCtrl.interrupt();
                        } else {
                          voiceCtrl.startListening();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: assistant.isListening ? accentColor : (isDark ? const Color(0xFF24201A) : const Color(0xFFEDE4D8)),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              assistant.isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                              color: assistant.isListening ? (isDark ? Colors.black : Colors.white) : accentColor,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              assistant.isListening
                                  ? 'Listening...'
                                  : assistant.isSpeaking
                                      ? 'Interrupt'
                                      : 'Tap to Speak',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: assistant.isListening ? (isDark ? Colors.black : Colors.white) : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Hands-Free Wake Word indicator
                    IconButton(
                      icon: Icon(
                        Icons.voice_chat_rounded,
                        color: assistant.isHandsFreeEnabled ? accentColor : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      tooltip: assistant.isHandsFreeEnabled ? 'Hands-Free: Say "Hi Kee"' : 'Tap to toggle hands-free',
                      onPressed: () => voiceCtrl.toggleHandsFree(!assistant.isHandsFreeEnabled),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getVoiceStatusText(AssistantState state) {
    switch (state) {
      case AssistantState.listening:
        return 'Listening... speak naturally';
      case AssistantState.processing:
        return 'Kee is understanding...';
      case AssistantState.speaking:
        return 'Kee is responding...';
      case AssistantState.interrupted:
        return 'Interrupted—listening...';
      case AssistantState.error:
        return 'Voice connection issue';
      case AssistantState.idle:
        return 'Ready. Say "Hi Kee" or tap to speak';
    }
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
