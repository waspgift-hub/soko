import '../models/wallet_model.dart';
import '../services/wallet_api.dart';

/// Server-authoritative seller wallet repository.
class WalletRepository {
  final WalletApiClient _apiClient;

  WalletRepository({WalletApiClient? apiClient})
      : _apiClient = apiClient ?? WalletApiClient();

  Stream<WalletDetail> watchWallet() async* {
    yield await _apiClient.fetchWallet();
  }

  Future<WithdrawalData> requestWithdrawal({
    required int amount,
    String? phoneNumber,
  }) => _apiClient.requestWithdrawal(amount: amount, phoneNumber: phoneNumber);

  Future<List<WithdrawalData>> fetchWithdrawalHistory() =>
      _apiClient.fetchWithdrawals();
}
