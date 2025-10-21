import 'package:flutter/foundation.dart';
import 'app_blocker_service.dart';

/// Singleton service for caching app data across the entire app lifecycle
/// Loads heavy resources once during app startup for instant access later
class AppCacheService {
  static final AppCacheService _instance = AppCacheService._internal();
  factory AppCacheService() => _instance;
  AppCacheService._internal();

  final AppBlockerService _appBlockerService = AppBlockerService();

  // Cached data
  List<AppInfo>? _allApps;
  List<AppInfo>? _socialMediaApps;
  Set<String>? _blockedPackages;

  // Loading states
  bool _isLoadingSocialMedia = false;
  bool _isLoadingAllApps = false;
  bool _hasLoadedSocialMedia = false;
  bool _hasLoadedAllApps = false;

  // Notifiers for UI updates
  final ValueNotifier<bool> isSocialMediaLoaded = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isAllAppsLoaded = ValueNotifier<bool>(false);

  /// Preload social media apps (fast, for initial screen)
  Future<void> preloadSocialMediaApps() async {
    if (_isLoadingSocialMedia || _hasLoadedSocialMedia) return;

    _isLoadingSocialMedia = true;
    debugPrint('🔄 Preloading social media apps...');

    try {
      final results = await Future.wait([
        _appBlockerService.getSavedBlockedApps(),
        _appBlockerService.getSocialMediaApps(),
      ]);

      _blockedPackages = (results[0] as List<String>).toSet();
      _socialMediaApps = results[1] as List<AppInfo>;
      _hasLoadedSocialMedia = true;
      isSocialMediaLoaded.value = true;

      debugPrint('✅ Preloaded ${_socialMediaApps!.length} social media apps');
    } catch (e) {
      debugPrint('❌ Error preloading social media apps: $e');
    } finally {
      _isLoadingSocialMedia = false;
    }
  }

  /// Preload all apps in background (for search functionality)
  Future<void> preloadAllApps() async {
    if (_isLoadingAllApps || _hasLoadedAllApps) return;

    _isLoadingAllApps = true;
    debugPrint('🔄 Preloading all apps in background...');

    try {
      // Load all apps (without compute isolate due to MethodChannel limitations)
      _allApps = await _appBlockerService.getInstalledApps();
      _hasLoadedAllApps = true;
      isAllAppsLoaded.value = true;

      debugPrint('✅ Preloaded ${_allApps!.length} apps in background');
    } catch (e) {
      debugPrint('❌ Error preloading all apps: $e');
    } finally {
      _isLoadingAllApps = false;
    }
  }

  /// Get social media apps (instant if preloaded)
  List<AppInfo> getSocialMediaApps() {
    if (!_hasLoadedSocialMedia) {
      debugPrint('⚠️ Social media apps not preloaded yet');
      return [];
    }
    return _socialMediaApps!;
  }

  /// Get all apps (instant if preloaded)
  List<AppInfo> getAllApps() {
    if (!_hasLoadedAllApps) {
      debugPrint('⚠️ All apps not preloaded yet');
      return [];
    }
    return _allApps!;
  }

  /// Get blocked packages
  Set<String> getBlockedPackages() {
    return _blockedPackages ?? {};
  }

  /// Search apps (uses native search for speed)
  Future<List<AppInfo>> searchApps(String query) async {
    // Use native Android search for best performance
    debugPrint('🔍 Searching for: $query');
    try {
      final results = await _appBlockerService.searchApps(query);
      debugPrint('✅ Found ${results.length} results');
      return results;
    } catch (e) {
      debugPrint('❌ Error searching apps: $e');
      return [];
    }
  }

  /// Update blocked packages
  Future<void> updateBlockedPackages(Set<String> packages) async {
    _blockedPackages = packages;
    await _appBlockerService.setBlockedApps(packages.toList());

    // Auto-enable blocking
    if (packages.isNotEmpty) {
      await _appBlockerService.setBlockingEnabled(true);
    }
  }

  /// Refresh blocked packages from storage
  Future<void> refreshBlockedPackages() async {
    final packages = await _appBlockerService.getSavedBlockedApps();
    _blockedPackages = packages.toSet();
  }

  /// Clear all cached data (for memory management)
  void clearCache() {
    _allApps = null;
    _socialMediaApps = null;
    _hasLoadedAllApps = false;
    _hasLoadedSocialMedia = false;
    isAllAppsLoaded.value = false;
    isSocialMediaLoaded.value = false;
    debugPrint('🗑️ Cleared app cache');
  }

  /// Dispose notifiers
  void dispose() {
    isSocialMediaLoaded.dispose();
    isAllAppsLoaded.dispose();
  }
}
