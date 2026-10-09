/// The device side of earning Shields: showing a rewarded ad and buying the Shield pack.
///
/// The app NEVER grants a Shield from here. A rewarded ad only reports what the ad SDK saw; the reward itself arrives
/// through Google's signed server-side verification (SSV) callback to the Flowstate server, and the app reads the result
/// back from the server. A purchase only hands the store's token to the server, which verifies it with Google Play.
///
/// Both default to "not available" until the native SDKs are wired (google_mobile_ads with an AdMob app id in
/// AndroidManifest.xml; in_app_purchase with the pack product in Play Console). Swap [ShieldEarning.ads] /
/// [ShieldEarning.store] at startup once they are.
library;

/// What the ad SDK reported. `earned` means the SDK's onUserEarnedReward fired — NOT that a Shield was granted.
enum RewardedAdOutcome { earned, dismissed, failed, unavailable }

abstract class RewardedAdGateway {
  bool get isAvailable;

  /// Load and show one rewarded ad. [ssvUserId] and [customData] MUST be set as the ad's server-side verification
  /// options, so Google's callback names this account and this ad session.
  Future<RewardedAdOutcome> show({required String adUnitId, required String ssvUserId, required String customData});
}

class UnconfiguredRewardedAds implements RewardedAdGateway {
  const UnconfiguredRewardedAds();

  @override
  bool get isAvailable => false;

  @override
  Future<RewardedAdOutcome> show({required String adUnitId, required String ssvUserId, required String customData}) async =>
      RewardedAdOutcome.unavailable;
}

/// A completed store purchase, before the server has verified it.
class StorePurchase {
  final String productId;
  final String purchaseToken;
  const StorePurchase({required this.productId, required this.purchaseToken});
}

enum StorePurchaseStatus { purchased, cancelled, pending, failed, unavailable }

class StorePurchaseResult {
  final StorePurchaseStatus status;
  final StorePurchase? purchase;
  const StorePurchaseResult(this.status, [this.purchase]);
}

abstract class ShieldPackStore {
  bool get isAvailable;

  /// Start the store purchase flow. [accountRef] MUST be passed as the obfuscated account id
  /// (Google Play: `applicationUserName` / obfuscatedAccountId): the server refuses a token bought by another account.
  Future<StorePurchaseResult> buy({required String productId, required String accountRef});
}

class UnconfiguredShieldPackStore implements ShieldPackStore {
  const UnconfiguredShieldPackStore();

  @override
  bool get isAvailable => false;

  @override
  Future<StorePurchaseResult> buy({required String productId, required String accountRef}) async =>
      const StorePurchaseResult(StorePurchaseStatus.unavailable);
}

class ShieldEarning {
  static RewardedAdGateway ads = const UnconfiguredRewardedAds();
  static ShieldPackStore store = const UnconfiguredShieldPackStore();
}
