import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'coin_badge.dart';
import 'coin_service.dart';
import 'screen_constants.dart';

class CoinsScreen extends StatelessWidget {
  const CoinsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: CoinService.walletStream(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? <String, dynamic>{};
        final coins = (data['coins'] as num?)?.toInt() ?? 0;
        final streak = (data['checkInStreak'] as num?)?.toInt() ?? 0;
        final dailyOpenClaimed = _isClaimedToday(data['lastOpenRewardAt']);
        final adRewardClaimed = _isClaimedToday(data['lastAdRewardAt']);
        final checkInClaimed = _isClaimedToday(data['lastCheckInAt']);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Coins'),
            actions: const [CoinBadge(), SizedBox(width: 16)],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _WalletCard(coins: coins, streak: streak),
              const SizedBox(height: 22),
              Text(
                'Earn Coins',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 14),
              _RewardActionCard(
                title: 'Daily Open Reward',
                subtitle: '+${CoinService.dailyOpenReward} coins once per day',
                icon: Icons.card_giftcard_rounded,
                buttonText: dailyOpenClaimed ? 'Claimed' : 'Claim',
                enabled: !dailyOpenClaimed,
                onTap: dailyOpenClaimed
                    ? null
                    : () => _runRewardAction(
                          context,
                          () => CoinService.claimDailyOpenReward(),
                          successPrefix: 'Daily reward claimed',
                        ),
              ),
              const SizedBox(height: 12),
              _RewardActionCard(
                title: 'Watch Ad Reward',
                subtitle: '+${CoinService.adReward} coins once per day',
                icon: Icons.ondemand_video_rounded,
                buttonText: adRewardClaimed ? 'Claimed' : 'Watch',
                enabled: !adRewardClaimed,
                onTap: adRewardClaimed
                    ? null
                    : () => _runRewardAction(
                          context,
                          () => CoinService.claimAdReward(),
                          successPrefix: 'Ad reward claimed',
                        ),
              ),

              const SizedBox(height: 12),
              _RewardActionCard(
                title: '7 Day Check-In',
                subtitle: 'Check in daily. Get +${CoinService.checkInGoalReward} coins on day ${CoinService.checkInGoalDays}',
                icon: Icons.local_fire_department_rounded,
                buttonText: checkInClaimed ? 'Claimed' : 'Check In',
                enabled: !checkInClaimed,
                onTap: checkInClaimed
                    ? null
                    : () => _runRewardAction(
                          context,
                          () => CoinService.claimCheckInReward(),
                          successPrefix: 'Check-in updated',
                        ),
              ),
              const SizedBox(height: 24),
              StreamBuilder<List<CoinHistoryEntry>>(
                stream: CoinService.historyStream(),
                builder: (context, snapshot) {
                  final items = snapshot.data ?? const <CoinHistoryEntry>[];
                  final hasMore = items.length > 5;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Coin History',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          if (hasMore)
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AllCoinHistoryScreen(),
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              child: const Text(
                                'See All',
                                style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (items.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            color: Theme.of(context).brightness == Brightness.dark
                                ? cardBackground
                                : Colors.grey.shade100,
                          ),
                          child: const Text('No coin history yet'),
                        )
                      else
                        ...items.take(5).map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _HistoryTile(item: item),
                            )),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isClaimedToday(dynamic value) {
    if (value is! Timestamp) return false;
    final date = value.toDate();
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Future<void> _runRewardAction(
    BuildContext context,
    Future<int> Function() action, {
    required String successPrefix,
  }) async {
    try {
      final amount = await action();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: primaryColor,
          content: Text(
            amount > 0
                ? '$successPrefix: +$amount coins'
                : 'Check-in saved. Complete 7 days to unlock reward.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      final message = e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            message.contains('already-claimed') || message.contains('already claimed')
                ? 'Already claimed for today'
                : message,
          ),
        ),
      );
    }
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.coins,
    required this.streak,
  });

  final int coins;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final progress = (streak / CoinService.checkInGoalDays).clamp(0.0, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: isDark ? cardBackground : Colors.grey.shade100,
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check-in streak: $streak / ${CoinService.checkInGoalDays} days',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${CoinService.checkInGoalDays - streak} days left for +${CoinService.checkInGoalReward} coins',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: primaryColor.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardActionCard extends StatelessWidget {
  const _RewardActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.buttonText,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String buttonText;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: enabled ? 1 : 0.48,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: isDark ? cardBackground : Colors.grey.shade100,
          border: Border.all(
            color: primaryColor.withValues(alpha: enabled ? 0.14 : 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: primaryColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: enabled
                    ? primaryColor
                    : primaryColor.withValues(alpha: 0.45),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}

class AllCoinHistoryScreen extends StatefulWidget {
  const AllCoinHistoryScreen({super.key});

  @override
  State<AllCoinHistoryScreen> createState() => _AllCoinHistoryScreenState();
}

class _AllCoinHistoryScreenState extends State<AllCoinHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<DocumentSnapshot<Map<String, dynamic>>> _docs = [];
  List<CoinHistoryEntry> _cachedEntries = [];
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _initData();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _initData() async {
    final cached = await CoinService.loadLocalHistory();
    if (mounted && cached.isNotEmpty && _docs.isEmpty) {
      setState(() {
        _cachedEntries = cached;
      });
    }
    await _loadMore();
  }

  Future<void> _refresh() async {
    setState(() {
      _docs.clear();
      _cachedEntries.clear();
      _hasMore = true;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      var query = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('coin_history')
          .orderBy('createdAt', descending: true)
          .limit(12);

      if (_docs.isNotEmpty) {
        query = query.startAfterDocument(_docs.last);
      }

      final snapshot = await query.get();
      if (snapshot.docs.length < 12) {
        _hasMore = false;
      }

      if (_docs.isEmpty && snapshot.docs.isNotEmpty) {
        final freshEntries = snapshot.docs
            .map((doc) => CoinHistoryEntry.fromMap(doc.data()))
            .toList();
        await CoinService.saveLocalHistory(freshEntries);
      }

      if (mounted) {
        setState(() {
          _docs.addAll(snapshot.docs);
          _cachedEntries.clear();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCached = _docs.isEmpty && _cachedEntries.isNotEmpty;
    final displayList = showCached
        ? _cachedEntries
        : _docs.map((doc) => CoinHistoryEntry.fromMap(doc.data() ?? {})).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coin History'),
        centerTitle: true,
      ),
      body: displayList.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : displayList.isEmpty
              ? const Center(child: Text('No coin history yet'))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: primaryColor,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: displayList.length + (_hasMore && !showCached ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == displayList.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _HistoryTile(item: displayList[index]),
                      );
                    },
                  ),
                ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final CoinHistoryEntry item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPositive = item.amount >= 0;
    final amountColor = isPositive ? const Color(0xFF39D98A) : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark ? cardBackground : Colors.grey.shade100,
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPositive ? Icons.add_rounded : Icons.remove_rounded,
              color: amountColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(item.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                      ),
                ),
              ],
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}${item.amount}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Just now';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final meridiem = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.day}/${date.month}/${date.year}  $hour:$minute $meridiem';
  }
}
