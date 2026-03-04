import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:fyp_flutter/core/utils/app_snack.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/theme/theme.dart';

class ChatDetailScreen extends StatefulWidget {
  final String peerUid;

  const ChatDetailScreen({super.key, required this.peerUid});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ctrl = TextEditingController();
  bool _marked = false;
  bool _typing = false;
  final _scrollCtrl = ScrollController();
  int _lastMsgCount = 0;
  final _recorder = AudioRecorder();
  bool _recording = false;
  String? _recordPath;
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();

    ctrl.addListener(() {
      final nowTyping = ctrl.text.trim().isNotEmpty;
      if (nowTyping != _typing) {
        setState(() => _typing = nowTyping);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _markReadIfNeeded());
  }

  @override
  void dispose() {
    if (_recording) {
      _recorder.stop();
    }
    _recorder.dispose();
    _scrollCtrl.dispose();
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      return const Scaffold(body: Center(child: Text("Not signed in")));
    }

    final threadId = threadIdFor(myUid, widget.peerUid);
    final threadRef = FirebaseFirestore.instance
        .collection('threads')
        .doc(threadId);
    final msgQuery = threadRef
        .collection('messages')
        .orderBy('createdAt', descending: false);

    return Scaffold(
      backgroundColor: KLPalette.bg,
      appBar: AppBar(
        title: StreamBuilder(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.peerUid)
              .snapshots(),
          builder: (context, snap) {
            final name = (snap.data?.data()?['name'] ?? 'User')
                .toString();
            return Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            );
          },
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: threadRef.snapshots(),
              builder: (context, threadSnap) {
                final threadData = threadSnap.data?.data() ?? {};
                final peerLastReadTs =
                    threadData['lastReadAt_${widget.peerUid}'];
                final peerLastReadAt = (peerLastReadTs is Timestamp)
                    ? peerLastReadTs.toDate()
                    : null;

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: msgQuery.snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData)
                      return const Center(child: CircularProgressIndicator());

                    final docs = snap.data!.docs;

                    if (!_didInitialScroll && docs.isNotEmpty) {
                      _didInitialScroll = true;

                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        _scrollToBottom(animated: false);
                        await Future.delayed(const Duration(milliseconds: 250));
                        _scrollToBottom(animated: false);
                      });
                    }

                    if (docs.length != _lastMsgCount) {
                      _lastMsgCount = docs.length;
                      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                    }

                    return ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final doc = docs[i];
                        final m = doc.data();

                        final senderId = (m['senderId'] ?? '').toString();
                        final type = (m['type'] ?? 'text').toString();
                        final text = (m['text'] ?? '').toString();
                        final imageUrl = (m['imageUrl'] ?? '').toString();
                        final audioUrl = (m['audioUrl'] ?? '').toString();

                        final ts = m['createdAt'];
                        final createdAt = (ts is Timestamp)
                            ? ts.toDate()
                            : null;

                        final isMe = senderId == myUid;

                        // Show "Seen" only on the last message that sent
                        final isLast = i == docs.length - 1;
                        final showSeen =
                            isMe &&
                            isLast &&
                            peerLastReadAt != null &&
                            createdAt != null &&
                            peerLastReadAt.isAfter(createdAt);

