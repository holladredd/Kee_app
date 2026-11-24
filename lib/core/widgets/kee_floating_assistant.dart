import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_spacing.dart';
import '../voice/assistant_state.dart';
import '../voice/voice_assistant_controller.dart';
import 'kee_voice_orb.dart';

/// Floating assistant interface for Kee.
/// Operates in two modes:
/// 1. Compact floating button (orb + status pill)
/// 2. Expandable bottom sheet / modal voice conversation overlay with live transcription,
///    interruption control, and seamless switch to text.
class KeeFloatingAssistant extends ConsumerWidget {
  const KeeFloatingAssistant({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assistant = ref.watch(voiceAssistantProvider);
    final controller = ref.read(voiceAssistantProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final accentColor = isDark ? const Color(0xFFE8D0B2) : const Color(0xFFA6855B);

    // If expanded, show the full voice conversation sheet
    if (assistant.isExpanded) {
      return _buildExpandedOverlay(context, ref, assistant, controller, theme, accentColor);
    }

    // Compact floating assistant orb
    return Positioned(
      right: AppSpacing.md,
      bottom: AppSpacing.xxl + 40,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: () {
            controller.setExpanded(true);
            if (assistant.isIdle) {
              controller.startListening();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14120E) : const Color(0xFFFBF8F4),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: assistant.isListening
                    ? accentColor
                    : (isDark ? const Color(0xFF2E271F) : const Color(0xFFE2D6C5)),
                width: assistant.isListening ? 1.5 : 1.0,
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
                  state: assistant.state,
                  soundLevel: assistant.soundLevel,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  _getStateLabel(assistant.state),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: assistant.isListening ? accentColor : theme.colorScheme.onSurface,
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
        return 'Voice Error';
      case AssistantState.idle:
        return 'Ask Kee';
    }
  }

  Widget _buildExpandedOverlay(
    BuildContext context,
    WidgetRef ref,
    VoiceAssistantState assistant,
    VoiceAssistantController controller,
    ThemeData theme,
    Color accentColor,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.65),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar with close / minimize controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                      tooltip: 'Minimize to floating orb',
                      onPressed: () => controller.setExpanded(false),
                    ),
                    Text(
                      'Kee Voice Assistant',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: accentColor,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 24),
                      tooltip: 'End conversation',
                      onPressed: () => controller.dismissSession(),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 1),

              // Animated Kee Voice Orb Hero
              Center(
                child: KeeVoiceOrb(
                  state: assistant.state,
                  soundLevel: assistant.soundLevel,
                  size: 90,
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

              // Spoken query / Live transcript display
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
                              : 'Say "Hi Kee" or tap the orb to talk...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                        color: assistant.liveTranscript.isNotEmpty
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
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

              // Bottom control bar: Mic button, Interrupt button, Switch to Text button
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
                    // Switch to Ask Kee text view
                    IconButton(
                      icon: const Icon(Icons.keyboard_outlined),
                      tooltip: 'Type instead',
                      onPressed: () {
                        controller.dismissSession();
                        context.go('/ask-kee');
                      },
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
                          controller.startListening();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: assistant.isListening ? accentColor : (isDark ? Colors.white12 : Colors.black12),
                        ),
                        child: Icon(
                          assistant.isListening
                              ? Icons.mic_rounded
                              : assistant.isSpeaking
                                  ? Icons.stop_rounded
                                  : Icons.mic_none_rounded,
                          color: assistant.isListening
                              ? (isDark ? Colors.black : Colors.white)
                              : theme.colorScheme.onSurface,
                          size: 28,
                        ),
                      ),
                    ),

                    // Tap to Interrupt Button (active especially when speaking)
                    TextButton.icon(
                      icon: const Icon(Icons.pan_tool_outlined, size: 18),
                      label: const Text('Interrupt', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                        foregroundColor: assistant.isSpeaking ? accentColor : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      onPressed: assistant.isSpeaking
                          ? () => controller.interrupt()
                          : null,
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
