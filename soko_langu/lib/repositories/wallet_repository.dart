import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/wallet_model.dart';
import '../services/wallet_api.dart';
import '../services/local_cache_service.dart';

/// WalletRepository abstracts the financial data source for sellers.
/// 
/// It follows the Cache-Aside pattern:
/// 1. Return cached balance immediately for instant UI feedback.
/// 2. Fetch authoritative balance from V3 API in the background.
/// 3. Update cache and notify listeners of the authoritative truth.
class WalletRepository {
  final WalletApiClient _apiClient;
  final LocalCacheService _cache;

  WalletRepository({
    required WalletApiClient apiClient,
    required LocalCacheService cache,
  }) : _apiClient = apiClient,
       _cache = cache;

  /// Fetches the current wallet details.
  /// Returns a Stream to allow the UI to show cached data then fresh data.
  Stream<WalletDetail> watchWallet() async* {
    // 1. Emit cached data first for instant load
    final cached = await _cache.getCachedWallet();
    if (cached != null) {
      yield cached;
    }

    try {
      // 2. Fetch authoritative data from V3 API
      final fresh = await _apiClient.fetchWallet();
      
      // 3. Update local cache
      await _cache.saveWallet(fresh);
      
      yield fresh;
    } catch (e) {
      if (cached == null) rethrow;
      // Silently fail if we have a cache to fall back on
    }
  }

  /// Requests a withdrawal from the V3 Postgres Wallet.
  /// This is an authoritative mutation that bypasses local cache.
  Future<WithdrawalData> requestWithdrawal({
    required int amount,
    String? phoneNumber,
  }) async {
    final result = await _apiClient.requestWithdrawal(
      amount: amount,
      phoneNumber: phoneNumber,
    );
    
    // Invalidate wallet cache as balance has changed
    await _cache.invalidateWallet();
    
    return result;
  }

  /// Fetches withdrawal history.
  Future<List<WithdrawalData>> fetchWithdrawalHistory() async {
    return await _apiClient.fetchWithdrawals();
  }
}
