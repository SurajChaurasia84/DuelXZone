import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'navigation_controller.dart';
import 'screen_constants.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        elevation: 0,
      ),
      body: user == null
          ? const _EmptyNotifications()
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('recipientId', whereIn: [user.uid, 'all', 'ALL_USERS'])
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const _EmptyNotifications();
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: docs.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    return _NotificationTile(data: data);
                  },
                );
              },
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timestamp = data['timestamp'] as Timestamp?;
    final title = data['title'] as String? ?? 'Notification';
    final body = data['body'] as String? ?? '';
    final type = data['type'] as String? ?? 'system';
    final dateStr = timestamp != null
        ? DateFormat('MMM dd, hh:mm a').format(timestamp.toDate())
        : '';

    IconData icon;
    Color iconColor;
    switch (type) {
      case 'battle':
        icon = Icons.shield_rounded;
        iconColor = Colors.blueAccent;
        break;
      case 'reward':
        icon = Icons.card_giftcard_rounded;
        iconColor = Colors.orangeAccent;
        break;
      case 'system':
        icon = Icons.info_outline_rounded;
        iconColor = primaryColor;
        break;
      default:
        icon = Icons.notifications_rounded;
        iconColor = primaryColor;
    }

    return GestureDetector(
      onTap: () {
        // Navigate based on type
        switch (type) {
          case 'battle':
            AppTabController.goTo(1);
            break;
          case 'reward':
            AppTabController.goTo(2);
            break;
          default:
            // Do nothing for system or unknown types
            return;
        }
        
        // Close the notification screen to show the target tab
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? cardBackground : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        dateStr,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7),
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 80,
            width: 80,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 40,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No notifications yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'We\'ll notify you when something important happens.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }
}
