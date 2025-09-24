import 'package:flutter/material.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 12,
        itemBuilder: (context, i) {
          final isMe = i.isEven;
          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: isMe
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMe ? 14 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 14),
                ),
              ),
              child: Text(
                isMe
                    ? 'Hey! Did you watch The Godfather?'
                    : 'Yes! It\'s a classic. What\'s next on your list?',
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Write a message…',
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                ),
                child: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
