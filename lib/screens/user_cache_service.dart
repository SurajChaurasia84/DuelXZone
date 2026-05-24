import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserCacheService {
  static const _nameKey = 'user_name';
  static const _emailKey = 'user_email';
  static const _photoKey = 'user_photo';
  static const _usernameKey = 'user_username';
  static const _gameKey = 'user_game';
  static const _gameIdKey = 'user_game_id';
  static const _gameLevelKey = 'user_game_level';
  static const _lastOpenRewardAtKey = 'user_last_open_reward_at';
  static const _lastAdRewardAtKey = 'user_last_ad_reward_at';
  static const _lastCheckInAtKey = 'user_last_check_in_at';

  static Future<Map<String, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString(_nameKey) ?? '',
      'email': prefs.getString(_emailKey) ?? '',
      'photo': prefs.getString(_photoKey) ?? '',
      'username': prefs.getString(_usernameKey) ?? '',
      'game': prefs.getString(_gameKey) ?? '',
      'gameId': prefs.getString(_gameIdKey) ?? '',
      'gameLevel': prefs.getString(_gameLevelKey) ?? '',
      'lastOpenRewardAt': prefs.getString(_lastOpenRewardAtKey) ?? '',
      'lastAdRewardAt': prefs.getString(_lastAdRewardAtKey) ?? '',
      'lastCheckInAt': prefs.getString(_lastCheckInAtKey) ?? '',
    };
  }

  static Future<void> save(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, (data['name'] as String?) ?? '');
    await prefs.setString(_emailKey, (data['email'] as String?) ?? '');
    await prefs.setString(_photoKey, (data['photo'] as String?) ?? '');
    await prefs.setString(_usernameKey, (data['username'] as String?) ?? '');
    await prefs.setString(_gameKey, (data['game'] as String?) ?? '');
    await prefs.setString(_gameIdKey, (data['gameId'] as String?) ?? '');
    if (data.containsKey('gameLevel')) {
      await prefs.setString(_gameLevelKey, data['gameLevel'].toString());
    }

    if (data.containsKey('lastOpenRewardAt')) {
      final val = data['lastOpenRewardAt'];
      if (val is Timestamp) {
        await prefs.setString(_lastOpenRewardAtKey, val.toDate().toIso8601String());
      } else if (val is String) {
        await prefs.setString(_lastOpenRewardAtKey, val);
      }
    }
    if (data.containsKey('lastAdRewardAt')) {
      final val = data['lastAdRewardAt'];
      if (val is Timestamp) {
        await prefs.setString(_lastAdRewardAtKey, val.toDate().toIso8601String());
      } else if (val is String) {
        await prefs.setString(_lastAdRewardAtKey, val);
      }
    }
    if (data.containsKey('lastCheckInAt')) {
      final val = data['lastCheckInAt'];
      if (val is Timestamp) {
        await prefs.setString(_lastCheckInAtKey, val.toDate().toIso8601String());
      } else if (val is String) {
        await prefs.setString(_lastCheckInAtKey, val);
      }
    }
  }

  static Future<void> saveSingle(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == 'lastOpenRewardAt') {
      await prefs.setString(_lastOpenRewardAtKey, value);
    } else if (key == 'lastAdRewardAt') {
      await prefs.setString(_lastAdRewardAtKey, value);
    } else if (key == 'lastCheckInAt') {
      await prefs.setString(_lastCheckInAtKey, value);
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_photoKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_gameKey);
    await prefs.remove(_gameIdKey);
    await prefs.remove(_gameLevelKey);
    await prefs.remove(_lastOpenRewardAtKey);
    await prefs.remove(_lastAdRewardAtKey);
    await prefs.remove(_lastCheckInAtKey);
  }
}
