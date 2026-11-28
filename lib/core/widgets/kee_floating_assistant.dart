import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_spacing.dart';
import '../voice/assistant_state.dart';
import '../voice/voice_assistant_controller.dart';
import 'kee_voice_orb.dart';

// Official Kee brand palette — mirrors _KeeBrand in kee_voice_orb.dart
class _KB {
  static const Color obsidian = Color(0xFF080808);
  static const Color warmIvory = Color(0xFFF3F0E8);
  static const Color softGrey = Color(0xFF77736B);
  static const Color lightAccent = Color(0xFFD8D2C5);
  static const Color surface = Color(0xFF111110);
  static const Color border = Color(0xFF242220);
  static const Color errorRose = Color(0xFFD97070);
}

/// Floating AI Assistant Widget for Kee.
/// Appears everywhere across the entire application.
/// When clicked, it does NOT navigate away; instead, it opens the interactive
/// AI bubble overlay right on top of whatever screen the user is viewing.
/// Everything discussed (spoken or typed) is automatically saved to the single unified chat.
class KeeFloatingAssistant extends ConsumerStatefulWidget {
  const KeeFloatingAssistant({super.key});

  @override
  ConsumerState<KeeFloatingAssistant> createState() =>
      _KeeFloatingAssistantState();
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

    final safeCtrl = controller;
    final safeAssistant = assistant;

    // If expanded, show the full-screen Kee-branded panel
    if (safeAssistant.isExpanded) {
      return _buildExpandedOverlay(context, safeAssistant, safeCtrl);
    }

    // ── Compact floating pill ─────────────────────────────────────────────────
    final isActive =
        safeAssistant.isListening ||
        safeAssistant.isProcessing ||
        safeAssistant.isSpeaking;

