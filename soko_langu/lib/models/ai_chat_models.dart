// AI chat persistence models — no external dependencies.

class AiConversation {
  final String conversationId;
  final String title;
  final String createdAt;
  final String updatedAt;
  final String status;
  final String lastMessagePreview;
  final int messageCount;

  AiConversation({
    required this.conversationId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.lastMessagePreview,
    required this.messageCount,
  });

  factory AiConversation.fromJson(Map<String, dynamic> json) {
    return AiConversation(
      conversationId: json['conversationId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      lastMessagePreview: json['lastMessagePreview']?.toString() ?? '',
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class AiMessage {
  final String messageId;
  final String conversationId;
  final String role;
  final String content;
  final String createdAt;
  final String status;
  final String? model;
  final String? provider;
  final String? voiceCacheKey;

  AiMessage({
    required this.messageId,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.status,
    this.model,
    this.provider,
    this.voiceCacheKey,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isGenerating => status == 'generating';
  bool get isFailed => status == 'failed';
  bool get isCompleted => status == 'completed';

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    return AiMessage(
      messageId: json['messageId']?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? '',
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      status: json['status']?.toString() ?? 'completed',
      model: json['model']?.toString(),
      provider: json['provider']?.toString(),
      voiceCacheKey: json['voiceCacheKey']?.toString(),
    );
  }

  AiMessage copyWith({String? content, String? status}) {
    return AiMessage(
      messageId: messageId,
      conversationId: conversationId,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      status: status ?? this.status,
      model: model,
      provider: provider,
      voiceCacheKey: voiceCacheKey,
    );
  }
}

class AiPreferences {
  final bool memoryEnabled;
  final bool chatHistoryEnabled;
  final bool voiceEnabled;
  final String? preferredLanguage;
  final String? responseStyle;

  AiPreferences({
    required this.memoryEnabled,
    required this.chatHistoryEnabled,
    required this.voiceEnabled,
    this.preferredLanguage,
    this.responseStyle,
  });

  factory AiPreferences.fromJson(Map<String, dynamic> json) {
    return AiPreferences(
      memoryEnabled: json['memoryEnabled'] != false,
      chatHistoryEnabled: json['chatHistoryEnabled'] != false,
      voiceEnabled: json['voiceEnabled'] != false,
      preferredLanguage: json['preferredLanguage']?.toString(),
      responseStyle: json['responseStyle']?.toString(),
    );
  }
}

class AiMemory {
  final String memoryId;
  final String key;
  final String value;
  final double confidence;
  final String source;
  final String createdAt;
  final String updatedAt;

  AiMemory({
    required this.memoryId,
    required this.key,
    required this.value,
    required this.confidence,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiMemory.fromJson(Map<String, dynamic> json) {
    return AiMemory(
      memoryId: json['memoryId']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      source: json['source']?.toString() ?? 'inferred',
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
    );
  }
}