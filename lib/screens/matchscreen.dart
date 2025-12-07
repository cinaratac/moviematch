import 'package:flutter/material.dart';

class MatchPage extends StatelessWidget {
  const MatchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(radius: 64, child: Icon(Icons.person, size: 64)),
            const SizedBox(height: 16),
            Text('Ethan, 27', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: () {},
                  child: const Icon(Icons.close),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: () {},
                  child: const Icon(Icons.favorite),
                ),
                const SizedBox(width: 16),
                FilledButton.tonal(
                  onPressed: () {},
                  child: const Icon(Icons.star),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
