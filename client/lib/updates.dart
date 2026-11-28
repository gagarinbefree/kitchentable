import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

const _repository = 'gagarinbefree/kitchentable';
const _apkName = 'KitchenTable-Android.apk';
const _android = MethodChannel('kitchentable/updates');
final updatesProvider = Provider((ref) => AppUpdates());

class AppRelease {
  const AppRelease(this.code, this.version, this.size, this.digest);
  final int code;
  final String version;
  final int size;
  final String digest;

  Uri get url => Uri.https(
    'github.com',
    '/$_repository/releases/download/v$version/$_apkName',
  );
}

AppRelease? findUpdate(Map<String, dynamic> release, int installed) {
  if (release['draft'] == true || release['prerelease'] == true) return null;
  final tag = release['tag_name'];
  final match = tag is String
      ? RegExp(r'^v1\.0\.([0-9]+)$').firstMatch(tag)
      : null;
  if (match == null) throw const FormatException('Unknown release tag');
  final code = int.parse(match[1]!);
  if (code <= installed) return null;
  final assets = release['assets'];
  if (assets is List) {
    for (final asset in assets.whereType<Map>()) {
      if (asset['state'] != 'uploaded' || asset['name'] != _apkName) continue;
      final digest = asset['digest'];
      final size = asset['size'];
      if (size is int &&
          size > 0 &&
          digest is String &&
          RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(digest)) {
        return AppRelease(code, '1.0.$code', size, digest.substring(7));
      }
    }
  }
  throw const FormatException('Release APK unavailable');
}

typedef UpdateCheck = ({String installed, AppRelease? available});

class AppUpdates {
  Future<UpdateCheck> check() async {
    final info = (await _android.invokeMapMethod<String, dynamic>(
      'installed',
    ))!;
    final client = http.Client();
    try {
      final response = await client
          .get(
            Uri.https('api.github.com', '/repos/$_repository/releases/latest'),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'KitchenTable-Android',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw const HttpException('Release lookup failed');
      }
      return (
        installed: info['name'] as String,
        available: findUpdate(
          jsonDecode(response.body) as Map<String, dynamic>,
          info['code'] as int,
        ),
      );
    } finally {
      client.close();
    }
  }

  Future<String> install(
    AppRelease release,
    http.Client client,
    void Function(double) progress,
    bool Function() active,
  ) async {
    final directory = (await _android.invokeMethod<String>('directory'))!;
    final apk = File('$directory/update.apk');
    Future<bool> valid(File file) async =>
        await file.exists() &&
        await file.length() == release.size &&
        (await sha256.bind(file.openRead()).first).toString() == release.digest;
    if (!await valid(apk)) {
      final temp = File(
        '${apk.path}.${DateTime.now().microsecondsSinceEpoch}.part',
      );
      try {
        final response = await client
            .send(http.Request('GET', release.url))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw const HttpException('APK download failed');
        }
        final sink = temp.openWrite();
        var bytes = 0;
        try {
          await sink.addStream(
            response.stream.timeout(const Duration(seconds: 30)).map((chunk) {
              bytes += chunk.length;
              if (bytes > release.size) {
                throw const FormatException('Unexpected APK size');
              }
              progress(bytes / release.size);
              return chunk;
            }),
          );
        } finally {
          await sink.close();
        }
        if (!await valid(temp)) {
          throw const FormatException('APK verification failed');
        }
        await temp.rename(apk.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    }
    if (!active()) return 'cancelled';
    await _android.invokeMethod<void>('verify', release.code);
    if (!active()) return 'cancelled';
    return (await _android.invokeMethod<String>('install', release.code))!;
  }
}
