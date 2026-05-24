import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import '../services/cloudinary_service.dart';

class TournamentJoinAction {
  const TournamentJoinAction({
    required this.title,
    required this.cycleId,
    required this.liveStart,
    required this.battleCount,
  });

  final String title;
  final String cycleId;
  final DateTime liveStart;
  final int battleCount;
}

class TournamentService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  static const Duration battleDuration = Duration(minutes: 30);

  static Future<void> registerForTournament({
    required String cycleId,
    required String title,
    required String type,
    required int entryFee,
    required DateTime liveAt,
    required bool isLiveDay,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'unauthenticated',
        message: 'Please sign in to register.',
      );
    }

    final rootRef = _firestore.collection('tournament_registrations').doc(cycleId);
    final participantRef = rootRef.collection('participants').doc(user.uid);
    final userRef = _firestore.collection('users').doc(user.uid);

    await _firestore.runTransaction<void>((transaction) async {
      final participantSnap = await transaction.get(participantRef);
      if (participantSnap.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'already-registered',
          message: 'You are already registered for this tournament.',
        );
      }

      final userSnap = await transaction.get(userRef);
      final userData = userSnap.data() ?? <String, dynamic>{};
      final currentCoins = (userData['coins'] as num?)?.toInt() ?? 0;
      if (currentCoins < entryFee) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'insufficient-coins',
          message: 'Not enough coins to register.',
        );
      }

      final username = ((userData['username'] as String?)?.trim().isNotEmpty == true)
          ? (userData['username'] as String).trim()
          : (user.displayName ?? 'Player');

      transaction.set(rootRef, {
        'id': cycleId,
        'type': type,
        'title': title,
        'entryFee': entryFee,
        'liveAt': Timestamp.fromDate(liveAt),
        'isLiveDay': isLiveDay,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(participantRef, {
        'uid': user.uid,
        'name': username,
        'email': user.email ?? '',
        'photo': user.photoURL ?? '',
        'registeredAt': FieldValue.serverTimestamp(),
        'entryFeePaid': entryFee,
        'battle1': _emptyBattleMap(1),
        'battle2': _emptyBattleMap(2),
        'battle3': _emptyBattleMap(3),
      });

      transaction.set(userRef, {
        'coins': currentCoins - entryFee,
      }, SetOptions(merge: true));

      final historyRef = userRef.collection('coin_history').doc();
      transaction.set(historyRef, {
        'amount': -entryFee,
        'title': '$title registration',
        'type': 'tournament_registration',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> participantStream(String cycleId) {
    final user = FirebaseAuth.instance.currentUser!;
    return _firestore
        .collection('tournament_registrations')
        .doc(cycleId)
        .collection('participants')
        .doc(user.uid)
        .snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> battleRoomStream({
    required String cycleId,
    required String roomId,
  }) {
    return _firestore
        .collection('tournament_registrations')
        .doc(cycleId)
        .collection('battle_rooms')
        .doc(roomId)
        .snapshots();
  }

  static Future<String> joinOrCreateBattleRoom({
    required String cycleId,
    required int battleNumber,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'unauthenticated',
        message: 'Please sign in again.',
      );
    }

    final participantRef = _firestore
        .collection('tournament_registrations')
        .doc(cycleId)
        .collection('participants')
        .doc(user.uid);
    final participantSnap = await participantRef.get();
    final participantData = participantSnap.data();
    if (participantData == null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
        message: 'You are not registered for this tournament.',
      );
    }

    final battleKey = 'battle$battleNumber';
    final battleMap = Map<String, dynamic>.from(
      (participantData[battleKey] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
    final existingMatchId = (battleMap['matchId'] as String?)?.trim() ?? '';
    if (existingMatchId.isNotEmpty) {
      return existingMatchId;
    }

    final waitingRooms = await _firestore
        .collection('tournament_registrations')
        .doc(cycleId)
        .collection('battle_rooms')
        .where('battleNumber', isEqualTo: battleNumber)
        .where('status', isEqualTo: 'waiting')
        .limit(10)
        .get();

    for (final doc in waitingRooms.docs) {
      final matched = await _tryJoinExistingBattleRoom(
        cycleId: cycleId,
        battleNumber: battleNumber,
        roomRef: doc.reference,
        participantRef: participantRef,
        participantData: participantData,
        uid: user.uid,
      );
      if (matched) {
        return doc.id;
      }
    }

    final roomRef = _firestore
        .collection('tournament_registrations')
        .doc(cycleId)
        .collection('battle_rooms')
        .doc();
    final now = DateTime.now();

    await _firestore.runTransaction<void>((transaction) async {
      final freshParticipant = await transaction.get(participantRef);
      final freshData = freshParticipant.data() ?? <String, dynamic>{};
      final freshBattle = Map<String, dynamic>.from(
        (freshData[battleKey] as Map<String, dynamic>?) ?? <String, dynamic>{},
      );
      final roomId = (freshBattle['matchId'] as String?)?.trim() ?? '';
      if (roomId.isNotEmpty) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'already-joined',
          message: 'You already joined this battle.',
        );
      }

      transaction.set(roomRef, {
        'battleNumber': battleNumber,
        'status': 'waiting',
        'createdBy': user.uid,
        'playerIds': [user.uid],
        'players': {
          user.uid: _roomPlayerData(freshData, user.uid),
        },
        'createdAt': Timestamp.fromDate(now),
        'startedAt': null,
        'expiresAt': null,
      });
      transaction.set(participantRef, {
        '$battleKey.matchId': roomRef.id,
      }, SetOptions(merge: true));
    });

    return roomRef.id;
  }

  static Future<void> uploadBattleProof({
    required String cycleId,
    required int battleNumber,
    required String roomId,
    required File file,
    required int kills,
    required String rank,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'unauthenticated',
        message: 'Please sign in again.',
      );
    }

    final participantRef = _firestore
        .collection('tournament_registrations')
        .doc(cycleId)
        .collection('participants')
        .doc(user.uid);
    final roomRef = _firestore
        .collection('tournament_registrations')
        .doc(cycleId)
        .collection('battle_rooms')
        .doc(roomId);

    final participantSnap = await participantRef.get();
    if (!participantSnap.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-registered',
        message: 'You are not registered for this tournament.',
      );
    }

    final roomSnap = await roomRef.get();
    final roomData = roomSnap.data();
    if (roomData == null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'room-missing',
        message: 'Match room not found.',
      );
    }

    final playerIds = List<String>.from(roomData['playerIds'] as List<dynamic>? ?? []);
    if (!playerIds.contains(user.uid)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-in-room',
        message: 'You are not part of this match.',
      );
    }

    final expiresAt = roomData['expiresAt'];
    if (expiresAt is Timestamp && DateTime.now().isAfter(expiresAt.toDate())) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'window-closed',
        message: 'Upload window closed.',
      );
    }

    final folder = 'tournament_uploads/$cycleId/${user.uid}/battle$battleNumber';

    final downloadUrl = await CloudinaryService().uploadFile(
      file: file,
      folder: folder,
      resourceType: CloudinaryResourceType.Image,
    );

    await _firestore
        .collection('tournament_registrations')
        .doc(cycleId)
        .collection('participants')
        .doc(user.uid)
        .set({
      'battle$battleNumber.screenshotUrl': downloadUrl,
      'battle$battleNumber.kills': kills,
      'battle$battleNumber.rank': rank,
      'battle$battleNumber.submittedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await roomRef.set({
      'players.${user.uid}.screenshotUrl': downloadUrl,
      'players.${user.uid}.kills': kills,
      'players.${user.uid}.rank': rank,
      'players.${user.uid}.submittedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<TournamentJoinAction?> joinActionStream() async* {
    while (true) {
      yield await findJoinAction();
      await Future<void>.delayed(const Duration(seconds: 10));
    }
  }

  static Future<TournamentJoinAction?> findJoinAction() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final now = DateTime.now();

    final daily = _cycleInfo('daily', now);
    final weekly = _cycleInfo('weekly', now);
    final mega = _cycleInfo('mega', now);

    final candidateCycles = [
      if (daily['openJoin'] == true) daily,
      if (weekly['openJoin'] == true) weekly,
      if (mega['openJoin'] == true) mega,
    ];

    for (final cycle in candidateCycles) {
      final participant = await _firestore
          .collection('tournament_registrations')
          .doc(cycle['id'] as String)
          .collection('participants')
          .doc(user.uid)
          .get();
      if (participant.exists) {
        return TournamentJoinAction(
          title: cycle['title'] as String,
          cycleId: cycle['id'] as String,
          liveStart: cycle['liveStart'] as DateTime,
          battleCount: cycle['battleCount'] as int,
        );
      }
    }

    return null;
  }

  static Map<String, dynamic> _emptyBattleMap(int battleNumber) {
    return {
      'battleNumber': battleNumber,
      'matchId': null,
      'screenshotUrl': null,
      'submittedAt': null,
    };
  }

  static Future<bool> _tryJoinExistingBattleRoom({
    required String cycleId,
    required int battleNumber,
    required DocumentReference<Map<String, dynamic>> roomRef,
    required DocumentReference<Map<String, dynamic>> participantRef,
    required Map<String, dynamic> participantData,
    required String uid,
  }) async {
    try {
      await _firestore.runTransaction<void>((transaction) async {
        final roomSnap = await transaction.get(roomRef);
        final room = roomSnap.data();
        if (room == null || room['status'] != 'waiting') {
          throw StateError('Room unavailable');
        }
        final playerIds = List<String>.from(room['playerIds'] as List<dynamic>? ?? []);
        if (playerIds.contains(uid) || playerIds.length >= 2) {
          throw StateError('Room unavailable');
        }

        final freshParticipant = await transaction.get(participantRef);
        final freshData = freshParticipant.data() ?? participantData;
        final battleKey = 'battle$battleNumber';
        final freshBattle = Map<String, dynamic>.from(
          (freshData[battleKey] as Map<String, dynamic>?) ?? <String, dynamic>{},
        );
        final existingMatchId = (freshBattle['matchId'] as String?)?.trim() ?? '';
        if (existingMatchId.isNotEmpty) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'already-joined',
            message: 'You already joined this battle.',
          );
        }

        final now = DateTime.now();
        final expiresAt = now.add(battleDuration);
        final players = Map<String, dynamic>.from(
          (room['players'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        );
        players[uid] = _roomPlayerData(freshData, uid);

        transaction.set(roomRef, {
          'status': 'matched',
          'playerIds': [...playerIds, uid],
          'players': players,
          'startedAt': Timestamp.fromDate(now),
          'expiresAt': Timestamp.fromDate(expiresAt),
        }, SetOptions(merge: true));
        transaction.set(participantRef, {
          '$battleKey.matchId': roomRef.id,
        }, SetOptions(merge: true));
      });
      return true;
    } on StateError {
      return false;
    }
  }

  static Map<String, dynamic> _roomPlayerData(Map<String, dynamic> participantData, String uid) {
    return {
      'uid': uid,
      'name': (participantData['name'] as String?) ?? 'Player',
      'photo': (participantData['photo'] as String?) ?? '',
      'screenshotUrl': null,
      'submittedAt': null,
    };
  }

  static Map<String, dynamic> _cycleInfo(String type, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (type == 'daily') {
      return {
        'id': 'daily-${_formatDate(today)}',
        'title': 'Daily Battles',
        'liveStart': today,
        'battleCount': 1,
        'openJoin': true,
      };
    }
    if (type == 'weekly') {
      final isLiveDay = now.weekday == DateTime.sunday;
      final liveStart = today.add(Duration(days: (DateTime.sunday - now.weekday) % 7));
      final activeStart = isLiveDay ? today : liveStart;
      return {
        'id': 'weekly-${_formatDate(activeStart)}',
        'title': 'Weekly Tournament',
        'liveStart': activeStart,
        'battleCount': 3,
        'openJoin': isLiveDay,
      };
    }

    final isLiveDay = now.day == 1 || now.day == 15;
    final liveStart = now.day < 15
        ? DateTime(now.year, now.month, 15)
        : (isLiveDay ? today : DateTime(now.year, now.month + 1, 1));
    final activeStart = isLiveDay ? today : liveStart;
    return {
      'id': 'mega-${_formatDate(activeStart)}',
      'title': 'Mega Tournament',
      'liveStart': activeStart,
      'battleCount': 3,
      'openJoin': isLiveDay,
    };
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
