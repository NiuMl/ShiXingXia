import 'dart:async';
import 'package:flutter/material.dart';
import '../services/app_blocker_service.dart';
import '../services/app_cache_service.dart';

class AppBlockerSettingsScreen extends StatefulWidget {
  const AppBlockerSettingsScreen({super.key});

  @override
  State<AppBlockerSettingsScreen> createState() => _AppBlockerSettingsScreenState();
}

class _AppBlockerSettingsScreenState extends State<AppBlockerSettingsScreen> {
  final AppCacheService _cache = AppCacheService();
  final TextEditingController _searchController = TextEditingController();

  List<AppInfo> _displayedApps = [];
  Set<String> _blockedPackages = {};
  bool _isLoading = true;
  bool _isSearching = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text;

    // Debounce search to avoid triggering on every keystroke
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      // Clear search - show social media apps again
      setState(() {
        _displayedApps = _cache.getSocialMediaApps();
      });
    } else if (query.length >= 2) {
      // Only search if 2+ characters
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        _searchApps(query);
      });
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    // Get data from cache (instant if preloaded!)
    _blockedPackages = _cache.getBlockedPackages();
    _displayedApps = _cache.getSocialMediaApps();

    // If cache is empty (shouldn't happen with splash), load now
    if (_displayedApps.isEmpty) {
      debugPrint('⚠️ Cache empty, loading social media apps...');
      await _cache.preloadSocialMediaApps();
      _displayedApps = _cache.getSocialMediaApps();
      _blockedPackages = _cache.getBlockedPackages();
    }

    setState(() => _isLoading = false);

    // Start preloading all apps in background if not done
    if (!_cache.isAllAppsLoaded.value) {
      _cache.preloadAllApps();
    }
  }

  Future<void> _searchApps(String query) async {
    setState(() => _isSearching = true);

    // Search in cache (instant if preloaded!)
    final results = await _cache.searchApps(query);

    setState(() {
      _displayedApps = results;
      _isSearching = false;
    });
  }

  Future<void> _toggleAppBlocked(String packageName, bool isBlocked) async {
    setState(() {
      if (isBlocked) {
        _blockedPackages.add(packageName);
      } else {
        _blockedPackages.remove(packageName);
      }
    });

    // Update cache and persist
    await _cache.updateBlockedPackages(_blockedPackages);
  }

  String _getShortAppName(String fullName) {
    // Remove common suffixes and keep it short
    return fullName
        .replaceAll(RegExp(r'\s+(App|Pro|Plus|Lite|Free)$', caseSensitive: false), '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Block Apps'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search more apps...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats header
                if (_blockedPackages.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.block, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          '${_blockedPackages.length} ${_blockedPackages.length == 1 ? 'app' : 'apps'} blocked',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Section header
                if (_searchController.text.isEmpty && _displayedApps.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Row(
                      children: [
                        Icon(Icons.smartphone, color: Colors.purple.withValues(alpha: 0.8), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Popular Social Apps',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[400],
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Content area
                Expanded(
                  child: _buildContent(),
                ),
              ],
            ),
    );
  }

  Widget _buildContent() {
    if (_isSearching) {
      // Loading search results
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_displayedApps.isEmpty) {
      // No apps found
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchController.text.isEmpty ? Icons.apps_outlined : Icons.search_off,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No social media apps found'
                  : 'No apps match your search',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isEmpty
                  ? 'Try searching for other apps above'
                  : 'Try a different search term',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );
    }

    // Show app list
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: _displayedApps.length,
      itemBuilder: (context, index) {
        final app = _displayedApps[index];
        final isBlocked = _blockedPackages.contains(app.packageName);
        final shortName = _getShortAppName(app.appName);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isBlocked
                  ? Colors.redAccent.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: CheckboxListTile(
            value: isBlocked,
            onChanged: (value) {
              _toggleAppBlocked(app.packageName, value ?? false);
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            secondary: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.withValues(alpha: 0.1),
              ),
              child: app.iconBytes != null && app.iconBytes!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        app.iconBytes!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.apps, size: 32);
                        },
                      ),
                    )
                  : const Icon(Icons.apps, size: 32),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    shortName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isBlocked ? Colors.redAccent : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (app.isSocialMedia) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'SOCIAL',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: shortName != app.appName
                ? Text(
                    app.appName,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
          ),
        );
      },
    );
  }
}