                        return _MessageBubbleFirestore(
                          docId: doc.id,
                          threadRef: threadRef,
                          fromMe: isMe,
                          type: type,
                          text: text,
                          imageUrl: imageUrl,
                          audioUrl: audioUrl,
                          timeText: createdAt == null
                              ? ""
                              : _fmtTime(createdAt),
                          showSeen: showSeen,
                          seenText: "Seen",
                          onOpenImage: (url) => _openImageViewer(context, url),
                          isLastMessage: isLast,
                          onLastMediaLaidOut: () => _scrollToBottom(animated: false),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          _Composer(
            controller: ctrl,
            typing: _typing,
            recording: _recording,
            onPickImage: () => _pickAndPreviewImage(myUid, widget.peerUid, threadRef),
            onMic: () => _onMicPressed(myUid, widget.peerUid, threadRef),
            onSend: () => _sendText(myUid, widget.peerUid, threadRef),
          ),
        ],
      ),
    );
  }

  Future<void> _sendText(
    String myUid,
    String peerUid,
    DocumentReference<Map<String, dynamic>> threadRef,
  ) async {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;

    ctrl.clear();

    final batch = FirebaseFirestore.instance.batch();
    final msgDoc = threadRef.collection('messages').doc();

    batch.set(threadRef, {
      'participants': [myUid, peerUid],
      'lastMessage': text,
      'lastMessageType': 'text',
      'lastSenderId': myUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'messageCount': FieldValue.increment(1),
      'unreadCount_$peerUid': FieldValue.increment(1),
      'unreadCount_$myUid': 0,
    }, SetOptions(merge: true));

    batch.set(msgDoc, {
      'senderId': myUid,
      'type': 'text',
      'text': text,
      'imageUrl': '',
      'audioUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> _markReadIfNeeded() async {
    if (_marked) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    final threadId = threadIdFor(myUid, widget.peerUid);
    final threadRef = FirebaseFirestore.instance
        .collection('threads')
        .doc(threadId);

    _marked = true;

    final snap = await threadRef.get();
    if (!snap.exists) return;

    await threadRef.set({
      'unreadCount_$myUid': 0,
      'lastReadAt_$myUid': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    return "${h.toString().padLeft(2, '0')}:$m";
  }

  void _openImageViewer(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ImageViewerScreen(url: url)),
    );
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollCtrl.hasClients) return;

    final target = _scrollCtrl.position.maxScrollExtent;
    if (animated) {
      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollCtrl.jumpTo(target);
    }
  }

  Future<void> _onMicPressed(
      String myUid,
      String peerUid,
      DocumentReference<Map<String, dynamic>> threadRef,
      ) async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_recording) {
      // stop and send
      final path = await _recorder.stop();
      setState(() => _recording = false);

      if (path == null || path.trim().isEmpty) return;
      await _sendAudioFile(myUid, peerUid, threadRef, File(path));
      return;
    }

    // start recording
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (!mounted) return;
      AppSnack.show(
        context,
        "Microphone permission not granted",
        type: AppSnackType.error,
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final fileName = "${DateTime.now().millisecondsSinceEpoch}_$myUid.m4a";
    final path = "${dir.path}/$fileName";
    _recordPath = path;

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: path,
    );

    setState(() => _recording = true);
  }

  Future<void> _sendAudioFile(
      String myUid,
      String peerUid,
      DocumentReference<Map<String, dynamic>> threadRef,
      File file,
      ) async {
    final threadId = threadRef.id;
    final fileName = "${DateTime.now().millisecondsSinceEpoch}_$myUid.m4a";

    final storageRef = FirebaseStorage.instance
        .ref()
        .child("chatAudios/$threadId/$fileName");

    final task = await storageRef.putFile(file);
    final url = await task.ref.getDownloadURL();

    final batch = FirebaseFirestore.instance.batch();
    final msgDoc = threadRef.collection('messages').doc();

    batch.set(threadRef, {
      'participants': [myUid, peerUid],
      'lastMessage': "[Voice]",
      'lastMessageType': 'audio',
      'lastSenderId': myUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'messageCount': FieldValue.increment(1),
      'unreadCount_$peerUid': FieldValue.increment(1),
      'unreadCount_$myUid': 0,
    }, SetOptions(merge: true));

    batch.set(msgDoc, {
      'senderId': myUid,
      'type': 'audio',
      'audioUrl': url,
      'text': '',
      'imageUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _pickAndPreviewImage(
      String myUid,
      String peerUid,
      DocumentReference<Map<String, dynamic>> threadRef,
      ) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    final file = File(picked.path);
    if (!mounted) return;

    final caption = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: KLPalette.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ImageCaptionSheet(file: file),
    );

    if (!mounted || caption == null) return;

    await _sendImage(
      myUid,
      peerUid,
      threadRef,
      file,
      caption: caption,
    );
  }

}

class _ImageCaptionSheet extends StatefulWidget {
  final File file;
  const _ImageCaptionSheet({required this.file});

  @override
  State<_ImageCaptionSheet> createState() => _ImageCaptionSheetState();
}

class _ImageCaptionSheetState extends State<_ImageCaptionSheet> {
  final captionCtrl = TextEditingController();

