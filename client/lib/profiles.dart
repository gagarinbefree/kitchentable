import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

import 'chat.dart';

SharedPreferencesAsync openProfilePreferences() => SharedPreferencesAsync(
  options: const SharedPreferencesAsyncAndroidOptions(
    backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
    originalSharedPreferencesOptions: AndroidSharedPreferencesStoreOptions(
      fileName: 'local_profile_names',
    ),
  ),
);

final profilePreferencesProvider = Provider((ref) => openProfilePreferences());
final initialProfileNamesProvider = Provider((ref) => const <int?, String>{});
final profileNamesProvider = NotifierProvider<ProfileNames, Map<int?, String>>(
  ProfileNames.new,
);

// A null key identifies the device owner's profile, even before connecting.
Future<Map<int?, String>> readProfileNames(SharedPreferencesAsync prefs) async {
  final names = <int?, String>{};
  for (final entry in (await prefs.getAll()).entries) {
    final id = int.tryParse(entry.key);
    if (entry.key != 'self' && id == null) continue;
    if (entry.value case final String name) names[id] = name;
  }
  return names;
}

class ProfileNames extends Notifier<Map<int?, String>> {
  @override
  Map<int?, String> build() => ref.watch(initialProfileNamesProvider);

  Future<void> save(int? peer, String input) async {
    final name = input.trim();
    final prefs = ref.read(profilePreferencesProvider);
    final key = peer?.toString() ?? 'self';
    if (name.isEmpty) {
      await prefs.remove(key);
      if (ref.mounted) state = {...state}..remove(peer);
    } else {
      await prefs.setString(key, name);
      if (ref.mounted) state = {...state, peer: name};
    }
  }
}

class ProfileEditor extends ConsumerStatefulWidget {
  const ProfileEditor({required this.number, this.isMine = false, super.key});
  final int? number;
  final bool isMine;

  @override
  ConsumerState<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<ProfileEditor> {
  int? get _key => widget.isMine ? null : widget.number;
  late final _name = TextEditingController(
    text: ref.read(profileNamesProvider)[_key],
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileNamesProvider.notifier).save(_key, _name.text);
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Не удалось сохранить имя. Попробуйте ещё раз.';
        });
      }
    }
  }

  Future<void> _hideContact() async {
    final peer = widget.number;
    if (widget.isMine || peer == null || _saving) return;
    final label = ref.read(profileNamesProvider)[peer] ?? 'Абонент $peer';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Скрыть абонента?'),
        content: Text(
          '«$label» исчезнет только из вашего списка. Переписка сохранится. Следующее входящее сообщение вернёт абонента в список.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Скрыть'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(directChatProvider.notifier).hideContact(peer);
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    } on Exception {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось скрыть абонента. Проверьте соединение и повторите попытку.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.isMine ? 'Мой профиль' : 'Профиль абонента'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.number != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SelectableText('Номер абонента: ${widget.number}'),
            ),
          TextField(
            controller: _name,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Имя',
              helperText: 'Имя видно только на этом устройстве.',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Сохранить'),
              ),
            ],
          ),
          if (!widget.isMine && widget.number != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _saving ? null : _hideContact,
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Скрыть из списка'),
              ),
            ),
        ],
      ),
    ),
  );
}
