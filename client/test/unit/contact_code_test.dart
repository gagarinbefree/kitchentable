import 'package:flutter_test/flutter_test.dart';
import 'package:kitchentable/contact_invite.dart';

void main() {
  final token = 'a' * 64;
  test('reads the full KitchenTable QR invitation', () {
    expect(contactToken('kitchentable://contact/$token'), token);
  });

  test('rejects subscriber numbers and unrelated or incomplete codes', () {
    for (final input in [
      null,
      '100002',
      token,
      'https://example.com/$token',
      'kitchentable://contact/100002',
      'kitchentable://contact/${token}0',
      'kitchentable://contact/$token?peer=100002',
    ]) {
      expect(contactToken(input), isNull);
    }
  });
}
