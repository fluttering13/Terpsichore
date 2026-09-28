enum SupportDistribution { googlePlay, direct }

enum SupportItem { badge, theme }

final class SupportConfig {
  const SupportConfig({
    this.distribution = SupportDistribution.googlePlay,
    this.productId = '',
    this.themeProductId = '',
    this.ecpayUrl = '',
    this.coffeeUrl = '',
    this.playEcpayAllowed = false,
    this.playCoffeeAllowed = false,
  });

  factory SupportConfig.fromEnvironment() => const SupportConfig(
    distribution: String.fromEnvironment('SUPPORT_DISTRIBUTION') == 'direct'
        ? SupportDistribution.direct
        : SupportDistribution.googlePlay,
    productId: String.fromEnvironment('SUPPORT_BADGE_PRODUCT_ID'),
    themeProductId: String.fromEnvironment('SUPPORT_THEME_PRODUCT_ID'),
    ecpayUrl: String.fromEnvironment('SUPPORT_ECPAY_URL'),
    coffeeUrl: String.fromEnvironment('SUPPORT_COFFEE_URL'),
    playEcpayAllowed: bool.fromEnvironment('SUPPORT_PLAY_ECPAY_ALLOWED'),
    playCoffeeAllowed: bool.fromEnvironment('SUPPORT_PLAY_COFFEE_ALLOWED'),
  );

  final SupportDistribution distribution;
  final String productId, themeProductId, ecpayUrl, coffeeUrl;
  String idFor(SupportItem item) =>
      item == SupportItem.badge ? productId : themeProductId;
  bool get validProducts =>
      productId.isEmpty ||
      themeProductId.isEmpty ||
      productId != themeProductId;
  final bool playEcpayAllowed, playCoffeeAllowed;
  bool get showPlay => distribution == SupportDistribution.googlePlay;
  bool get showEcpay => !showPlay || playEcpayAllowed;
  bool get showCoffee => !showPlay || playCoffeeAllowed;

  Uri? get ecpayUri => _paymentUri(ecpayUrl, 'ecpay.com.tw');
  Uri? get coffeeUri => _paymentUri(coffeeUrl, 'buymeacoffee.com');

  static Uri? _paymentUri(String value, String domain) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !(uri.host == domain || uri.host.endsWith('.$domain')) ||
        uri.path.isEmpty ||
        uri.path == '/') {
      return null;
    }
    return uri;
  }
}
