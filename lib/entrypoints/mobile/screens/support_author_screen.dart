import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/support/support_config.dart';
import '../../../infrastructure/engagement/emotion_backmail_service.dart';
import '../../../infrastructure/support/support_store.dart';

Future<bool> _openPayment(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

final class SupportAuthorScreen extends StatefulWidget {
  const SupportAuthorScreen({
    super.key,
    this.config,
    this.store,
    this.openPayment = _openPayment,
  });
  final SupportConfig? config;
  final SupportStore? store;
  final Future<bool> Function(Uri) openPayment;

  @override
  State<SupportAuthorScreen> createState() => _SupportAuthorScreenState();
}

final class _SupportAuthorScreenState extends State<SupportAuthorScreen> {
  late final config = widget.config ?? SupportConfig.fromEnvironment();
  late final store = widget.store ?? PlaySupportStore.instance;
  bool _opening = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    if (config.showPlay) {
      scheduleMicrotask(() {
        if (mounted) unawaited(store.initialize());
      });
    }
  }

  Future<void> _open(Uri uri, bool english) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      if (!await widget.openPayment(uri)) throw StateError('launch failed');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              english
                  ? 'Unable to open the payment page. Please try again.'
                  : '無法開啟付款頁，請稍後重試。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _restore(bool english) async {
    setState(() => _restoring = true);
    try {
      await store.restore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              english
                  ? 'Restore requested. Your items will appear when Google Play confirms ownership.'
                  : '已要求恢復購買，Google Play 確認後會顯示數位小物。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: EmotionBackmailService.language,
    builder: (context, language, _) {
      final en = language == AppLanguage.english;
      return Scaffold(
        appBar: AppBar(title: Text(en ? 'Support the creator' : '支持作者')),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(
                  Icons.favorite_outline,
                  size: 48,
                  color: Color(0xffff9eb7),
                ),
                const SizedBox(height: 16),
                Text(
                  en ? 'Keep Terpsichore dancing' : '讓 Terpsichore 繼續陪你跳舞',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  en
                      ? 'If this app helps your practice, you can support its development and maintenance. All practice tools remain available without a purchase.'
                      : '如果這個 App 對你的練習有幫助，歡迎支持開發與維護。不購買也能使用所有練習工具。',
                ),
                const SizedBox(height: 24),
                if (config.showPlay) ...[
                  _playCard(en, SupportItem.badge),
                  _playCard(en, SupportItem.theme),
                  if ((store.status == SupportStoreStatus.unavailable ||
                          store.status == SupportStoreStatus.failed) &&
                      SupportItem.values.every(
                        (item) => store.priceFor(item) == null,
                      ))
                    TextButton(
                      onPressed: store.initialize,
                      child: Text(
                        en ? 'Retry Google Play' : '重新連線 Google Play',
                      ),
                    ),
                  TextButton(
                    onPressed:
                        store.status != SupportStoreStatus.loading &&
                            store.status != SupportStoreStatus.pending &&
                            !_restoring &&
                            SupportItem.values.any(
                              (item) => store.priceFor(item) != null,
                            )
                        ? () => _restore(en)
                        : null,
                    child: Text(en ? 'Restore purchases' : '恢復購買'),
                  ),
                ],
                if (config.showEcpay)
                  _externalCard(
                    title: en ? 'ECPay · Taiwan' : '綠界 ECPay・台灣',
                    icon: Icons.payments_outlined,
                    uri: config.ecpayUri,
                    en: en,
                  ),
                if (config.showCoffee)
                  _externalCard(
                    title: 'Buy Me a Coffee',
                    icon: Icons.coffee_outlined,
                    uri: config.coffeeUri,
                    en: en,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _playCard(bool en, SupportItem item) {
    final pending = store.status == SupportStoreStatus.pending;
    final loading = store.status == SupportStoreStatus.loading;
    final price = store.priceFor(item);
    final available = price != null;
    final owned = store.owns(item);
    final badge = item == SupportItem.badge;
    return _card(
      children: [
        Text('Google Play', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Center(
          child: Semantics(
            label: badge
                ? (en ? 'Dancing star supporter badge' : '舞動之星支持者徽章')
                : (en ? 'Sunrise jade theme preview' : '晨曦金綠主題預覽'),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: badge
                    ? const Color(0xff403052)
                    : const Color(0xff10372f),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xffd6ad68), width: 2),
              ),
              child: Icon(
                badge ? Icons.auto_awesome : Icons.palette_outlined,
                size: 48,
                color: const Color(0xffffd78b),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          badge
              ? (en ? 'Dancing star · Commemorative badge' : '舞動之星・紀念徽章')
              : (en ? 'Sunrise jade · Color theme' : '晨曦金綠・配色主題'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          badge
              ? (en
                    ? 'Collect this badge on your support page.'
                    : '在支持頁收藏這枚紀念徽章。')
              : (en
                    ? 'A jade and gold palette for app controls and navigation. Video content and the home artwork keep their original colors.'
                    : '將 App 控制元件與導覽換成金綠配色，影片內容與首頁主視覺保留原色。'),
        ),
        Text(
          en
              ? 'One-time purchase, priced separately. Restore with the same Google Play account. No subscription.'
              : '各自定價、一次購買，可使用同一 Google Play 帳號恢復。不會自動續訂。',
        ),
        const SizedBox(height: 12),
        if (owned)
          Text(
            en ? 'In your collection — thank you!' : '已收藏，謝謝你的支持！',
            key: ValueKey('support-${item.name}-owned'),
          ),
        if (owned && !badge)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(en ? 'Use sunrise jade' : '使用晨曦金綠配色'),
            value: store.useTheme,
            onChanged: store.selectTheme,
          ),
        if (pending)
          Text(
            en
                ? 'Waiting for Google Play to complete payment…'
                : '等待 Google Play 完成付款…',
          ),
        if (loading) const LinearProgressIndicator(),
        if (!available && !loading)
          Text(
            en
                ? 'Google Play purchases are currently unavailable.'
                : '目前暫不提供 Google Play 購買。',
          ),
        if (store.status == SupportStoreStatus.failed)
          Text(
            en
                ? 'Unable to complete the request. Please try again or restore purchases.'
                : '暫時無法完成要求，請重試或恢復購買。',
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: available && !pending && !loading && !owned && !_restoring
              ? () => store.buy(item)
              : null,
          child: Text(
            owned
                ? (en ? 'Owned' : '已擁有')
                : available
                ? (en ? 'Purchase · $price' : '購買・$price')
                : (en ? 'Unavailable' : '尚未開放'),
          ),
        ),
      ],
    );
  }

  Widget _externalCard({
    required String title,
    required IconData icon,
    required Uri? uri,
    required bool en,
  }) => _card(
    children: [
      Icon(icon, size: 32),
      const SizedBox(height: 8),
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        en
            ? 'Voluntary support with no digital rewards. This does not include Google Play items. Payment opens on an external website.'
            : '自願打賞，不提供數位回饋，也不包含 Google Play 數位小物。付款會開啟外部網站。',
      ),
      if (uri == null)
        Text(en ? 'This support option is not available yet.' : '此支持管道尚未開放。'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: uri == null || _opening ? null : () => _open(uri, en),
        icon: const Icon(Icons.open_in_new),
        label: Text(en ? 'Open support page' : '前往支持頁面'),
      ),
    ],
  );

  Widget _card({required List<Widget> children}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}
