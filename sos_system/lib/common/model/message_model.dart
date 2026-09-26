// lib/models/message_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String sender;   // email
  final String receiver; // email
  final String text;
  final Timestamp? timestamp;
  final bool read;

  MessageModel({
    required this.id,
    required this.sender,
    required this.receiver,
    required this.text,
    this.timestamp,
    this.read = false,
  });

  factory MessageModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return MessageModel(
      id: doc.id,
      sender: data['sender'] as String? ?? '',
      receiver: data['receiver'] as String? ?? '',
      text: data['text'] as String? ?? '',
      timestamp: data['timestamp'] as Timestamp?,
      read: data['read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sender': sender,
      'receiver': receiver,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'read': read,
    };
  }
}
