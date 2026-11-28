import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchentable/profiles.dart';

import '../support/device_preferences.dart';

void main() {
  test(
    'renaming and clearing a contact preserves the other local names',
    () async {
      final prefs = DevicePreferences();
      final container = ProviderContainer.test(
        overrides: [profilePreferencesProvider.overrideWithValue(prefs)],
      );
      final profiles = container.read(profileNamesProvider.notifier);
      await profiles.save(null, ' Владелец ');
      await profiles.save(100002, ' Анна ');
      await profiles.save(100003, 'Иван');
      await profiles.save(100002, 'Аня');
      expect((await readProfileNames(prefs))[100002], 'Аня');
      await profiles.save(100002, ' ');
      const expected = {null: 'Владелец', 100003: 'Иван'};
      expect(container.read(profileNamesProvider), expected);
      expect(await readProfileNames(prefs), expected);
    },
  );
}
