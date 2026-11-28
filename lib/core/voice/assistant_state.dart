enum AssistantState {
  idle,
  listening,
  processing,
  speaking,
  interrupted,
  error,
}

class VoiceAssistantState {
  final AssistantState state;
  final String liveTranscript;
  final String lastAssistantResponse;
  final double soundLevel; // 0.0 to 1.0
  final String? errorMessage;
  final bool isHandsFreeEnabled;
  final bool isContinuousMode;
  final bool isExpanded;
  final double speechRate;
  final double speechPitch;

  const VoiceAssistantState({
    this.state = AssistantState.idle,
    this.liveTranscript = '',
    this.lastAssistantResponse = '',
    this.soundLevel = 0.0,
    this.errorMessage,
    this.isHandsFreeEnabled = false,
    this.isContinuousMode = false,
    this.isExpanded = false,
    this.speechRate = 0.5,
    this.speechPitch = 1.0,
  });

  bool get isIdle => state == AssistantState.idle;
  bool get isListening => state == AssistantState.listening;
  bool get isProcessing => state == AssistantState.processing;
  bool get isSpeaking => state == AssistantState.speaking;
  bool get isInterrupted => state == AssistantState.interrupted;
  bool get hasError => state == AssistantState.error;

  VoiceAssistantState copyWith({
    AssistantState? state,
    String? liveTranscript,
    String? lastAssistantResponse,
    double? soundLevel,
    String? errorMessage,
    bool? isHandsFreeEnabled,
    bool? isContinuousMode,
    bool? isExpanded,
    double? speechRate,
    double? speechPitch,
  }) {
    return VoiceAssistantState(
      state: state ?? this.state,
      liveTranscript: liveTranscript ?? this.liveTranscript,
      lastAssistantResponse:
          lastAssistantResponse ?? this.lastAssistantResponse,
      soundLevel: soundLevel ?? this.soundLevel,
      errorMessage: errorMessage,
      isHandsFreeEnabled: isHandsFreeEnabled ?? this.isHandsFreeEnabled,
      isContinuousMode: isContinuousMode ?? this.isContinuousMode,
      isExpanded: isExpanded ?? this.isExpanded,
      speechRate: speechRate ?? this.speechRate,
      speechPitch: speechPitch ?? this.speechPitch,
    );
  }
}
