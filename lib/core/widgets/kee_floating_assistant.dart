import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_spacing.dart';
import '../voice/assistant_state.dart';
import '../voice/voice_assistant_controller.dart';
import 'kee_voice_orb.dart';

/// Floating AI Assistant Widget for Kee.
/// Appears everywhere across the entire application.
/// When clicked, it does NOT navigate away; instead, it opens the interactive
/// AI bubble overlay right on top of whatever screen the user is viewing.
/// Everything discussed (spoken or typed) is automatically saved to the single unified chat.
class KeeFloatingAssistant extends ConsumerStatefulWidget {
  const KeeFloatingAssistant({super.key});

  @override
  ConsumerState<KeeFloatingAssistant> createState() => _KeeFloatingAssistantState();
}

class _KeeFloatingAssistantState extends ConsumerState<KeeFloatingAssistant> {
  final TextEditingController _bubbleTextController = TextEditingController();
  bool _showBubbleTextInput = false;

  @override
  void dispose() {
    _bubbleTextController.dispose();
    super.dispose();
  }

  void _sendBubbleText(VoiceAssistantController controller) {
    final text = _bubbleTextController.text.trim();
    if (text.isEmpty) return;
    _bubbleTextController.clear();
    setState(() => _showBubbleTextInput = false);
    controller.processSpokenInput(text);
  }

  @override
  Widget build(BuildContext context) {
    VoiceAssistantState? assistant;
    VoiceAssistantController? controller;

    try {
      assistant = ref.watch(voiceAssistantProvider);
      controller = ref.read(voiceAssistantProvider.notifier);
    } catch (_) {
      // In case voice provider is initializing or unavailable
    }

    if (assistant == null || controller == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFFE8D0B2) : const Color(0xFFA6855B);

    final safeCtrl = controller;
    final safeAssistant = assistant;

    // If expanded, show the in-place AI bubble overlay
    if (safeAssistant.isExpanded) {
      return _buildExpandedOverlay(context, safeAssistant, safeCtrl, theme, accentColor, isDark);
    }

    // Compact floating assistant button (stays pinned on screen)
    return Positioned(
      right: AppSpacing.md,
      bottom: AppSpacing.xl,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: () {
            // Open the AI bubble in-place without navigating away
            safeCtrl.setExpanded(true);
            if (safeAssistant.isIdle) {
              safeCtrl.startListening();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14120E) : const Color(0xFFFBF8F4),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: safeAssistant.isListening
                    ? accentColor
                    : (isDark ? const Color(0xFF2E271F) : const Color(0xFFE2D6C5)),
                width: safeAssistant.isListening ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KeeVoiceOrb(
                  state: safeAssistant.state,
                  soundLevel: safeAssistant.soundLevel,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  _getStateLabel(safeAssistant.state),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: safeAssistant.isListening ? accentColor : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getStateLabel(AssistantState state) {
    switch (state) {
      case AssistantState.listening:
        return 'Listening...';
      case AssistantState.processing:
        return 'Thinking...';
      case AssistantState.speaking:
        return 'Speaking...';
      case AssistantState.interrupted:
        return 'Interrupted';
      case AssistantState.error:
        return 'Voice Notice';
      case AssistantState.idle:
        return 'Ask Kee';
    }
  }

  Widget _buildExpandedOverlay(
    BuildContext context,
    VoiceAssistantState assistant,
    VoiceAssistantController controller,
    ThemeData theme,
    Color accentColor,
    bool isDark,
  ) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar with minimize, full-chat shortcut, and close
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                      tooltip: 'Minimize bubble',
                      onPressed: () => controller.setExpanded(false),
                    ),
                    Text(
                      'Kee AI Assistant',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: accentColor,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.open_in_full_rounded, size: 20),
                          tooltip: 'Open full chat page',
                          onPressed: () {
                            controller.setExpanded(false);
                            context.push('/ask-kee');
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 22),
                          tooltip: 'Close session',
                          onPressed: () => controller.dismissSession(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 1),

              // Animated Voice Orb Hero
              Center(
                child: KeeVoiceOrb(
                  state: assistant.state,
                  soundLevel: assistant.soundLevel,
                  size: 96,
                  onTap: () {
                    if (assistant.isSpeaking) {
                      controller.interrupt();
                    } else if (assistant.isListening) {
                      controller.dismissSession();
                    } else {
                      controller.startListening();
                    }
                  },
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // State label
              Text(
                _getStateLabel(assistant.state),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Live transcript or latest response
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 60, maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Text(
                      assistant.liveTranscript.isNotEmpty
                          ? '"${assistant.liveTranscript}"'
                          : assistant.lastAssistantResponse.isNotEmpty
                              ? assistant.lastAssistantResponse
                              : 'Talk naturally or type a question...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                        color: assistant.liveTranscript.isNotEmpty
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ),
              ),

              if (assistant.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm, left: AppSpacing.lg, right: AppSpacing.lg),
                  child: Text(
                    assistant.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Color(0xFFE57373)),
                  ),
                ),

              const Spacer(flex: 2),

              // Optional in-bubble text input (so user can type right here without leaving!)
              if (_showBubbleTextInput)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF221E19) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextField(
                            controller: _bubbleTextController,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: 'Type to Kee...',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onSubmitted: (_) => _sendBubbleText(controller),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.send_rounded, size: 20, color: accentColor),
                          onPressed: () => _sendBubbleText(controller),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() => _showBubbleTextInput = false),
                        ),
                      ],
                    ),
                  ),
                ),

              // Bottom control bar: Mic button, Interrupt button, Keyboard toggle
              Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF191612) : const Color(0xFFF7F3EE),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2E271F) : const Color(0xFFE2D6C5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Toggle in-bubble keyboard
                    IconButton(
                      icon: Icon(_showBubbleTextInput ? Icons.keyboard_hide_outlined : Icons.keyboard_alt_outlined),
                      tooltip: _showBubbleTextInput ? 'Hide keyboard' : 'Type here',
                      onPressed: () => setState(() => _showBubbleTextInput = !_showBubbleTextInput),
                    ),

                    // Main Mic / Stop Turn Button
                    InkWell(
                      borderRadius: BorderRadius.circular(32),
                      onTap: () {
                        if (assistant.isListening) {
                          controller.dismissSession();
                        } else if (assistant.isSpeaking) {
                          controller.interrupt();
                        } else {
                          controller.clearError();
                          controller.startListening();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: assistant.isListening
                              ? accentColor
                              : assistant.hasError
                                  ? Colors.redAccent.withValues(alpha: 0.2)
                                  : (isDark ? Colors.white12 : Colors.black12),
                        ),
                        child: Icon(
                          assistant.isListening
                              ? Icons.mic_rounded
                              : assistant.isSpeaking
                                  ? Icons.stop_rounded
                                  : assistant.hasError
                                      ? Icons.refresh_rounded
                                      : Icons.mic_none_rounded,
                          color: assistant.isListening
                              ? (isDark ? Colors.black : Colors.white)
                              : assistant.hasError
                                  ? Colors.redAccent
                                  : theme.colorScheme.onSurface,
                          size: 28,
                        ),
                      ),
                    ),

                    // Tap to Interrupt Button
                    TextButton.icon(
                      icon: const Icon(Icons.pan_tool_outlined, size: 18),
                      label: const Text('Interrupt', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                        foregroundColor: assistant.isSpeaking ? accentColor : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      onPressed: assistant.isSpeaking ? () => controller.interrupt() : null,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}
