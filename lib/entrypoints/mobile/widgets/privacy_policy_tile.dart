import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const privacyPolicyUrl =
    'https://fluttering13.github.io/Terpsichore/privacy.html';

class PrivacyPolicyTile extends StatelessWidget {
  const PrivacyPolicyTile({required this.english, super.key});

  final bool english;

  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(
        Uri.parse(privacyPolicyUrl),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Keep the policy accessible when no browser can handle the URL.
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(english ? 'Privacy policy' : '隱私權政策'),
        content: const SelectableText(privacyPolicyUrl),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(text: privacyPolicyUrl),
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(english ? 'Copy link' : '複製連結'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(english ? 'Close' : '關閉'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.privacy_tip_outlined),
      title: Text(english ? 'Privacy policy' : '隱私權政策'),
      subtitle: Text(english ? 'Data use and deletion' : '資料使用與刪除方式'),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => _open(context),
    ),
  );
}