  @override
  void dispose() {
    captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _close({String? result}) async {
    FocusManager.instance.primaryFocus?.unfocus();

    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(
              widget.file,
              height: 260,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: captionCtrl,
            decoration: const InputDecoration(
              hintText: "Add a caption (optional)...",
              prefixIcon: Icon(Icons.edit_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _close(result: null),
                  child: const Text("Cancel"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _close(result: captionCtrl.text.trim()),
                  child: const Text("Send"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubbleFirestore extends StatelessWidget {
  final String docId;
  final DocumentReference<Map<String, dynamic>> threadRef;

  final bool fromMe;
  final String type;
  final String text;
  final String imageUrl;
  final String audioUrl;
  final String timeText;

  final bool showSeen;
  final String seenText;

  final bool isLastMessage;
  final VoidCallback onLastMediaLaidOut;

  final void Function(String url) onOpenImage;

  const _MessageBubbleFirestore({
    required this.docId,
    required this.threadRef,
    required this.fromMe,
    required this.type,
    required this.text,
    required this.imageUrl,
    required this.audioUrl,
    required this.timeText,
    required this.showSeen,
    required this.seenText,
    required this.isLastMessage,
    required this.onLastMediaLaidOut,
    required this.onOpenImage,
  });

  Future<void> _deleteIfAllowed(BuildContext context) async {
    if (!fromMe) return;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dCtx) => AlertDialog(
        title: const Text("Delete message?"),
        content: const Text("This will delete the message for both sides."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final msgRef = threadRef.collection('messages').doc(docId);

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(msgRef);
    batch.set(threadRef, {
      'messageCount': FieldValue.increment(-1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    if (!context.mounted) return;
    AppSnack.show(context, "Message deleted", type: AppSnackType.success);
  }

  @override
  Widget build(BuildContext context) {
    final isMe = fromMe;
    final bubbleColor = isMe ? KLPalette.primary : KLPalette.mutedBg;
    final textColor = isMe ? Colors.white : KLPalette.text;

    Widget content;
    if (type == 'image' && imageUrl.trim().isNotEmpty) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => onOpenImage(imageUrl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                imageUrl,
                width: 220,
                height: 220,
                fit: BoxFit.cover,
                loadingBuilder: (c, w, p) {
                  if (p == null) {
                    if (isLastMessage) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => onLastMediaLaidOut());
                    }
                    return w;
                  }
                  return const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
              ),
            ),
          ),
          if (text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ],
      );
    }
    else if (type == 'audio' && audioUrl.trim().isNotEmpty) {
      content = _AudioBubble(url: audioUrl, fromMe: isMe);
    }
    else {
      content = Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _deleteIfAllowed(context),
            child: Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Flexible(
                  child: Container(
                    padding: type == 'image'
                        ? const EdgeInsets.all(6)
                        : const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(18),
                      border: isMe ? null : Border.all(color: KLPalette.border),
                    ),
                    child: content,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(
                timeText,
                style: const TextStyle(
                  color: KLPalette.text2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (showSeen) ...[
                const SizedBox(width: 10),
                Text(
                  seenText,
                  style: const TextStyle(
                    color: KLPalette.text2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AudioBubble extends StatefulWidget {
  final String url;
  final bool fromMe;
  const _AudioBubble({required this.url, required this.fromMe});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  late final AudioPlayer _player;

  bool _loading = false;
  bool _dragging = false;

  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    // Position (updates frequently)
    _player.positionStream.listen((p) {
      if (!_dragging && mounted) {
        setState(() => _position = p);
      }
    });

    // Buffered position
    _player.bufferedPositionStream.listen((b) {
      if (mounted) setState(() => _buffered = b);
    });

    // Total duration (available after setUrl)
    _player.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    });

    // When finished, reset to start
    _player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        await _player.pause();
        await _player.seek(Duration.zero);
        if (mounted) setState(() => _position = Duration.zero);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_player.playing) {
      await _player.pause();
      if (mounted) setState(() {});
      return;
    }

    if (_player.processingState == ProcessingState.idle) {
      setState(() => _loading = true);
      try {
        await _player.setUrl(widget.url);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }

    await _player.play();
    if (mounted) setState(() {});
  }

  String _fmt(Duration d) {
    final totalSeconds = d.inSeconds;
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.fromMe ? Colors.white : KLPalette.text;

    final icon = _loading
        ? Icons.hourglass_top_rounded
        : (_player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded);

    // Avoid divide-by-zero
    final durMs = _duration.inMilliseconds;
    final posMs = _position.inMilliseconds.clamp(0, durMs == 0 ? 0 : durMs);
    final bufMs = _buffered.inMilliseconds.clamp(0, durMs == 0 ? 0 : durMs);

    final bufferedValue = (durMs <= 0) ? 0.0 : (bufMs / durMs).clamp(0.0, 1.0);

    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _loading ? null : _toggle,
                icon: Icon(icon, color: color),
              ),

              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Buffer progress behind slider
                    Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: SizedBox(
                            height: 4,
                            child: LinearProgressIndicator(value: bufferedValue),
                          ),
                        ),
                        Slider(
                          min: 0,
                          max: durMs <= 0 ? 1 : durMs.toDouble(),
                          value: durMs <= 0 ? 0 : posMs.toDouble(),
                          onChangeStart: (_) => setState(() => _dragging = true),
                          onChanged: (v) {
                            setState(() {
                              _position = Duration(milliseconds: v.toInt());
                            });
                          },
                          onChangeEnd: (v) async {
                            setState(() => _dragging = false);
                            await _player.seek(Duration(milliseconds: v.toInt()));
                          },
                        ),
                      ],
                    ),

                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Text(
                            _fmt(_position),
                            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                          const Spacer(),
                          Text(
                            _duration == Duration.zero ? "--:--" : _fmt(_duration),
                            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImageViewerScreen extends StatelessWidget {
  final String url;

  const _ImageViewerScreen({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          "Image",
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.network(url),
        ),
      ),
    );
  }
}

String threadIdFor(String a, String b) {
  final pair = [a, b]..sort();
  return "${pair[0]}_${pair[1]}";
}

Future<void> _sendImage(
    String myUid,
    String peerUid,
    DocumentReference<Map<String, dynamic>> threadRef,
    File file, {
      String caption = "",
    }) async {
  final threadId = threadRef.id;

  final fileName = "${DateTime.now().millisecondsSinceEpoch}_$myUid.jpg";
  final storageRef = FirebaseStorage.instance
      .ref()
      .child("chatImages/$threadId/$fileName");

  final task = await storageRef.putFile(file);
  final url = await task.ref.getDownloadURL();

  final batch = FirebaseFirestore.instance.batch();
  final msgDoc = threadRef.collection('messages').doc();

  // For thread list preview:
  final previewText = caption.isNotEmpty ? "📷 $caption" : "[Image]";

  batch.set(threadRef, {
    'participants': [myUid, peerUid],
    'lastMessage': previewText,
    'lastMessageType': 'image',
    'lastSenderId': myUid,
    'updatedAt': FieldValue.serverTimestamp(),
    'messageCount': FieldValue.increment(1),
    'unreadCount_$peerUid': FieldValue.increment(1),
    'unreadCount_$myUid': 0,
  }, SetOptions(merge: true));

  batch.set(msgDoc, {
    'senderId': myUid,
    'type': 'image',
    'imageUrl': url,
    'audioUrl': '',
    'text': caption,
    'createdAt': FieldValue.serverTimestamp(),
  });

  await batch.commit();
}


class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool typing;
  final bool recording;
  final VoidCallback onPickImage;
  final VoidCallback onMic;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.typing,
    required this.recording,
    required this.onPickImage,
    required this.onMic,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (typing) onSend();
                },
                decoration: InputDecoration(
                  hintText: "Type a message...",
                  prefixIcon: const Icon(Icons.chat_bubble_outline),
                  suffixIcon: IconButton(
                    onPressed: onPickImage,
                    icon: const Icon(Icons.image_outlined),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: typing ? onSend : onMic,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: KLPalette.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: KLPalette.border),
                ),
                child: Icon(
                  typing ? Icons.send_rounded : (recording ? Icons.stop_rounded : Icons.mic_rounded),
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
