// lib/controllers/chat_controller.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sos_system/common/model/message_model.dart';

class ChatController {
  final String myEmail;      // e.g., child@example.com or guardian@example.com
  final String otherEmail;   // counterpart's email
  final bool isChildSide;    // true if this device is the Child side; false => Guardian side

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  ChatController({
    required this.myEmail,
    required this.otherEmail,
    required this.isChildSide,
  });

  // Paths (child side or guardian side) for listening/writing for *this* device:
  CollectionReference<Map<String, dynamic>> _myMessagesCollection() {
    if (isChildSide) {
      return _db
          .collection('Child')
          .doc(myEmail)
          .collection('chat')
          .doc(otherEmail)
          .collection('messages');
    } else {
      return _db
          .collection('Guardian')
          .doc(myEmail)
          .collection('chat')
          .doc(otherEmail)
          .collection('messages');
    }
  }

  // Mirror path (other device's path) — where we also write the same message
  CollectionReference<Map<String, dynamic>> _otherMessagesCollection() {
    if (isChildSide) {
      // write also under Guardian/{otherEmail}/chat/{myEmail}/messages
      return _db
          .collection('Guardian')
          .doc(otherEmail)
          .collection('chat')
          .doc(myEmail)
          .collection('messages');
    } else {
      return _db
          .collection('Child')
          .doc(otherEmail)
          .collection('chat')
          .doc(myEmail)
          .collection('messages');
    }
  }

  /// Stream of messages for this chat (ordered by timestamp)
  Stream<List<MessageModel>> streamMessages({int limit = 500}) {
    return _myMessagesCollection()
        .orderBy('timestamp')
        .limitToLast(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MessageModel.fromDoc(d)).toList());
  }

  /// Send message: writes to BOTH sides (batch) so both parties have the same doc id & data.
  Future<void> sendMessage({required String text}) async {
    final msgDoc = _myMessagesCollection().doc(); // new doc to generate id
    final otherDoc = _otherMessagesCollection().doc(msgDoc.id);

    final message = {
      'sender': myEmail,
      'receiver': otherEmail,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    };

    final batch = _db.batch();
    batch.set(msgDoc, message);
    batch.set(otherDoc, message);
    await batch.commit();
  }

  /// Mark all unread messages (where receiver == myEmail) as read on my side only.
  /// Note: you may also want to mirror read state to the other side, but since both sides have separate copies,
  /// we update only this device's path. If you want to mark read on both copies, do so similarly.
  Future<void> markMessagesAsRead() async {
    final q = await _myMessagesCollection()
        .where('receiver', isEqualTo: myEmail)
        .where('read', isEqualTo: false)
        .get();

    final batch = _db.batch();
    for (var doc in q.docs) {
      batch.update(doc.reference, {'read': true});
    }
    if (q.docs.isNotEmpty) await batch.commit();
  }

  /// Optional: update a single message's read state on both sides (if you want mirrored read receipts)
  Future<void> markMessageReadBothSides(String messageId) async {
    final myRef = _myMessagesCollection().doc(messageId);
    final otherRef = _otherMessagesCollection().doc(messageId);
    final batch = _db.batch();
    batch.update(myRef, {'read': true});
    batch.update(otherRef, {'read': true});
    await batch.commit();
  }
}
