import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group_model.dart';
import '../utils/network_error.dart';
import 'notification_service.dart';

class GroupService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<GroupChat> createGroup({
    required String name,
    required List<String> participantIds,
    String? imageUrl,
    String? description,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw NetworkError(
          message: "User not logged in",
          userMessage: 'Please log in to continue.',
        );
      }

      final allParticipants = [
        currentUser.uid,
        ...participantIds.where((id) => id != currentUser.uid),
      ];

      final docRef = await _db.collection("groups").add({
        'name': name,
        'description': description ?? '',
        'imageUrl': imageUrl ?? '',
        'participantIds': allParticipants,
        'adminIds': [currentUser.uid],
        'createdBy': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount': 0,
      });

      if (allParticipants.length > 1) {
        await _db
            .collection("groups")
            .doc(docRef.id)
            .collection("messages")
            .add({
              'senderId': currentUser.uid,
              'senderName':
                  currentUser.displayName ?? currentUser.email ?? 'Someone',
              'content': 'Group created',
              'timestamp': FieldValue.serverTimestamp(),
              'type': 'system',
              'isSystem': true,
            });
      }

      return GroupChat(
        id: docRef.id,
        name: name,
        imageUrl: imageUrl ?? '',
        participantIds: allParticipants,
        adminIds: [currentUser.uid],
        createdBy: currentUser.uid,
        createdAt: DateTime.now(),
        lastMessage: '',
        lastMessageTime: DateTime.now(),
      );
    } catch (e) {
      throw NetworkError(
        message: "Failed to create group: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }

  Stream<List<GroupChat>> getGroups() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);
    return _db
        .collection("groups")
        .where("participantIds", arrayContains: currentUser.uid)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => GroupChat.fromFirestore(doc))
              .toList();
          list.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
          return list;
        });
  }

  Stream<List<GroupMessage>> getMessages(String groupId, {int limit = 50}) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);
    return _db
        .collection("groups")
        .doc(groupId)
        .collection("messages")
        .orderBy("timestamp", descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupMessage.fromFirestore(doc))
              .toList(),
        );
  }

  Future<List<GroupMessage>> loadOlderMessages(
    String groupId, {
    required DocumentSnapshot? lastDoc,
    int limit = 30,
  }) async {
    var query = _db
        .collection("groups")
        .doc(groupId)
        .collection("messages")
        .orderBy("timestamp", descending: true)
        .limit(limit);
    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }
    final snap = await query.get();
    return snap.docs.map((doc) => GroupMessage.fromFirestore(doc)).toList();
  }

  Future<void> sendMessage({
    required String groupId,
    required String content,
    String type = 'text',
  }) async {
    try {
      final sender = _auth.currentUser;
      if (sender == null) {
        throw NetworkError(
          message: "User not logged in",
          userMessage: 'Please log in to continue.',
        );
      }

      final senderName = sender.displayName ?? sender.email ?? 'Someone';

      await _db.collection("groups").doc(groupId).collection("messages").add({
        'senderId': sender.uid,
        'senderName': senderName,
        'content': content,
        'timestamp': FieldValue.serverTimestamp(),
        'type': type,
        'isSystem': type == 'system',
      });

      await _db.collection("groups").doc(groupId).update({
        'lastMessage': content,
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      final groupDoc = await _db.collection("groups").doc(groupId).get();
      final participantIds =
          List<String>.from(groupDoc.data()?['participantIds'] ?? []);
      final otherMembers =
          participantIds.where((id) => id != sender.uid).toList();
      for (final uid in otherMembers) {
        NotificationService().sendNotification(
          userId: uid,
          title: senderName,
          body: content,
          data: {
            'type': 'group_chat',
            'groupId': groupId,
            'senderId': sender.uid,
            'senderName': senderName,
          },
        );
      }
    } catch (e) {
      throw NetworkError(
        message: "Failed to send message: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }

  Future<void> addMember(String groupId, String userId) async {
    try {
      await _db.collection("groups").doc(groupId).update({
        'participantIds': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      throw NetworkError(
        message: "Failed to add member: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }

  Future<void> addMemberWithMessage(String groupId, String userId, String addedBy) async {
    try {
      await _db.collection("groups").doc(groupId).update({
        'participantIds': FieldValue.arrayUnion([userId]),
      });
      final addedByName = addedBy == 'system' ? 'System' : addedBy;
      await _db.collection("groups").doc(groupId).collection("messages").add({
        'senderId': 'system',
        'senderName': '',
        'content': '$addedByName added a member',
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'system',
        'isSystem': true,
      });
    } catch (e) {
      throw NetworkError(
        message: "Failed to add member: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }

  Future<void> removeMember(String groupId, String userId) async {
    try {
      await _db.collection("groups").doc(groupId).update({
        'participantIds': FieldValue.arrayRemove([userId]),
        'adminIds': FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      throw NetworkError(
        message: "Failed to remove member: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }

  Future<void> leaveGroup(String groupId, String userId) async {
    try {
      await _db.collection("groups").doc(groupId).update({
        'participantIds': FieldValue.arrayRemove([userId]),
        'adminIds': FieldValue.arrayRemove([userId]),
      });
      await _db.collection("groups").doc(groupId).collection("messages").add({
        'senderId': 'system',
        'senderName': '',
        'content': 'A member left the group',
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'system',
        'isSystem': true,
      });
    } catch (e) {
      throw NetworkError(
        message: "Failed to leave group: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }

  Future<void> makeAdmin(String groupId, String userId) async {
    try {
      await _db.collection("groups").doc(groupId).update({
        'adminIds': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      throw NetworkError(
        message: "Failed to make admin: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }

  Future<void> removeAdmin(String groupId, String userId) async {
    try {
      await _db.collection("groups").doc(groupId).update({
        'adminIds': FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      throw NetworkError(
        message: "Failed to remove admin: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }

  Future<void> deleteGroup(String groupId) async {
    try {
      final messagesSnap = await _db
          .collection("groups")
          .doc(groupId)
          .collection("messages")
          .get();
      final batch = _db.batch();
      for (final doc in messagesSnap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      await _db.collection("groups").doc(groupId).delete();
    } catch (e) {
      throw NetworkError(
        message: "Failed to delete group: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }

  Future<String?> sendImageMessage({
    required String groupId,
    required String imageUrl,
  }) async {
    try {
      final sender = _auth.currentUser;
      if (sender == null) {
        throw NetworkError(
          message: "User not logged in",
          userMessage: 'Please log in to continue.',
        );
      }

      final senderName = sender.displayName ?? sender.email ?? 'Someone';

      final msgRef = await _db.collection("groups").doc(groupId).collection("messages").add({
        'senderId': sender.uid,
        'senderName': senderName,
        'content': imageUrl,
        'imageUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'image',
        'isSystem': false,
      });

      await _db.collection("groups").doc(groupId).update({
        'lastMessage': 'Photo',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      final groupDoc = await _db.collection("groups").doc(groupId).get();
      final participantIds = List<String>.from(groupDoc.data()?['participantIds'] ?? []);
      final otherMembers = participantIds.where((id) => id != sender.uid).toList();
      for (final uid in otherMembers) {
        NotificationService().sendNotification(
          userId: uid,
          title: senderName,
          body: 'Sent a photo',
          data: {
            'type': 'group_chat',
            'groupId': groupId,
            'senderId': sender.uid,
            'senderName': senderName,
          },
        );
      }

      return msgRef.id;
    } catch (e) {
      throw NetworkError(
        message: "Failed to send image: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }

  Future<void> updateGroup({
    required String groupId,
    String? name,
    String? imageUrl,
    String? description,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (imageUrl != null) updates['imageUrl'] = imageUrl;
      if (description != null) updates['description'] = description;
      if (updates.isNotEmpty) {
        await _db.collection("groups").doc(groupId).update(updates);
      }
    } catch (e) {
      throw NetworkError(
        message: "Failed to update group: $e",
        userMessage: translateError(e),
        originalError: e,
      );
    }
  }
}
