import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

Future<Map<String, dynamic>> serverAccessRequest(
  Map<String, dynamic> command,
) async {
  final reply = jsonDecode(
    await bind.mainServerAccess(command: jsonEncode(command)),
  );
  if (reply['ok'] != true) {
    throw Exception(reply['error'] ?? translate('Failed'));
  }
  return Map<String, dynamic>.from(reply['value']);
}

class ServerAccessSettings extends StatefulWidget {
  final TextEditingController serverController;
  const ServerAccessSettings({super.key, required this.serverController});

  @override
  State<ServerAccessSettings> createState() => ServerAccessSettingsState();
}

class ServerAccessSettingsState extends State<ServerAccessSettings> {
  final _secret = TextEditingController();
  final _minutes = TextEditingController(text: '10');
  bool _loaded = false;
  bool _serviceUnavailable = false;
  bool _hasSecret = false;
  bool _editing = false;
  bool _secretChanged = false;
  bool _clear = false;
  bool _enabled = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    serverAccessRequest({'action': 'status'})
        .then((value) {
          if (!mounted) return;
          setState(() {
            _hasSecret = value['has_secret'] == true;
            _secret.text = _hasSecret ? '••••••••••••••••••••' : '';
            _enabled = value['enabled'] == true;
            _minutes.text = (value['minutes'] ?? 10).toString();
            _serviceUnavailable = value['available'] == false;
            _loaded = !_serviceUnavailable;
          });
        })
        .catchError((Object error) {
          if (mounted) setState(() => _error = error.toString());
        });
  }

  bool validate() {
    if (!_dirty) return true;
    final minutes = int.tryParse(_minutes.text);
    String? error;
    if (minutes == null || minutes < 1 || minutes > 1440) {
      error = translate(
        'Invitation validity must be between 1 and 1440 minutes',
      );
    } else if (widget.serverController.text.trim().isEmpty &&
        ((_secretChanged && _secret.text.isNotEmpty) || _enabled)) {
      error = translate('ID Server');
    }
    setState(() => _error = error);
    return error == null;
  }

  Future<bool> save() async {
    if (!_dirty) return true;
    if (!validate()) return false;
    try {
      final minutes = int.tryParse(_minutes.text);
      if (minutes == null || minutes < 1 || minutes > 1440) {
        throw Exception(
          translate('Invitation validity must be between 1 and 1440 minutes'),
        );
      }
      await serverAccessRequest({
        'action': 'save',
        'server': widget.serverController.text.trim(),
        'secret': _secretChanged && _secret.text.isNotEmpty
            ? _secret.text
            : null,
        'clear': _clear || (_secretChanged && _secret.text.isEmpty),
        'enabled': _enabled,
        'minutes': minutes,
      });
      _secret.clear();
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return false;
    }
  }

  @override
  void dispose() {
    _secret.clear();
    _secret.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = _secretChanged
        ? _secret.text.isNotEmpty
        : (_hasSecret && !_clear);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(width: 120, child: Text(translate('Private key'))),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _secret,
                enabled: _loaded,
                readOnly: !_editing && _hasSecret,
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                onTap: () {
                  if (_hasSecret && !_editing) {
                    setState(() {
                      _secret.clear();
                      _editing = true;
                    });
                  }
                },
                onChanged: (_) => setState(() {
                  _secretChanged = true;
                  _dirty = true;
                  _clear = false;
                  if (_secret.text.isEmpty) _enabled = false;
                }),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  suffixIcon: hasValue
                      ? IconButton(
                          tooltip: translate('Clear'),
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() {
                            _secret.clear();
                            _clear = true;
                            _hasSecret = false;
                            _secretChanged = true;
                            _editing = true;
                            _enabled = false;
                            _dirty = true;
                          }),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(translate('Enable guest invitations')),
          value: _enabled,
          onChanged: _loaded && hasValue
              ? (value) => setState(() {
                  _enabled = value;
                  _dirty = true;
                })
              : null,
        ),
        Row(
          children: [
            Expanded(child: Text(translate('Invitation validity (minutes)'))),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _minutes,
                enabled: _loaded && _enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _dirty = true,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(8),
                ),
              ),
            ),
          ],
        ),
        if (_serviceUnavailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              translate('Install or restart the updated RustDesk client service to use private keys and guest invitations'),
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
