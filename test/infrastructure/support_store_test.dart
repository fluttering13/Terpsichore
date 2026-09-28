import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:terpsichore/core/support/support_config.dart';
import 'package:terpsichore/infrastructure/support/support_store.dart';

class FakeBilling implements InAppPurchase {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <String>[];
  final bought = <String>[];
  Set<String>? queried;
  int restores = 0;
  bool acknowledgeFails = false;
  bool available = true;
  bool buyAccepted = true;
  bool buyFails = false;
  bool queryFails = false;
  int queries = 0;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queried = ids;
    queries++;
    if (queryFails) throw StateError('offline');
    return ProductDetailsResponse(
      productDetails: [
        for (final id in ids)
          ProductDetails(
            id: id,
            title: id,
            description: id,
            price: id == 'badge' ? 'NT\$90.00' : 'NT\$150.00',
            rawPrice: id == 'badge' ? 90 : 150,
            currencyCode: 'TWD',
          ),
      ],
      notFoundIDs: [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    bought.add(purchaseParam.productDetails.id);
    if (buyFails) throw StateError('billing disconnected');
    return buyAccepted;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restores++;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (acknowledgeFails) throw StateError('offline');
    completed.add(purchase.productID);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeBilling billing;
  late PlaySupportStore store;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    billing = FakeBilling();
    store = PlaySupportStore(
      const SupportConfig(productId: 'badge', themeProductId: 'theme'),
      billing: billing,
    );
  });
  tearDown(() async {
    store.dispose();
    await billing.events.close();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> emit(
    String id,
    PurchaseStatus status, {
    bool complete = false,
  }) async {
    final purchase = PurchaseDetails(
      productID: id,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'google_play',
      ),
      transactionDate: '1',
      status: status,
    )..pendingCompletePurchase = complete;
    billing.events.add([purchase]);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'independent prices and product IDs come from Play; initialize once',
    () async {
      await store.initialize();
      await store.initialize();
      expect(billing.queried, {'badge', 'theme'});
      expect(store.priceFor(SupportItem.badge), 'NT\$90.00');
      expect(store.priceFor(SupportItem.theme), 'NT\$150.00');
      expect(billing.restores, 1);
      await store.buy(SupportItem.theme);
      expect(billing.bought, ['theme']);
      await store.buy(SupportItem.badge);
      expect(billing.bought, [
        'theme',
      ], reason: 'Block repeat taps while pending');
    },
  );

  test('pending, cancellation and errors never deliver items', () async {
    await store.initialize();
    for (final status in [
      PurchaseStatus.pending,
      PurchaseStatus.canceled,
      PurchaseStatus.error,
    ]) {
      await emit('badge', status);
      expect(store.owns(SupportItem.badge), isFalse);
      expect(store.owns(SupportItem.theme), isFalse);
    }
    expect(billing.completed, isEmpty);
  });

  test('badge purchase is acknowledged without granting the theme', () async {
    await store.initialize();
    await emit('badge', PurchaseStatus.purchased, complete: true);
    expect(store.owns(SupportItem.badge), isTrue);
    expect(store.owns(SupportItem.theme), isFalse);
    expect(billing.completed, ['badge']);
    await store.buy(SupportItem.badge);
    expect(billing.bought, isEmpty);
    store.selectTheme(true);
    expect(store.useTheme, isFalse);
  });

  test(
    'restore delivers theme and supports returning to original colors',
    () async {
      await store.initialize();
      await emit('theme', PurchaseStatus.restored, complete: true);
      expect(store.useTheme, isTrue);
      expect(store.owns(SupportItem.badge), isFalse);
      store.selectTheme(false);
      expect(store.useTheme, isFalse);
      await emit('theme', PurchaseStatus.restored);
      expect(
        store.useTheme,
        isFalse,
        reason: 'A repeated restore must not override a user choice',
      );
      store.selectTheme(true);
      expect(store.useTheme, isTrue);
    },
  );

  test('unknown products do not grant or acknowledge purchases', () async {
    await store.initialize();
    await emit('unknown', PurchaseStatus.purchased, complete: true);
    expect(billing.completed, isEmpty);
    expect(SupportItem.values.any(store.owns), isFalse);
  });

  test(
    'failed acknowledgement can be retried through restored delivery',
    () async {
      await store.initialize();
      billing.acknowledgeFails = true;
      await emit('badge', PurchaseStatus.purchased, complete: true);
      expect(store.status, SupportStoreStatus.failed);
      billing.acknowledgeFails = false;
      await emit('badge', PurchaseStatus.restored, complete: true);
      expect(store.status, SupportStoreStatus.purchased);
      expect(billing.completed, ['badge']);
    },
  );

  test('missing or duplicate configuration cannot start billing', () async {
    for (final config in [
      const SupportConfig(),
      const SupportConfig(productId: 'same', themeProductId: 'same'),
    ]) {
      final unavailable = PlaySupportStore(config, billing: billing);
      await unavailable.initialize();
      expect(unavailable.status, SupportStoreStatus.unavailable);
      unavailable.dispose();
    }
    expect(billing.queried, isNull);
  });

  test('unavailable billing can recover when the user retries', () async {
    billing.available = false;
    await store.initialize();
    expect(store.status, SupportStoreStatus.unavailable);
    expect(billing.queried, isNull);
    await store.buy(SupportItem.badge);
    expect(billing.bought, isEmpty);
    billing.available = true;
    await store.initialize();
    expect(store.status, SupportStoreStatus.ready);
    expect(billing.restores, 1);
  });

  test(
    'concurrent initialization shares a query and failed queries retry',
    () async {
      billing.queryFails = true;
      await Future.wait([store.initialize(), store.initialize()]);
      expect(billing.queries, 1);
      expect(store.status, SupportStoreStatus.failed);
      billing.queryFails = false;
      await store.initialize();
      expect(billing.queries, 2);
      expect(store.status, SupportStoreStatus.ready);
    },
  );

  test(
    'rejected and failed checkout release the pending state without rewards',
    () async {
      await store.initialize();
      billing.buyAccepted = false;
      await store.buy(SupportItem.badge);
      expect(store.status, SupportStoreStatus.ready);
      billing.buyFails = true;
      await store.buy(SupportItem.badge);
      expect(store.status, SupportStoreStatus.failed);
      expect(SupportItem.values.any(store.owns), isFalse);
      expect(billing.completed, isEmpty);
    },
  );
}
