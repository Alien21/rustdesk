import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/server_access_settings.dart';
import 'package:flutter_hbb/models/platform_model.dart';

class GuestInvitationButton extends StatefulWidget {
  const GuestInvitationButton({super.key});

  @override
  State<GuestInvitationButton> createState() => _GuestInvitationButtonState();
}

class _GuestInvitationButtonState extends State<GuestInvitationButton> {
  Timer? _timer;
  bool _enabled = false;
  bool _busy = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_checking) return;
    _checking = true;
    try {
      final status = await serverAccessRequest({'action': 'status'});
      if (mounted)
        setState(
          () => _enabled =
              status['enabled'] == true && status['has_secret'] == true,
        );
    } catch (_) {
      if (mounted) setState(() => _enabled = false);
    } finally {
      _checking = false;
    }
  }

  Future<void> _invite() async {
    setState(() => _busy = true);
    try {
      final result = await serverAccessRequest({'action': 'create'});
      if (!mounted) return;
      final address = result['address'] as String;
      gFFI.dialogManager.show(
        (setState, close, context) => CustomAlertDialog(
          title: Text(translate('Invite guest')),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: address,
                        readOnly: true,
                      ),
                    ),
                    IconButton(
                      tooltip: translate('Copy'),
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: address));
                        showToast(translate('Copied'));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  translate(
                    'The invitation expires for new connections. Accepted sessions can continue.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            dialogButton(
              'Revoke invitation',
              isOutline: true,
              onPressed: () async {
                try {
                  await serverAccessRequest({'action': 'revoke'});
                  close();
                } catch (error) {
                  showToast(error.toString());
                }
              },
            ),
            dialogButton('Close', onPressed: () => close()),
          ],
        ),
      );
    } catch (error) {
      showToast(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _enabled && !_busy ? _invite : null,
        child: Text(translate('Invite guest')),
      ),
    ),
  );
}
