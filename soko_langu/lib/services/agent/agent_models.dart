// Agent data models — mirrors the backend agent action/permission/tool contracts.

enum AgentActionStatus {
  draft,
  validating,
  awaitingApproval,
  approved,
  executing,
  succeeded,
  failed,
  denied,
  cancelled,
  expired,
}

AgentActionStatus agentActionStatusFromJson(String? s) {
  switch (s) {
    case 'VALIDATING': return AgentActionStatus.validating;
    case 'AWAITING_APPROVAL': return AgentActionStatus.awaitingApproval;
    case 'APPROVED': return AgentActionStatus.approved;
    case 'EXECUTING': return AgentActionStatus.executing;
    case 'SUCCEEDED': return AgentActionStatus.succeeded;
    case 'FAILED': return AgentActionStatus.failed;
    case 'DENIED': return AgentActionStatus.denied;
    case 'CANCELLED': return AgentActionStatus.cancelled;
    case 'EXPIRED': return AgentActionStatus.expired;
    case 'DRAFT':
    default: return AgentActionStatus.draft;
  }
}

class AgentPendingAction {
  final String actionId;
  final String userId;
  final String actionType;
  final String? targetResourceId;
  final String? targetResourceType;
  final Map<String, dynamic> parameters;
  final List<String> requiredPermissions;
  final bool requiredMfa;
  final Map<String, dynamic>? versionSnapshot;
  final String idempotencyKey;
  final AgentActionStatus status;
  final String createdAt;
  final String updatedAt;
  final String? expiresAt;
  final String? approvedAt;
  final String? approvedBy;
  final String? executedAt;
  final Map<String, dynamic>? result;
  final String? error;
  final int attempts;

  AgentPendingAction({
    required this.actionId,
    required this.userId,
    required this.actionType,
    this.targetResourceId,
    this.targetResourceType,
    this.parameters = const {},
    this.requiredPermissions = const [],
    this.requiredMfa = false,
    this.versionSnapshot,
    required this.idempotencyKey,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.expiresAt,
    this.approvedAt,
    this.approvedBy,
    this.executedAt,
    this.result,
    this.error,
    this.attempts = 0,
  });

  bool get isTerminal =>
      status == AgentActionStatus.succeeded ||
      status == AgentActionStatus.failed ||
      status == AgentActionStatus.denied ||
      status == AgentActionStatus.expired ||
      status == AgentActionStatus.cancelled;

  bool get awaitingApproval => status == AgentActionStatus.awaitingApproval;
  bool get approved => status == AgentActionStatus.approved;

  factory AgentPendingAction.fromJson(Map<String, dynamic> json) {
    return AgentPendingAction(
      actionId: json['actionId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      actionType: json['actionType']?.toString() ?? '',
      targetResourceId: json['targetResourceId']?.toString(),
      targetResourceType: json['targetResourceType']?.toString(),
      parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
      requiredPermissions: List<String>.from(json['requiredPermissions'] ?? []),
      requiredMfa: json['requiredMfa'] == true,
      versionSnapshot: json['versionSnapshot'] != null
          ? Map<String, dynamic>.from(json['versionSnapshot'])
          : null,
      idempotencyKey: json['idempotencyKey']?.toString() ?? '',
      status: agentActionStatusFromJson(json['status']),
      createdAt: json['createdAt']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? '',
      expiresAt: json['expiresAt']?.toString(),
      approvedAt: json['approvedAt']?.toString(),
      approvedBy: json['approvedBy']?.toString(),
      executedAt: json['executedAt']?.toString(),
      result: json['result'] != null ? Map<String, dynamic>.from(json['result']) : null,
      error: json['error']?.toString(),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

class AgentToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final String impact; // read | prepare | execute | destructive | financial
  final bool requiresApproval;
  final bool requiresMfa;
  final String category;
  final int timeoutMs;

  AgentToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.impact,
    required this.requiresApproval,
    required this.requiresMfa,
    required this.category,
    required this.timeoutMs,
  });

  factory AgentToolDefinition.fromJson(Map<String, dynamic> json) {
    return AgentToolDefinition(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      parameters: Map<String, dynamic>.from(json['parameters'] ?? {}),
      impact: json['impact']?.toString() ?? 'read',
      requiresApproval: json['requiresApproval'] == true,
      requiresMfa: json['requiresMfa'] == true,
      category: json['category']?.toString() ?? '',
      timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 30000,
    );
  }
}

enum AgentPermissionStatus { granted, expired, revoked }

class AgentPermission {
  final String permissionId;
  final String userId;
  final String scope;
  final AgentPermissionStatus status;
  final String? grantedBy;
  final String? reason;
  final String? grantedAt;
  final String? expiresAt;
  final String? revokedAt;
  final String? revokedBy;
  final String? updatedAt;

  AgentPermission({
    required this.permissionId,
    required this.userId,
    required this.scope,
    required this.status,
    this.grantedBy,
    this.reason,
    this.grantedAt,
    this.expiresAt,
    this.revokedAt,
    this.revokedBy,
    this.updatedAt,
  });

  bool get isActive {
    if (status != AgentPermissionStatus.granted) return false;
    if (expiresAt == null) return true;
    final parsed = DateTime.tryParse(expiresAt!);
    // An unparseable expiry is treated as still active; the server is the
    // authority and will reject it if it has actually lapsed.
    return parsed == null || parsed.isAfter(DateTime.now());
  }

  factory AgentPermission.fromJson(Map<String, dynamic> json) {
    return AgentPermission(
      permissionId: json['permissionId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      scope: json['scope']?.toString() ?? '',
      status: _permissionStatusFromJson(json['status']),
      grantedBy: json['grantedBy']?.toString(),
      reason: json['reason']?.toString(),
      grantedAt: json['grantedAt']?.toString(),
      expiresAt: json['expiresAt']?.toString(),
      revokedAt: json['revokedAt']?.toString(),
      revokedBy: json['revokedBy']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
    );
  }
}

AgentPermissionStatus _permissionStatusFromJson(String? s) {
  switch (s) {
    case 'granted': return AgentPermissionStatus.granted;
    case 'revoked': return AgentPermissionStatus.revoked;
    case 'expired':
    default: return AgentPermissionStatus.expired;
  }
}

// A message event received from the agent SSE stream.
class AgentStreamEvent {
  final String event;
  final Map<String, dynamic> data;

  AgentStreamEvent({required this.event, required this.data});

  factory AgentStreamEvent.fromJson(Map<String, dynamic> json) {
    return AgentStreamEvent(
      event: json['event']?.toString() ?? 'message',
      data: Map<String, dynamic>.from(json['data'] ?? {}),
    );
  }
}
