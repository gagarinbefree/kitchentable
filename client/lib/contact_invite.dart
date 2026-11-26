import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'chat.dart';

final _contactCode = RegExp(r'^kitchentable://contact/([0-9a-f]{64})$');

String? contactToken(String? value) =>
    value == null ? null : _contactCode.firstMatch(value)?.group(1);

class ContactInvitePage extends ConsumerStatefulWidget {
  const ContactInvitePage({super.key});
  @override
  ConsumerState<ContactInvitePage> createState() => _ContactInvitePageState();
}

class _ContactInvitePageState extends ConsumerState<ContactInvitePage> {
  String? _ownToken;
  String? _scannedToken;
  int? _peer;
  String? _error;
  bool _scanning = false;
  bool _busy = true;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    _expiry?.cancel();
    setState(() {
      _busy = true;
      _error = null;
      _ownToken = null;
      _scannedToken = null;
      _peer = null;
      _scanning = false;
    });
    try {
      final token = await ref.read(directChatProvider.notifier).createInvite();
      if (!mounted) return;
      setState(() => _ownToken = token);
      _expiry = Timer(const Duration(minutes: 5), () {
        if (mounted) setState(() => _ownToken = null);
      });
    } on Exception {
      if (mounted) {
        setState(
          () =>
              _error = 'Не удалось получить приглашение. Проверьте соединение.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scan() {
    setState(() {
      _error = null;
      _scannedToken = null;
      _peer = null;
      _scanning = true;
    });
  }

  Future<void> _detected(BarcodeCapture capture) async {
    if (!_scanning || _busy || capture.barcodes.isEmpty) return;
    final token = contactToken(capture.barcodes.first.rawValue);
    setState(() {
      _scanning = false;
      _busy = token != null;
      _error = token == null ? 'Это не приглашение KitchenTable.' : null;
    });
    if (token == null) return;
    try {
      final peer = await ref
          .read(directChatProvider.notifier)
          .previewInvite(token);
      if (mounted) {
        setState(() {
          _scannedToken = token;
          _peer = peer;
        });
      }
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Приглашение недоступно. Попросите собеседника обновить QR-код.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    if (_busy || _scannedToken == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(directChatProvider.notifier).acceptInvite(_scannedToken!);
      if (mounted) Navigator.of(context).pop();
    } on Exception {
      if (mounted) {
        setState(
          () => _error = 'Не удалось добавить абонента. Проверьте соединение или отсканируйте новый QR-код.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(directChatProvider.select((state) => state.contacts), (
      previous,
      next,
    ) {
      if (!_busy &&
          !_scanning &&
          _scannedToken == null &&
          _ownToken != null &&
          previous != null &&
          next.any((peer) => !previous.contains(peer)) &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить абонента')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_scanning)
              AspectRatio(
                aspectRatio: 1,
                child: MobileScanner(
                  onDetect: _detected,
                  errorBuilder: (_, _) => const Center(
                    child: Text(
                      'Для сканирования разрешите доступ к камере в настройках приложения.',
                    ),
                  ),
                ),
              )
            else if (_busy && _peer == null)
              const Center(child: CircularProgressIndicator())
            else if (_peer != null)
              Text(
                'Добавить абонента $_peer?',
                style: Theme.of(context).textTheme.titleLarge,
              )
            else if (_ownToken != null)
              Center(
                child: QrImageView(
                  data: 'kitchentable://contact/$_ownToken',
                  size: 240,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(20),
                  semanticsLabel: 'Мой QR-код',
                ),
              )
            else if (_error == null)
              const Text('Срок действия QR-кода истёк.'),
            if (!_scanning && _peer == null && _ownToken != null)
              const Center(
                child: Text('Покажите код собеседнику. Он действует 5 минут.'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!),
              ),
            const SizedBox(height: 20),
            if (_peer != null)
              FButton(
                onPress: _busy ? null : _accept,
                child: const Text('Добавить в контакты'),
              ),
            if (!_scanning)
              FButton(
                variant: _peer == null ? .primary : .outline,
                onPress: _busy ? null : _scan,
                child: const Text('Сканировать QR'),
              ),
            const SizedBox(height: 8),
            FButton(
              variant: .outline,
              onPress: _busy ? null : _generate,
              child: Text(
                _scanning || _peer != null
                    ? 'Показать мой QR'
                    : 'Обновить мой QR',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
