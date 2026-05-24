import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CoinService {
  static const int signupBonus = 500;
  static const int dailyOpenReward = 20;
  static const int adReward = 20;
  static const int checkInGoalDays = 7;
  static const int checkInGoalReward = 50;


  static DocumentReference<Map<String, dynamic>>? get _userRef {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  static Stream<int> coinStream() {
    final ref = _userRef;
    if (ref == null) {
      return const Stream<int>.empty();
    }

    return ref.snapshots().map((snapshot) {
      final data = snapshot.data();
      final coins = data?['coins'];
      if (coins is int) return coins;
      if (coins is num) return coins.toInt();
      return 0;
    });
  }

  static Stream<Map<String, dynamic>?> walletStream() {
    final ref = _userRef;
    if (ref == null) {
      return const Stream<Map<String, dynamic>?>.empty();
    }
    return ref.snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return _normalizedWalletData(data);
    });
  }

  static Stream<List<CoinHistoryEntry>> historyStream() {
    final ref = _userRef;
    if (ref == null) {
      return const Stream<List<CoinHistoryEntry>>.empty();
    }

    return ref
        .collection('coin_history')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CoinHistoryEntry.fromMap(doc.data()))
              .toList(),
        );
  }

  static Future<void> addCoins(
    int amount, {
    String title = 'Reward added',
    String type = 'reward',
  }) async {
    if (amount <= 0) return;
    final ref = _userRef;
    if (ref == null) return;

    await _applyDelta(
      ref: ref,
      amount: amount,
      title: title,
      type: type,
      enforceBalance: false,
    );
  }

  static Future<void> useCoins(
    int amount, {
    String title = 'Coins used',
    String type = 'spent',
  }) async {
    if (amount <= 0) return;
    final ref = _userRef;
    if (ref == null) return;

    await _applyDelta(
      ref: ref,
      amount: -amount,
      title: title,
      type: type,
      enforceBalance: true,
    );
  }

  static Future<int> claimDailyOpenReward() {
    final ref = _userRef;
    if (ref == null) return Future.value(0);

    return _claimDailyReward(
      ref: ref,
      rewardKey: 'lastOpenRewardAt',
      amount: dailyOpenReward,
      title: 'Daily open reward',
      type: 'daily_open',
    );
  }

  static Future<int> claimAdReward() {
    final ref = _userRef;
    if (ref == null) return Future.value(0);

    return _claimDailyReward(
      ref: ref,
      rewardKey: 'lastAdRewardAt',
      amount: adReward,
      title: 'Ad reward',
      type: 'ad_reward',
    );
  }


  static Future<int> claimCheckInReward() {
    final ref = _userRef;
    if (ref == null) return Future.value(0);

    return FirebaseFirestore.instance.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data() ?? <String, dynamic>{};
      final now = DateTime.now();
      final lastCheckIn = (data['lastCheckInAt'] as Timestamp?)?.toDate();

      if (lastCheckIn != null && _isSameDay(lastCheckIn, now)) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'already-claimed',
          message: 'Today check-in already claimed.',
        );
      }

      final previousDay = now.subtract(const Duration(days: 1));
      final currentStreak = (data['checkInStreak'] as num?)?.toInt() ?? 0;
      final nextStreak = lastCheckIn != null && _isSameDay(lastCheckIn, previousDay)
          ? currentStreak + 1
          : 1;
      final completedCycle = nextStreak >= checkInGoalDays;
      final amount = completedCycle ? checkInGoalReward : 0;
      final currentCoins = (data['coins'] as num?)?.toInt() ?? 0;
      final historyRef = amount > 0 ? ref.collection('coin_history').doc() : null;

      transaction.set(ref, {
        'coins': currentCoins + amount,
        'checkInStreak': completedCycle ? 0 : nextStreak,
        'lastCheckInAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
      if (historyRef != null) {
        transaction.set(historyRef, {
          'amount': amount,
          'title': '7 day check-in reward',
          'type': 'check_in',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return amount;
    });
  }

  static Future<int> _claimDailyReward({
    required DocumentReference<Map<String, dynamic>> ref,
    required String rewardKey,
    required int amount,
    required String title,
    required String type,
  }) async {
    return FirebaseFirestore.instance.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data() ?? <String, dynamic>{};
      final now = DateTime.now();
      final lastClaim = (data[rewardKey] as Timestamp?)?.toDate();

      if (lastClaim != null && _isSameDay(lastClaim, now)) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'already-claimed',
          message: 'Reward already claimed today.',
        );
      }

      final currentCoins = (data['coins'] as num?)?.toInt() ?? 0;
      final historyRef = ref.collection('coin_history').doc();

      transaction.set(ref, {
        'coins': currentCoins + amount,
        rewardKey: Timestamp.fromDate(now),
      }, SetOptions(merge: true));
      transaction.set(historyRef, {
        'amount': amount,
        'title': title,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return amount;
    });
  }

  static Future<void> _applyDelta({
    required DocumentReference<Map<String, dynamic>> ref,
    required int amount,
    required String title,
    required String type,
    required bool enforceBalance,
  }) async {
    await FirebaseFirestore.instance.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data() ?? <String, dynamic>{};
      final currentCoins = (data['coins'] as num?)?.toInt() ?? 0;
      final nextCoins = currentCoins + amount;

      if (enforceBalance && nextCoins < 0) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'insufficient-coins',
          message: 'Not enough coins.',
        );
      }

      final historyRef = ref.collection('coin_history').doc();
      transaction.set(ref, {
        'coins': nextCoins,
      }, SetOptions(merge: true));
      transaction.set(historyRef, {
        'amount': amount,
        'title': title,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static Map<String, dynamic> _normalizedWalletData(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    final lastCheckIn = (data['lastCheckInAt'] as Timestamp?)?.toDate();
    final streak = (data['checkInStreak'] as num?)?.toInt() ?? 0;

    if (lastCheckIn == null || streak <= 0) {
      normalized['checkInStreak'] = 0;
      return normalized;
    }

    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final stillActive = _isSameDay(lastCheckIn, now) || _isSameDay(lastCheckIn, yesterday);

    normalized['checkInStreak'] = stillActive ? streak : 0;
    return normalized;
  }

  static const _historyCacheKey = 'coin_history_cache';

  static Future<List<CoinHistoryEntry>> loadLocalHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_historyCacheKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];

      final list = json.decode(jsonStr) as List<dynamic>;
      return list.map((item) => CoinHistoryEntry.fromMap(Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLocalHistory(List<CoinHistoryEntry> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = entries.map((e) => e.toMap()).toList();
      await prefs.setString(_historyCacheKey, json.encode(list));
    } catch (_) {}
  }

  static String generateReferralCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = math.Random();
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  static Future<String> generateUniqueReferralCode() async {
    while (true) {
      final code = generateReferralCode();
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('referralCode', isEqualTo: code)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        return code;
      }
    }
  }

  static Future<void> claimReferralCode({
    required String code,
    required String currentUid,
  }) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(currentUid);
    
    final referrerQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('referralCode', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();

    if (referrerQuery.docs.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-code',
        message: 'Invalid referral code.',
      );
    }

    final referrerDoc = referrerQuery.docs.first;
    final referrerUid = referrerDoc.id;

    if (referrerUid == currentUid) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'self-referral',
        message: 'You cannot claim your own code.',
      );
    }

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final userSnap = await transaction.get(userRef);
      final userData = userSnap.data() ?? <String, dynamic>{};

      if (userData['referralClaimed'] == true) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'already-claimed',
          message: 'You have already claimed a referral bonus.',
        );
      }

      final currentCoins = (userData['coins'] as num?)?.toInt() ?? 0;
      final nextCoins = currentCoins + 100;

      final historyRef = userRef.collection('coin_history').doc();
      
      transaction.set(userRef, {
        'coins': nextCoins,
        'referralClaimed': true,
        'referredBy': referrerUid,
      }, SetOptions(merge: true));

      transaction.set(historyRef, {
        'amount': 100,
        'title': 'Referral claim bonus',
        'type': 'referral_claim',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

class CoinHistoryEntry {
  const CoinHistoryEntry({
    required this.amount,
    required this.title,
    required this.type,
    required this.createdAt,
  });

  factory CoinHistoryEntry.fromMap(Map<String, dynamic> map) {
    DateTime? createdAtDate;
    final rawCreated = map['createdAt'];
    if (rawCreated is Timestamp) {
      createdAtDate = rawCreated.toDate();
    } else if (rawCreated is String) {
      createdAtDate = DateTime.tryParse(rawCreated);
    }
    return CoinHistoryEntry(
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      title: (map['title'] as String?) ?? 'Coin update',
      type: (map['type'] as String?) ?? 'reward',
      createdAt: createdAtDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'title': title,
      'type': type,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  final int amount;
  final String title;
  final String type;
  final DateTime? createdAt;
}
