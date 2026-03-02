import 'package:flutter/material.dart';

class ChatThreadUi {
  final String threadId;
  final String peerUid;
  final String peerName;
  final String lastMessage;
  final DateTime? updatedAt;
  final int unreadCount;

  const ChatThreadUi({
    required this.threadId,
    required this.peerUid,
    required this.peerName,
    required this.lastMessage,
    required this.updatedAt,
    required this.unreadCount,
  });
}


class MessageUi {
  final String id;
  final bool fromMe;
  final String text;
  final String timeText;

  const MessageUi({
    required this.id,
    required this.fromMe,
    required this.text,
    required this.timeText,
  });
}

enum CallDirection { incoming, outgoing, missed }

class CallLogUi {
  final String id;
  final String name;
  final CallDirection direction;
  final String dateText;
  final Color avatarColor;

  const CallLogUi({
    required this.id,
    required this.name,
    required this.direction,
    required this.dateText,
    required this.avatarColor,
  });
}