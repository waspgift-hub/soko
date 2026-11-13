import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/agent/agent_models.dart';

void main() {
  group('agentActionStatusFromJson', () {
    test('maps every backend status', () {
      expect(agentActionStatusFromJson('DRAFT'), AgentActionStatus.draft);
      expect(agentActionStatusFromJson('VALIDATING'), AgentActionStatus.validating);
      expect(agentActionStatusFromJson('AWAITING_APPROVAL'), AgentActionStatus.awaitingApproval);
      expect(agentActionStatusFromJson('APPROVED'), AgentActionStatus.approved);
      expect(agentActionStatusFromJson('EXECUTING'), AgentActionStatus.executing);
      expect(agentActionStatusFromJson('SUCCEEDED'), AgentActionStatus.succeeded);
      expect(agentActionStatusFromJson('FAILED'), AgentActionStatus.failed);
      expect(agentActionStatusFromJson('DENIED'), AgentActionStatus.denied);
      expect(agentActionStatusFromJson('CANCELLED'), AgentActionStatus.cancelled);
      expect(agentActionStatusFromJson('EXPIRED'), AgentActionStatus.expired);
    });

    test('falls back to draft for null or unknown values', () {
      expect(agentActionStatusFromJson(null), AgentActionStatus.draft);
      expect(agentActionStatusFromJson('WHATEVER'), AgentActionStatus.draft);
    });
  });

  group('AgentPendingAction', () {
    Map<String, dynamic> json({String status = 'AWAITING_APPROVAL'}) => {
          'actionId': 'act-1',
          'userId': 'u1',
          'actionType': 'submit_withdrawal',
          'targetResourceId': 'wallet-1',
          'targetResourceType': 'wallet',
          'parameters': {'amount': 5000},
          'requiredPermissions': ['execute_withdrawal'],
          'requiredMfa': true,
          'idempotencyKey': 'idem-1',
          'status': status,
          'createdAt': '2026-10-24T10:00:00.000Z',
          'updatedAt': '2026-10-24T10:00:00.000Z',
          'expiresAt': '2026-10-24T11:00:00.000Z',
          'attempts': 2,
        };

    test('parses a full payload', () {
      final action = AgentPendingAction.fromJson(json());
      expect(action.actionId, 'act-1');
      expect(action.actionType, 'submit_withdrawal');
      expect(action.status, AgentActionStatus.awaitingApproval);
      expect(action.requiredMfa, true);
      expect(action.parameters['amount'], 5000);
      expect(action.requiredPermissions, ['execute_withdrawal']);
      expect(action.attempts, 2);
    });

    test('defaults missing optional fields safely', () {
      final action = AgentPendingAction.fromJson({
        'actionId': 'a',
        'userId': 'u',
        'actionType': 'x',
        'idempotencyKey': 'i',
        'status': 'DRAFT',
        'createdAt': '',
        'updatedAt': '',
      });
      expect(action.parameters, isEmpty);
      expect(action.requiredPermissions, isEmpty);
      expect(action.requiredMfa, false);
      expect(action.result, isNull);
      expect(action.attempts, 0);
    });

    test('exposes lifecycle convenience flags', () {
      expect(AgentPendingAction.fromJson(json()).awaitingApproval, true);
      expect(AgentPendingAction.fromJson(json(status: 'APPROVED')).approved, true);
      expect(AgentPendingAction.fromJson(json(status: 'SUCCEEDED')).isTerminal, true);
      expect(AgentPendingAction.fromJson(json(status: 'DENIED')).isTerminal, true);
      expect(AgentPendingAction.fromJson(json(status: 'AWAITING_APPROVAL')).isTerminal, false);
    });
  });

  group('AgentToolDefinition', () {
    test('parses tool metadata', () {
      final tool = AgentToolDefinition.fromJson({
        'name': 'delete_product',
        'description': 'Delete a listing',
        'parameters': {'type': 'object'},
        'impact': 'destructive',
        'requiresApproval': true,
        'requiresMfa': true,
        'category': 'product',
        'timeoutMs': 30000,
      });
      expect(tool.name, 'delete_product');
      expect(tool.impact, 'destructive');
      expect(tool.requiresApproval, true);
      expect(tool.requiresMfa, true);
      expect(tool.timeoutMs, 30000);
    });

    test('defaults impact to read and timeout to 30s', () {
      final tool = AgentToolDefinition.fromJson({'name': 'search_products'});
      expect(tool.impact, 'read');
      expect(tool.timeoutMs, 30000);
      expect(tool.requiresApproval, false);
    });
  });

  group('AgentPermission', () {
    AgentPermission perm(String status, {String? expiresAt}) =>
        AgentPermission.fromJson({
          'permissionId': 'p1',
          'userId': 'u1',
          'scope': 'read_my_wallet',
          'status': status,
          'expiresAt': expiresAt,
        });

    test('is active when granted and not yet expired', () {
      final future = DateTime.now().add(const Duration(hours: 1)).toIso8601String();
      expect(perm('granted', expiresAt: future).isActive, true);
    });

    test('is inactive when granted but expired', () {
      final past = DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();
      expect(perm('granted', expiresAt: past).isActive, false);
    });

    test('is inactive when revoked, regardless of expiry', () {
      final future = DateTime.now().add(const Duration(hours: 1)).toIso8601String();
      expect(perm('revoked', expiresAt: future).isActive, false);
    });

    test('is active when granted without an expiry', () {
      expect(perm('granted').isActive, true);
    });

    test('tolerates an unparseable expiry when granted', () {
      expect(perm('granted', expiresAt: 'not-a-date').isActive, true);
    });
  });

  group('AgentStreamEvent', () {
    test('parses an SSE event envelope', () {
      final event = AgentStreamEvent.fromJson({
        'event': 'delta',
        'data': {'text': 'Hello'},
      });
      expect(event.event, 'delta');
      expect(event.data['text'], 'Hello');
    });

    test('defaults missing fields', () {
      final event = AgentStreamEvent.fromJson({});
      expect(event.event, 'message');
      expect(event.data, isEmpty);
    });
  });
}
