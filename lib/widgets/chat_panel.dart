import 'package:flutter/material.dart';
import '../models/models.dart';

class ChatPanel extends StatelessWidget {
  final List<ChatMessage> messages;
  final TextEditingController inputController;
  final ScrollController scrollController;
  final VoidCallback onSend;

  const ChatPanel({
    super.key,
    required this.messages,
    required this.inputController,
    required this.scrollController,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade900,
      child: Column(
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.grey.shade800,
            child: const Row(
              children: [
                Icon(Icons.chat, color: Colors.white54, size: 16),
                SizedBox(width: 6),
                Text(
                  '内部通信',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),

          // 消息列表
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      '暂无消息',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 发送者名单独占一行并允许截断：名字从服务端来，
                            // 可能是「超级管理员」这种长词，跟内容挤在一行
                            // 会把正文挤成两三行，很难读。
                            SizedBox(
                              width: 64,
                              child: Text(
                                '${msg.sender}: ',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: msg.isMine
                                      ? Colors.blue
                                      : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                msg.content,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // 输入框
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade800,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputController,
                    decoration: InputDecoration(
                      hintText: '输入消息...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.grey.shade700,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onSend,
                  icon: const Icon(Icons.send, color: Colors.blue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
