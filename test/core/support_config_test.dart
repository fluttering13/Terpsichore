import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/support/support_config.dart';

void main() {
  test(
    'Play defaults hide both external payment routes independently of URLs',
    () {
      const config = SupportConfig(
        ecpayUrl: 'https://p.ecpay.com.tw/123',
        coffeeUrl: 'https://buymeacoffee.com/creator',
      );
      expect(config.showPlay, isTrue);
      expect(config.showEcpay, isFalse);
      expect(config.showCoffee, isFalse);
      expect(const SupportConfig(playEcpayAllowed: true).showEcpay, isTrue);
      expect(const SupportConfig(playEcpayAllowed: true).showCoffee, isFalse);
    },
  );

  test(
    'direct distribution enables external routes without claiming Play support',
    () {
      const config = SupportConfig(distribution: SupportDistribution.direct);
      expect(config.showPlay, isFalse);
      expect(config.showEcpay, isTrue);
      expect(config.showCoffee, isTrue);
      expect(config.ecpayUri, isNull);
      expect(config.coffeeUri, isNull);
    },
  );

  test('only HTTPS payment links on the expected hosts are accepted', () {
    for (final url in [
      '',
      'http://p.ecpay.com.tw/123',
      'https://p.ecpay.com.tw.evil.test/123',
      'https://user@p.ecpay.com.tw/123',
      'https://p.ecpay.com.tw:444/123',
      'https://p.ecpay.com.tw/',
    ]) {
      expect(SupportConfig(ecpayUrl: url).ecpayUri, isNull, reason: url);
    }
    expect(
      const SupportConfig(
        ecpayUrl: 'https://payment.ecpay.com.tw/Broadcaster/Donate/abc',
      ).ecpayUri,
      isNotNull,
    );
    expect(
      const SupportConfig(
        coffeeUrl: 'https://buymeacoffee.com/creator',
      ).coffeeUri,
      isNotNull,
    );
    expect(
      const SupportConfig(
        coffeeUrl: 'https://notbuymeacoffee.com/creator',
      ).coffeeUri,
      isNull,
    );
  });
}