    return Positioned(
      right: AppSpacing.md,
      bottom: AppSpacing.xl,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: () {
            safeCtrl.setExpanded(true);
            if (safeAssistant.isIdle) safeCtrl.startListening();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              // Always use the dark Kee canvas for the pill — looks premium on
              // both light and dark host screens.
              color: _KB.obsidian,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: isActive ? _KB.warmIvory : _KB.border,
                width: isActive ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
                if (isActive)
                  BoxShadow(
                    color: _KB.warmIvory.withValues(alpha: 0.08),
                    blurRadius: 12,
                    spreadRadius: 1,
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
                    letterSpacing: 0.4,
                    color: isActive ? _KB.warmIvory : _KB.lightAccent,
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

  // ── Expanded full-screen panel ─────────────────────────────────────────────
  Widget _buildExpandedOverlay(
    BuildContext context,
    VoiceAssistantState assistant,
    VoiceAssistantController controller,
  ) {
    return Positioned.fill(
      child: Material(
        // Deep obsidian backdrop — 94 % opacity so the host screen is barely
        // visible, reinforcing the "modal" feel while keeping brand depth.
        color: _KB.obsidian.withValues(alpha: 0.94),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top bar ──────────────────────────────────────────────────
              _buildTopBar(context, controller),

              const Spacer(flex: 1),

              // ── Logo mark centred above orb ───────────────────────────────
              Image.asset(
                'assets/logo/kee_logo_mark_dark.png',
                height: 28,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Animated orb ─────────────────────────────────────────────
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

              const SizedBox(height: AppSpacing.sm),

              // ── State label ───────────────────────────────────────────────
              Text(
                _getStateLabel(assistant.state),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.1,
                  color: _KB.softGrey,
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── Live transcript / response ────────────────────────────────
              _buildTranscriptArea(assistant),

              if (assistant.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                  ),
                  child: Text(
                    assistant.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: _KB.errorRose),
                  ),
                ),

              const Spacer(flex: 2),

              // ── Inline text input (optional) ──────────────────────────────
              if (_showBubbleTextInput) _buildTextInput(controller),

              // ── Bottom control bar ────────────────────────────────────────
              _buildControlBar(assistant, controller),

              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar: minimize | logo wordmark | expand + close ────────────────────
  Widget _buildTopBar(
    BuildContext context,
    VoiceAssistantController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          // Minimize
          IconButton(
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 26,
              color: _KB.softGrey,
            ),
            tooltip: 'Minimize',
            onPressed: () => controller.setExpanded(false),
          ),

          // Centre: Kee wordmark logo
          Expanded(
            child: Center(
              child: Image.asset(
                'assets/logo/kee_logo_cropped_dark.png',
                height: 22,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // Open full page
          IconButton(
            icon: const Icon(
              Icons.open_in_full_rounded,
              size: 18,
              color: _KB.softGrey,
            ),
            tooltip: 'Open full chat',
            onPressed: () {
              controller.setExpanded(false);
              context.push('/ask-kee');
            },
          ),

          // Close / dismiss session
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: _KB.softGrey,
            ),
            tooltip: 'Close session',
            onPressed: () => controller.dismissSession(),
          ),
        ],
      ),
    );
  }

  // ── Transcript / response area ────────────────────────────────────────────
  Widget _buildTranscriptArea(VoiceAssistantState assistant) {
    final hasTranscript = assistant.liveTranscript.isNotEmpty;
    final hasResponse = assistant.lastAssistantResponse.isNotEmpty;

    final text = hasTranscript
        ? '"${assistant.liveTranscript}"'
        : hasResponse
        ? assistant.lastAssistantResponse
        : 'Talk naturally or type a question...';

    final textColor = hasTranscript
        ? _KB.warmIvory
        : hasResponse
        ? _KB.warmIvory.withValues(alpha: 0.85)
        : _KB.softGrey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56, maxHeight: 160),
        child: SingleChildScrollView(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
              fontWeight: hasTranscript ? FontWeight.w500 : FontWeight.w400,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  // ── Inline text input row ─────────────────────────────────────────────────
  Widget _buildTextInput(VoiceAssistantController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _KB.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _KB.border),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextField(
                controller: _bubbleTextController,
                autofocus: true,
                style: const TextStyle(color: _KB.warmIvory, fontSize: 14),
                cursorColor: _KB.lightAccent,
                decoration: const InputDecoration(
                  hintText: 'Type to Kee...',
                  hintStyle: TextStyle(color: _KB.softGrey, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (_) => _sendBubbleText(controller),
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.send_rounded,
                size: 20,
                color: _KB.lightAccent,
              ),
              onPressed: () => _sendBubbleText(controller),
            ),
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: _KB.softGrey,
              ),
              onPressed: () => setState(() => _showBubbleTextInput = false),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom control bar ────────────────────────────────────────────────────
  Widget _buildControlBar(
    VoiceAssistantState assistant,
    VoiceAssistantController controller,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _KB.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: _KB.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Keyboard toggle
          IconButton(
            icon: Icon(
              _showBubbleTextInput
                  ? Icons.keyboard_hide_outlined
                  : Icons.keyboard_alt_outlined,
              color: _KB.softGrey,
            ),
            tooltip: _showBubbleTextInput ? 'Hide keyboard' : 'Type here',
            onPressed: () =>
                setState(() => _showBubbleTextInput = !_showBubbleTextInput),
          ),

          // Central mic / stop button
          _MicButton(assistant: assistant, controller: controller),

          // Interrupt
          TextButton.icon(
            icon: Icon(
              Icons.pan_tool_outlined,
              size: 16,
              color: assistant.isSpeaking
                  ? _KB.lightAccent
                  : _KB.softGrey.withValues(alpha: 0.5),
            ),
            label: Text(
              'Interrupt',
              style: TextStyle(
                fontSize: 12,
                color: assistant.isSpeaking
                    ? _KB.lightAccent
                    : _KB.softGrey.withValues(alpha: 0.5),
              ),
            ),
            onPressed: assistant.isSpeaking
                ? () => controller.interrupt()
                : null,
          ),
        ],
      ),
    );
  }
}

// ── Mic button — extracted for clarity ───────────────────────────────────────
class _MicButton extends StatelessWidget {
  final VoiceAssistantState assistant;
  final VoiceAssistantController controller;

  const _MicButton({required this.assistant, required this.controller});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color bg;
    final Color iconColor;

    if (assistant.isListening) {
      icon = Icons.mic_rounded;
      bg = _KB.warmIvory;
      iconColor = _KB.obsidian;
    } else if (assistant.isSpeaking) {
      icon = Icons.stop_rounded;
      bg = _KB.lightAccent.withValues(alpha: 0.18);
      iconColor = _KB.lightAccent;
    } else if (assistant.hasError) {
      icon = Icons.refresh_rounded;
      bg = _KB.errorRose.withValues(alpha: 0.15);
      iconColor = _KB.errorRose;
    } else {
      icon = Icons.mic_none_rounded;
      bg = _KB.border;
      iconColor = _KB.lightAccent;
    }

    return InkWell(
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
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        child: Icon(icon, color: iconColor, size: 28),
      ),
    );
  }
}
