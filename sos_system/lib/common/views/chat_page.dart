// lib/modules/chat/chat_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/common/controllers/chat_controller.dart';
import 'package:sos_system/common/model/message_model.dart';
import 'package:sos_system/common/views/custom_appbar.dart';

class ChatScreen extends StatefulWidget {
  final String name;
  final String relationship;

  /// REQUIRED: the signed-in user's email (Child or Guardian)
  final String myEmail;

  /// REQUIRED: the other participant's email
  final String otherEmail;

  /// REQUIRED: true if this device is Child side, false if Guardian side
  final bool isChildSide;

  const ChatScreen({
    super.key,
    required this.name,
    this.relationship = '',
    required this.myEmail,
    required this.otherEmail,
    required this.isChildSide,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final ChatController _controllerMVC;

  @override
  void initState() {
    super.initState();
    _controllerMVC = ChatController(
      myEmail: widget.myEmail,
      otherEmail: widget.otherEmail,
      isChildSide: widget.isChildSide,
    );

    // When screen opens, mark unread messages as read (so unread toggles)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controllerMVC.markMessagesAsRead();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await _controllerMVC.sendMessage(text: text);
    _controller.clear();

    // Scroll down after a short delay to allow snapshot to arrive
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageBubble(MessageModel m, bool isMe) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final senderBubbleColor = const Color.fromRGBO(0, 123, 255, 1.0);
    final receiverBubbleColor = isDark ? Colors.grey[800] : Colors.grey[200];
    final textColor = isMe ? Colors.white : (isDark ? Colors.white : Colors.black);

    final timestamp = m.timestamp?.toDate();
    final timeString = timestamp != null ? TimeOfDay.fromDateTime(timestamp).format(context) : '';

    final bubble = Container(
      decoration: BoxDecoration(
        color: isMe ? senderBubbleColor : receiverBubbleColor,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(m.text, style: GoogleFonts.poppins(fontSize: 14, color: textColor)),
          const SizedBox(height: 6),
          Text(timeString, style: GoogleFonts.poppins(fontSize: 10, color: Colors.black54)),
        ],
      ),
    );

    final avatar = const CircleAvatar(
      backgroundImage: AssetImage("assets/images/profile.jpg"),
      radius: 20,
    );

    if (isMe) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: bubble),
          const SizedBox(width: 10),
          avatar,
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: 10),
          Flexible(child: bubble),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.grey[100];
    final inputBgColor = isDark ? Colors.grey[850] : Colors.grey[200];
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      appBar: CustomAppBar(title: widget.name),
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // Optional header showing relationship
          if (widget.relationship.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.relationship,
                  style: GoogleFonts.poppins(fontSize: 12, color: subTextColor),
                ),
              ),
            ),

          // Messages
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _controllerMVC.streamMessages(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // keep your original demo messages if you want (but now empty)
                      const SizedBox.shrink(),
                    ],
                  );
                }

                // mark latest unread as read (non-blocking)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _controllerMVC.markMessagesAsRead();
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final isMe = m.sender == widget.myEmail;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: _buildMessageBubble(m, isMe),
                    );
                  },
                );
              },
            ),
          ),

          // Input bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // Text input
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: inputBgColor,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _controller,
                      style: GoogleFonts.poppins(color: textColor),
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        hintStyle: GoogleFonts.poppins(fontSize: 14, color: subTextColor),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Send button
                GestureDetector(
                  onTap: () async {
                    if (_controller.text.trim().isNotEmpty) {
                      await _send();
                    }
                  },
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color.fromRGBO(0, 123, 255, 1.0),
                    child: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
