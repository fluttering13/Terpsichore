import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/support/support_config.dart';

enum SupportStoreStatus {
  loading,
  unavailable,
  ready,
  pending,
  purchased,
  failed,
}

abstract interface class SupportStore implements Listenable {
  SupportStoreStatus get status;
  String? priceFor(SupportItem item);
  bool owns(SupportItem item);
  bool get useTheme;
  void selectTheme(bool value);
  Future<void> initialize();
  Future<void> buy(SupportItem item);
  Future<void> restore();
}

/// App-lifetime listener: purchases can finish after the support route closes.
final class PlaySupportStore extends ChangeNotifier implements SupportStore {
  PlaySupportStore(this.config, {InAppPurchase? billing}) {
    _billing = billing;
  }
  static final instance = PlaySupportStore(SupportConfig.fromEnvironment());
  final SupportConfig config;
  InAppPurchase? _billing;
  InAppPurchase get billing => _billing ??= InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void>? _initializing;
  final _products = <SupportItem, ProductDetails>{};
  final _owned = <SupportItem>{};
  bool? _themeSelected;
  @override
  SupportStoreStatus status = SupportStoreStatus.loading;
  @override
  bool owns(SupportItem item) => _owned.contains(item);
  @override
  String? priceFor(SupportItem item) => _products[item]?.price;
  @override
  bool get useTheme => owns(SupportItem.theme) && (_themeSelected ?? true);
  @override
  void selectTheme(bool value) {
    if (value && !owns(SupportItem.theme)) return;
    _themeSelected = value;
    notifyListeners();
  }

  @override
  Future<void> initialize() {
    if (_products.isNotEmpty) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    _set(SupportStoreStatus.loading);
    final ids = SupportItem.values
        .map(config.idFor)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (!config.showPlay ||
        ids.isEmpty ||
        !config.validProducts ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      _set(SupportStoreStatus.unavailable);
      return;
    }
    try {
      _subscription ??= billing.purchaseStream.listen(
        (items) => unawaited(_purchases(items)),
        onError: (Object _) => _set(SupportStoreStatus.failed),
      );
      if (!await billing.isAvailable()) {
        _set(SupportStoreStatus.unavailable);
        return;
      }
      final response = await billing.queryProductDetails(ids);
      if (response.error != null || response.productDetails.isEmpty) {
        _set(SupportStoreStatus.unavailable);
        return;
      }
      for (final product in response.productDetails) {
        for (final item in SupportItem.values) {
          if (config.idFor(item) == product.id) _products[item] = product;
        }
      }
      _set(SupportStoreStatus.ready);
      await restore();
    } catch (_) {
      _set(SupportStoreStatus.failed);
    }
  }

  Future<void> _purchases(List<PurchaseDetails> items) async {
    for (final item in items) {
      final matches = SupportItem.values.where(
        (type) =>
            config.idFor(type).isNotEmpty &&
            config.idFor(type) == item.productID,
      );
      if (matches.isEmpty) continue;
      final type = matches.single;
      switch (item.status) {
        case PurchaseStatus.pending:
          _set(SupportStoreStatus.pending);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Cosmetic entitlement only. Play rehydrates it on startup/restore;
          // no client preference is used as proof of a purchase.
          _owned.add(type);
          _set(SupportStoreStatus.purchased);
        case PurchaseStatus.canceled:
          _set(SupportStoreStatus.ready);
        case PurchaseStatus.error:
          _set(SupportStoreStatus.failed);
      }
      if (item.pendingCompletePurchase &&
          item.status != PurchaseStatus.pending) {
        try {
          await billing.completePurchase(item);
        } catch (_) {
          // Leave acknowledgement pending for the next Play delivery/restore.
          _set(SupportStoreStatus.failed);
        }
      }
    }
  }

  @override
  Future<void> buy(SupportItem item) async {
    final product = _products[item];
    if (product == null || owns(item) || status == SupportStoreStatus.pending) {
      return;
    }
    _set(SupportStoreStatus.pending);
    try {
      if (!await billing.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      )) {
        _set(SupportStoreStatus.ready);
      }
    } catch (_) {
      _set(SupportStoreStatus.failed);
    }
  }

  @override
  Future<void> restore() async {
    if (_products.isEmpty || status == SupportStoreStatus.pending) return;
    try {
      await billing.restorePurchases();
    } catch (_) {
      _set(SupportStoreStatus.failed);
    }
  }

  void _set(SupportStoreStatus value) {
    status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
