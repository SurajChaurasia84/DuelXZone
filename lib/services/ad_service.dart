import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  // Unity Ads Android Game ID from your dashboard
  static const String _gameIdAndroid = '800001255';

  // Placement IDs configured on your dashboard
  static const String rewardedPlacementId = 'Rewarded_Android';
  static const String interstitialPlacementId = 'Interstitial_Android';
  static const String bannerPlacementId = 'Banner_Android';

  bool _initialized = false;
  final Set<String> _readyPlacements = {};
  final Set<String> _loadingPlacements = {};
  final Map<String, List<Completer<bool>>> _loadCompleters = {};

  static String get gameId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _gameIdAndroid;
    }
    return '';
  }

  /// Initializes Unity Ads SDK
  Future<void> init() async {
    if (_initialized) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      // NOTE: testMode is set to false to serve real production ads.
      await UnityAds.init(
        gameId: gameId,
        testMode: false, 
        onComplete: () {
          _initialized = true;
          // Preload ads upon initialization
          loadAd(rewardedPlacementId);
          loadAd(interstitialPlacementId);
        },
        onFailed: (error, message) {
          // Initialization failure handled gracefully
        },
      );
    } catch (e) {
      // Exception ignored to avoid app startup crashes
    }
  }

  /// Whether the SDK has finished initialization
  bool get isInitialized => _initialized;

  /// Check if a specific ad placement is ready to be shown
  bool isAdReady(String placementId) => _readyPlacements.contains(placementId);

  /// Loads an ad placement in the background
  void loadAd(String placementId) {
    if (!_initialized) return;
    if (_loadingPlacements.contains(placementId)) return;
    _loadingPlacements.add(placementId);

    UnityAds.load(
      placementId: placementId,
      onComplete: (pId) {
        _loadingPlacements.remove(pId);
        _readyPlacements.add(pId);
        
        final completers = _loadCompleters[pId];
        if (completers != null) {
          for (final completer in completers) {
            if (!completer.isCompleted) completer.complete(true);
          }
          _loadCompleters[pId] = [];
        }
      },
      onFailed: (pId, error, message) {
        _loadingPlacements.remove(pId);
        _readyPlacements.remove(pId);
        
        final completers = _loadCompleters[pId];
        if (completers != null) {
          for (final completer in completers) {
            if (!completer.isCompleted) completer.complete(false);
          }
          _loadCompleters[pId] = [];
        }
      },
    );
  }

  /// Loads an ad and returns a Future that completes when loading finishes
  Future<bool> loadAdAsync(String placementId) async {
    if (!_initialized) {
      await init();
      if (!_initialized) return false;
    }
    if (isAdReady(placementId)) return true;

    final completer = Completer<bool>();
    _loadCompleters.putIfAbsent(placementId, () => []).add(completer);
    
    loadAd(placementId);
    
    // Add a timeout of 15 seconds to avoid hanging indefinitely
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _loadCompleters[placementId]?.remove(completer);
        return false;
      },
    );
  }

  /// Shows Rewarded Ad video and triggers callback upon completion
  void showRewardedAd({
    required VoidCallback onComplete,
    required VoidCallback onFailed,
  }) {
    if (!_initialized) {
      onFailed();
      return;
    }
    _readyPlacements.remove(rewardedPlacementId);
    UnityAds.showVideoAd(
      placementId: rewardedPlacementId,
      onStart: (placementId) {},
      onClick: (placementId) {},
      onSkipped: (placementId) {
        onFailed();
        loadAd(rewardedPlacementId); // Preload next ad
      },
      onComplete: (placementId) {
        onComplete();
        loadAd(rewardedPlacementId); // Preload next ad
      },
      onFailed: (placementId, error, message) {
        onFailed();
        loadAd(rewardedPlacementId); // Preload next ad
      },
    );
  }

  /// Shows Interstitial Ad video
  void showInterstitialAd({
    VoidCallback? onComplete,
    VoidCallback? onFailed,
  }) {
    if (!_initialized) {
      onFailed?.call();
      return;
    }
    _readyPlacements.remove(interstitialPlacementId);
    UnityAds.showVideoAd(
      placementId: interstitialPlacementId,
      onStart: (placementId) {},
      onClick: (placementId) {},
      onSkipped: (placementId) {
        onComplete?.call(); // Interstitial skipped is still finished
        loadAd(interstitialPlacementId); // Preload next ad
      },
      onComplete: (placementId) {
        onComplete?.call();
        loadAd(interstitialPlacementId); // Preload next ad
      },
      onFailed: (placementId, error, message) {
        onFailed?.call();
        loadAd(interstitialPlacementId); // Preload next ad
      },
    );
  }
}

