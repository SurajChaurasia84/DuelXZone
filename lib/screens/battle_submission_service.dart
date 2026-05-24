import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import '../services/cloudinary_service.dart';

enum BattleSubmissionKind { daily, weekly, mega }

class BattleSubmissionCycle {
  const BattleSubmissionCycle({
    required this.kind,
    required this.id,
    required this.title,
    required this.entryFee,
    required this.battleCount,
    required this.liveStart,
    required this.isLiveDay,
    required this.statusText,
    required this.countdownText,
  });

  final BattleSubmissionKind kind;
  final String id;
  final String title;
  final int entryFee;
  final int battleCount;
  final DateTime liveStart;
  final bool isLiveDay;
  final String statusText;
  final String countdownText;
}

class BattleSubmissionUser {
  const BattleSubmissionUser({
    required this.uid,
    required this.username,
    required this.email,
    required this.name,
    required this.photo,
  });

  final String uid;
  final String username;
  final String email;
  final String name;
  final String photo;
}

class BattleSubmissionService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static BattleSubmissionCycle cycleFor(BattleSubmissionKind kind, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (kind) {
      case BattleSubmissionKind.daily:
        final end = today.add(const Duration(days: 1));
        return BattleSubmissionCycle(
          kind: kind,
          id: 'daily-${_formatDate(today)}',
          title: 'Daily Battles',
          entryFee: 50,
          battleCount: 1,
          liveStart: today,
          isLiveDay: true,
          statusText: 'Live today',
          countdownText: 'Ends in ${_formatDuration(end.difference(now))}',
        );
      case BattleSubmissionKind.weekly:
        final daysUntilSunday = (DateTime.sunday - now.weekday) % 7;
        final isLiveDay = now.weekday == DateTime.sunday;
        final liveStart = today.add(Duration(days: daysUntilSunday));
        final activeStart = isLiveDay ? today : liveStart;
        final activeEnd = activeStart.add(const Duration(days: 1));
        return BattleSubmissionCycle(
          kind: kind,
          id: 'weekly-${_formatDate(activeStart)}',
          title: 'Weekly Tournament',
          entryFee: 500,
          battleCount: 3,
          liveStart: activeStart,
          isLiveDay: isLiveDay,
          statusText: isLiveDay ? 'Live today' : 'Registration open',
          countdownText: isLiveDay
              ? 'Ends in ${_formatDuration(activeEnd.difference(now))}'
              : 'Live in ${_formatDuration(activeStart.difference(now))}',
        );
      case BattleSubmissionKind.mega:
        final isLiveDay = now.day == 1 || now.day == 15;
        final liveStart = _nextMegaLiveDay(today, now.day);
        final activeStart = isLiveDay ? today : liveStart;
        final activeEnd = activeStart.add(const Duration(days: 1));
        return BattleSubmissionCycle(
          kind: kind,
          id: 'mega-${_formatDate(activeStart)}',
          title: 'Mega Tournament',
          entryFee: 1000,
          battleCount: 3,
          liveStart: activeStart,
          isLiveDay: isLiveDay,
          statusText: isLiveDay ? 'Live today' : 'Registration open',
          countdownText: isLiveDay
              ? 'Ends in ${_formatDuration(activeEnd.difference(now))}'
              : 'Live in ${_formatDuration(activeStart.difference(now))}',
        );
    }
  }

  static Future<BattleSubmissionUser> currentUserMeta() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'unauthenticated',
        message: 'Please sign in again.',
      );
    }

    final userSnap = await _firestore.collection('users').doc(authUser.uid).get();
    final data = userSnap.data() ?? <String, dynamic>{};
    final username = ((data['username'] as String?) ?? '').trim();
    if (username.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'username-missing',
        message: 'Set your username before joining battles.',
      );
    }

    final name = ((data['name'] as String?)?.trim().isNotEmpty == true)
        ? (data['name'] as String).trim()
        : ((authUser.displayName ?? 'Player').trim());

    return BattleSubmissionUser(
      uid: authUser.uid,
      username: username,
      email: authUser.email ?? '',
      name: name,
      photo: ((data['photo'] as String?) ?? authUser.photoURL ?? '').trim(),
    );
  }

  static CollectionReference<Map<String, dynamic>> participantsCollection(String cycleId) {
    return _firestore.collection(cycleId).doc('participants').collection('entries');
  }

  static DocumentReference<Map<String, dynamic>> participantDoc({
    required String cycleId,
    required String username,
  }) {
    return participantsCollection(cycleId).doc(username);
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> participantStream({
    required String cycleId,
    required String username,
  }) {
    return participantDoc(cycleId: cycleId, username: username).snapshots();
  }

  static Stream<int> registeredCountStream(String cycleId) {
    return participantsCollection(cycleId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  static Future<void> joinTournament({
    required BattleSubmissionCycle cycle,
    required BattleSubmissionUser user,
  }) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final participantRef = participantDoc(
      cycleId: cycle.id,
      username: user.username,
    );

    await _firestore.runTransaction<void>((transaction) async {
      final existing = await transaction.get(participantRef);
      if (existing.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'already-exists',
          message: 'You already joined this battle cycle.',
        );
      }

      final userSnap = await transaction.get(userRef);
      final coins = (userSnap.data()?['coins'] as num?)?.toInt() ?? 0;
      if (coins < cycle.entryFee) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'insufficient-coins',
          message: 'Not enough coins to join battles.',
        );
      }

      final battleData = <String, dynamic>{};
      for (var index = 1; index <= cycle.battleCount; index++) {
        battleData['battle$index'] = <String, dynamic>{};
      }

      transaction.set(participantRef, {
        'userId': user.uid,
        'username': user.username,
        'name': user.name,
        'photo': user.photo,
        'email': user.email,
        'totalScore': 0,
        'isapprove': false,
        'submittedAt': null,
        'joinedAt': FieldValue.serverTimestamp(),
        ...battleData,
      });

      transaction.set(userRef, {
        'coins': coins - cycle.entryFee,
      }, SetOptions(merge: true));

      transaction.set(userRef.collection('coin_history').doc(), {
        'amount': -cycle.entryFee,
        'title': '${cycle.title} join',
        'type': 'battle_join',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> submitBattle({
    required String cycleId,
    required String username,
    required int battleNumber,
    required int battleCount,
    required int kills,
    required String rank,
    required File imageFile,
  }) async {
    final participantRef = participantDoc(cycleId: cycleId, username: username);
    final snap = await participantRef.get();
    final data = snap.data();
    if (data == null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-joined',
        message: 'Join this battle first.',
      );
    }
    if (data['submittedAt'] != null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'already-submitted',
        message: 'Final submission already done.',
      );
    }
    if (battleNumber > 1 && !_isBattleCompleted(data['battle${battleNumber - 1}'])) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'locked',
        message: 'Complete previous battle first.',
      );
    }
    if (_isBattleCompleted(data['battle$battleNumber'])) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'already-completed',
        message: 'This battle is already completed.',
      );
    }
    if (battleNumber > battleCount) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-battle',
        message: 'Invalid battle selected.',
      );
    }

    final imageUrl = await _uploadFile(
      cycleId: cycleId,
      username: username,
      battleNumber: battleNumber,
      type: 'image',
      file: imageFile,
    );

    final points = calculatePoints(kills: kills, rank: rank);

    await participantRef.set({
      'battle$battleNumber': {
        'kills': kills,
        'rank': rank,
        'image': imageUrl,
        'points': points,
      },
    }, SetOptions(merge: true));
  }

  static Future<void> finalSubmit({
    required String cycleId,
    required String username,
    required int battleCount,
  }) async {
    final participantRef = participantDoc(cycleId: cycleId, username: username);
    final snap = await participantRef.get();
    final data = snap.data();
    if (data == null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-joined',
        message: 'Join this battle first.',
      );
    }
    if (data['submittedAt'] != null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'already-submitted',
        message: 'Already submitted.',
      );
    }

    var totalScore = 0;
    for (var index = 1; index <= battleCount; index++) {
      final battle = data['battle$index'];
      if (!_isBattleCompleted(battle)) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'incomplete',
          message: 'Complete all battles first.',
        );
      }
      totalScore += (battle['points'] as num?)?.toInt() ?? 0;
    }

    await participantRef.set({
      'totalScore': totalScore,
      'isapprove': false,
      'submittedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static int calculatePoints({
    required int kills,
    required String rank,
  }) {
    final rankPoints = switch (rank) {
      '1' => 10,
      '2-5' => 7,
      '6-10' => 5,
      '11-20' => 3,
      _ => 1,
    };
    return (kills * 2) + rankPoints;
  }

  static int nextUnlockedBattle({
    required Map<String, dynamic>? participantData,
    required int battleCount,
  }) {
    if (participantData == null) return 1;
    for (var index = 1; index <= battleCount; index++) {
      if (!_isBattleCompleted(participantData['battle$index'])) {
        return index;
      }
    }
    return battleCount;
  }

  static bool isBattleCompleted(dynamic battle) => _isBattleCompleted(battle);

  static bool _isBattleCompleted(dynamic battle) {
    if (battle is! Map) return false;
    return battle['kills'] != null &&
        battle['rank'] != null &&
        battle['image'] != null &&
        battle['points'] != null;
  }

  static Future<String> _uploadFile({
    required String cycleId,
    required String username,
    required int battleNumber,
    required String type,
    required File file,
  }) async {
    final folder = 'battle_submissions/$cycleId/$username/battle$battleNumber';
    
    // Determine resource type (image or video)
    final resourceType = type == 'video' 
        ? CloudinaryResourceType.Video 
        : CloudinaryResourceType.Image;

    return CloudinaryService().uploadFile(
      file: file,
      folder: folder,
      resourceType: resourceType,
    );
  }

  static DateTime _nextMegaLiveDay(DateTime today, int currentDay) {
    if (currentDay < 15) return DateTime(today.year, today.month, 15);
    return DateTime(today.year, today.month + 1, 1);
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String _formatDuration(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final days = safe.inDays;
    final hours = safe.inHours.remainder(24).toString().padLeft(2, '0');
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (days > 0) return '${days}d ${hours}h ${minutes}m';
    return '${hours}h ${minutes}m ${seconds}s';
  }
}
