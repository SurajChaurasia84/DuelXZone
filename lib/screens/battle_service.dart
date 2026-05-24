import 'dart:math';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import '../services/cloudinary_service.dart';

class BattleService {
  static const Duration roomDuration = Duration(minutes: 30);
  static final Random _random = Random();

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _battles =>
      _firestore.collection('battles');

  static CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  static DocumentReference<Map<String, dynamic>> get _userRef =>
      _users.doc(FirebaseAuth.instance.currentUser!.uid);

  static Future<String> createOrJoinBattle({required int entryFee}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'unauthenticated',
        message: 'Please sign in again.',
      );
    }

    final existingBattleId = await _findLiveBattleId(user.uid);
    if (existingBattleId != null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'active-room-exists',
        message: 'A room is already live. Exit that room before joining another.',
      );
    }

    final userSnap = await _userRef.get();
    final userData = userSnap.data() ?? <String, dynamic>{};
    final displayName = ((userData['username'] as String?)?.trim().isNotEmpty == true)
        ? (userData['username'] as String).trim()
        : (user.displayName ?? 'Player');
    final photo = (userData['photo'] as String?) ?? user.photoURL ?? '';
    final waitingQuery = await _battles
        .where('status', isEqualTo: 'waiting')
        .where('entryFee', isEqualTo: entryFee)
        .limit(10)
        .get();
    final waitingDocs = waitingQuery.docs.where((doc) {
      final data = doc.data();
      if ((data['createdBy'] as String?) == user.uid) return false;
      final createdAtRaw = data['createdAt'];
      if (createdAtRaw == null) return false;
      final createdAt = createdAtRaw is Timestamp
          ? createdAtRaw.toDate()
          : (createdAtRaw as DateTime);
      final difference = DateTime.now().difference(createdAt).inSeconds.abs();
      return difference <= 45;
    }).toList()
      ..shuffle(_random);

    for (final doc in waitingDocs) {
      final matched = await _tryJoinWaitingBattle(
        battleRef: doc.reference,
        uid: user.uid,
        displayName: displayName,
        photo: photo,
        entryFee: entryFee,
      );
      if (matched) {
        return doc.id;
      }
    }

    final battleRef = _battles.doc();
    await _firestore.runTransaction<void>((transaction) async {
      final now = DateTime.now();
      final playerData = _playerData(
        uid: user.uid,
        name: displayName,
        photo: photo,
        joinedAt: now,
      );

      transaction.set(battleRef, {
        'createdBy': user.uid,
        'entryFee': entryFee,
        'status': 'waiting',
        'createdAt': Timestamp.fromDate(now),
        'startedAt': null,
        'expiresAt': null,
        'startPlayerIds': <String>[].toList(),
        'entryDeducted': false,
        'playerIds': [user.uid],
        'players': {user.uid: playerData},
        'winnerId': null,
        'resultText': 'Waiting for opponent',
        'approvedByAdmin': false,
        'winnerCandidateId': null,
        'dismissedBy': <String>[].toList(),
      });
    });

    return battleRef.id;
  }

  static Future<String?> findLiveBattleId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return _findLiveBattleId(user.uid);
  }

  static Future<String?> _findLiveBattleId(String uid) async {
    final snapshot = await _battles
        .where('playerIds', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String? ?? 'waiting';
      final dismissedBy = List<String>.from(data['dismissedBy'] as List<dynamic>? ?? []);
      final isLive = status == 'waiting' || status == 'matched' || status == 'ongoing';
      if (isLive && !dismissedBy.contains(uid)) {
        return doc.id;
      }
    }

    return null;
  }

  static Future<bool> _tryJoinWaitingBattle({
    required DocumentReference<Map<String, dynamic>> battleRef,
    required String uid,
    required String displayName,
    required String photo,
    required int entryFee,
  }) async {
    try {
      await _firestore.runTransaction<void>((transaction) async {
        final battleSnap = await transaction.get(battleRef);
        final battle = battleSnap.data();
        if (battle == null || battle['status'] != 'waiting') {
          throw StateError('Battle no longer available');
        }

        final playerIds = List<String>.from(battle['playerIds'] as List<dynamic>);
        if (playerIds.contains(uid) || playerIds.length >= 2) {
          throw StateError('Battle unavailable');
        }

        final now = DateTime.now();
        final players = Map<String, dynamic>.from(
          (battle['players'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        );
        players[uid] = _playerData(
          uid: uid,
          name: displayName,
          photo: photo,
          joinedAt: now,
        );

        transaction.set(battleRef, {
          'status': 'matched',
          'playerIds': [...playerIds, uid],
          'players': players,
          'resultText': 'Opponent assigned. Both players press start.',
        }, SetOptions(merge: true));
      });
      return true;
    } on StateError {
      return false;
    }
  }

  static Map<String, dynamic> _playerData({
    required String uid,
    required String name,
    required String photo,
    required DateTime joinedAt,
  }) {
    return {
      'uid': uid,
      'name': name,
      'photo': photo,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'entryPaid': false,
      'screenshotUrl': null,
      'submittedAt': null,
    };
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> battleStream(String battleId) {
    return _battles.doc(battleId).snapshots();
  }

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> myBattlesStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.empty();
    }

    return _battles
        .where('playerIds', arrayContains: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  static Future<void> startBattle(String battleId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'unauthenticated',
        message: 'Please sign in again.',
      );
    }

    final battleRef = _battles.doc(battleId);
    await _firestore.runTransaction<void>((transaction) async {
      final battleSnap = await transaction.get(battleRef);
      final battle = battleSnap.data();
      if (battle == null) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'Battle room not found.',
        );
      }

      final status = battle['status'] as String? ?? 'waiting';
      if (status == 'ongoing' || status == 'completed' || status == 'review') {
        return;
      }

      final playerIds = List<String>.from(battle['playerIds'] as List<dynamic>? ?? []);
      if (!playerIds.contains(user.uid) || playerIds.length < 2) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message: 'Opponent not joined yet.',
        );
      }

      final started = List<String>.from(battle['startPlayerIds'] as List<dynamic>? ?? []);
      if (!started.contains(user.uid)) {
        started.add(user.uid);
      }

      final entryFee = (battle['entryFee'] as num?)?.toInt() ?? 0;
      final players = Map<String, dynamic>.from(
        (battle['players'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      );
      final currentPlayer = Map<String, dynamic>.from(
        (players[user.uid] as Map<String, dynamic>?) ?? <String, dynamic>{},
      );
      final alreadyPaid = currentPlayer['entryPaid'] == true;
      final userRef = _users.doc(user.uid);
      final userSnap = await transaction.get(userRef);
      final userData = userSnap.data() ?? <String, dynamic>{};
      final currentCoins = (userData['coins'] as num?)?.toInt() ?? 0;
      final startedAt = Timestamp.fromDate(DateTime.now());

      if (entryFee > 0 && !alreadyPaid && currentCoins < entryFee) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'insufficient-coins',
          message: 'Not enough coins for this battle.',
        );
      }

      currentPlayer['entryPaid'] = true;
      currentPlayer['startedAt'] = startedAt;
      players[user.uid] = currentPlayer;

      if (entryFee > 0 && !alreadyPaid) {
        transaction.set(userRef, {
          'coins': currentCoins - entryFee,
        }, SetOptions(merge: true));
        final historyRef = userRef.collection('coin_history').doc();
        transaction.set(historyRef, {
          'amount': -entryFee,
          'title': 'Battle entry fee',
          'type': 'battle_entry',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final allStarted = started.length == playerIds.length;
      final allPaid = playerIds.every((id) {
        final player = Map<String, dynamic>.from(
          (players[id] as Map<String, dynamic>?) ?? <String, dynamic>{},
        );
        return player['entryPaid'] == true;
      });

      if (allStarted && allPaid) {
        final now = DateTime.now();
        final expiresAt = now.add(roomDuration);
        transaction.set(battleRef, {
          'status': 'ongoing',
          'startedAt': Timestamp.fromDate(now),
          'expiresAt': Timestamp.fromDate(expiresAt),
          'entryDeducted': true,
          'resultText': 'Battle started. Submit proof within 30 minutes.',
        }, SetOptions(merge: true));
      } else {
        transaction.set(battleRef, {
          'status': 'matched',
          'startPlayerIds': started,
          'players': players,
          'resultText': started.length == 1
              ? 'One player is ready and entry paid. Waiting for opponent to start.'
              : 'Opponent assigned. Both players press start.',
        }, SetOptions(merge: true));
      }
    });
  }

  static Future<void> dismissBattle(String battleId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _battles.doc(battleId).set({
      'dismissedBy': FieldValue.arrayUnion([user.uid]),
    }, SetOptions(merge: true));
  }

  static Future<void> cancelWaitingBattle(String battleId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'unauthenticated',
        message: 'Please sign in again.',
      );
    }

    final battleRef = _battles.doc(battleId);
    await _firestore.runTransaction<void>((transaction) async {
      final battleSnap = await transaction.get(battleRef);
      final battle = battleSnap.data();
      if (battle == null) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'Battle room not found.',
        );
      }

      final status = battle['status'] as String? ?? 'waiting';
      final createdBy = battle['createdBy'] as String? ?? '';
      final playerIds = List<String>.from(battle['playerIds'] as List<dynamic>? ?? []);

      if (status != 'waiting' || createdBy != user.uid || playerIds.length > 1) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message: 'This room can no longer be cancelled.',
        );
      }

      transaction.delete(battleRef);
    });
  }

  static Future<void> leaveBattle(String battleId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'unauthenticated',
        message: 'Please sign in again.',
      );
    }

    final battleRef = _battles.doc(battleId);
    final userRef = _users.doc(user.uid);

    await _firestore.runTransaction<void>((transaction) async {
      final battleSnap = await transaction.get(battleRef);
      final battle = battleSnap.data();
      if (battle == null) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'Battle room not found.',
        );
      }

      final status = battle['status'] as String? ?? 'waiting';
      if (status != 'waiting' && status != 'matched') {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message: 'This room cannot be exited right now.',
        );
      }

      final playerIds = List<String>.from(battle['playerIds'] as List<dynamic>? ?? []);
      if (!playerIds.contains(user.uid)) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message: 'You are not part of this room.',
        );
      }

      final players = Map<String, dynamic>.from(
        (battle['players'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      );
      final currentPlayer = Map<String, dynamic>.from(
        (players[user.uid] as Map<String, dynamic>?) ?? <String, dynamic>{},
      );
      final entryFee = (battle['entryFee'] as num?)?.toInt() ?? 0;
      final hadPaid = currentPlayer['entryPaid'] == true;

      if (entryFee > 0 && hadPaid) {
        final userSnap = await transaction.get(userRef);
        final userData = userSnap.data() ?? <String, dynamic>{};
        final currentCoins = (userData['coins'] as num?)?.toInt() ?? 0;
        transaction.set(userRef, {
          'coins': currentCoins + entryFee,
        }, SetOptions(merge: true));
        final historyRef = userRef.collection('coin_history').doc();
        transaction.set(historyRef, {
          'amount': entryFee,
          'title': 'Battle exit refund',
          'type': 'battle_refund',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      players.remove(user.uid);
      final remainingPlayerIds = playerIds.where((id) => id != user.uid).toList();

      if (remainingPlayerIds.isEmpty) {
        transaction.delete(battleRef);
        return;
      }

      transaction.set(battleRef, {
        'createdBy': remainingPlayerIds.first,
        'status': 'waiting',
        'playerIds': remainingPlayerIds,
        'players': players,
        'startPlayerIds': <String>[],
        'startedAt': null,
        'expiresAt': null,
        'entryDeducted': false,
        'resultText': 'Waiting for opponent',
      }, SetOptions(merge: true));
    });
  }

  static Future<void> uploadBattleProof({
    required String battleId,
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

    final folder = 'battle_uploads/$battleId/${user.uid}';

    final downloadUrl = await CloudinaryService().uploadFile(
      file: file,
      folder: folder,
      resourceType: CloudinaryResourceType.Image,
    );
    final battleRef = _battles.doc(battleId);

    await battleRef.set({
      'players': {
        user.uid: {
          'screenshotUrl': downloadUrl,
          'kills': kills,
          'rank': rank,
          'submittedAt': FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));

    await resolveBattleIfPossible(battleId);
  }

  static Future<void> resolveBattleIfPossible(String battleId) async {
    final battleRef = _battles.doc(battleId);

    await _firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(battleRef);
      final battle = snapshot.data();
      if (battle == null) return;

      final status = battle['status'] as String? ?? 'waiting';
      if (status == 'completed' || status == 'review' || status == 'pending_admin') return;

      final expiresAt = (battle['expiresAt'] as Timestamp?)?.toDate();
      final now = DateTime.now();
      final playerIds = List<String>.from(battle['playerIds'] as List<dynamic>? ?? []);
      final players = Map<String, dynamic>.from(
          (battle['players'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      );
      final completePlayers = <String>[];

      for (final id in playerIds) {
        final player = Map<String, dynamic>.from(
          (players[id] as Map<String, dynamic>?) ?? <String, dynamic>{},
        );
        final hasScreenshot = (player['screenshotUrl'] as String?)?.isNotEmpty == true;
        if (hasScreenshot) {
          completePlayers.add(id);
        }
      }

      if (completePlayers.length == 2) {
        transaction.set(battleRef, {
          'status': 'review',
          'winnerId': null,
          'winnerCandidateId': null,
          'approvedByAdmin': false,
          'resultText': 'Both players submitted proof. Waiting for admin approval.',
        }, SetOptions(merge: true));
        return;
      }

      final isExpired = expiresAt != null && !now.isBefore(expiresAt);
      if (!isExpired) return;

      if (completePlayers.length == 1) {
        transaction.set(battleRef, {
          'status': 'pending_admin',
          'winnerId': null,
          'winnerCandidateId': completePlayers.first,
          'approvedByAdmin': false,
          'resultText': 'Proof submitted by one player. Waiting for admin approval.',
        }, SetOptions(merge: true));
        return;
      }

      transaction.set(battleRef, {
        'status': 'completed',
        'winnerId': null,
        'winnerCandidateId': null,
        'approvedByAdmin': true,
        'resultText': 'No valid proof submitted in time. Both players lose.',
      }, SetOptions(merge: true));
    });
  }
}
