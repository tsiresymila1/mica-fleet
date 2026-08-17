import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  final String version;
  final int build;
  final String apkUrl;
  final String sha256Hash;
  final bool mandatory;
  final String? releaseNotes;

  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.sha256Hash,
    required this.mandatory,
    required this.releaseNotes,
  });
}

class AppUpdateCheck {
  final String currentVersion;
  final int currentBuild;
  final AppUpdateInfo? update;

  const AppUpdateCheck({
    required this.currentVersion,
    required this.currentBuild,
    required this.update,
  });
}

class AppUpdateService {
  static const _channel = MethodChannel('net.radoran.mica/app_update');
  final Dio dio;

  const AppUpdateService(this.dio);

  Future<AppUpdateCheck> check() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('La mise à jour directe est réservée à Android');
    }
    final installed = await _channel.invokeMapMethod<String, dynamic>(
      'getVersion',
    );
    final currentBuild = (installed?['build'] as num?)?.toInt() ?? 0;
    final currentVersion = installed?['version']?.toString() ?? '';
    final response = await dio.get<dynamic>(
      '/api/app/version',
      queryParameters: {'platform': 'android', 'current_build': currentBuild},
    );
    final root = response.data;
    if (root is! Map || root['status'] == 'error') {
      throw FormatException(
        root is Map
            ? root['message']?.toString() ?? 'Réponse de mise à jour invalide'
            : 'Réponse de mise à jour invalide',
      );
    }
    final data = root['data'];
    if (data == null || data is! Map || data['available'] == false) {
      return AppUpdateCheck(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        update: null,
      );
    }
    final build = (data['build'] as num?)?.toInt();
    final apkUrl = data['apk_url']?.toString();
    final hash = data['sha256']?.toString().toLowerCase();
    if (build == null || apkUrl == null || hash == null) {
      throw const FormatException('Informations APK incomplètes');
    }
    if (Uri.tryParse(apkUrl)?.scheme != 'https') {
      throw const FormatException('L’URL de l’APK doit utiliser HTTPS');
    }
    return AppUpdateCheck(
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      update: build > currentBuild
          ? AppUpdateInfo(
              version: data['version']?.toString() ?? build.toString(),
              build: build,
              apkUrl: apkUrl,
              sha256Hash: hash,
              mandatory: data['mandatory'] as bool? ?? false,
              releaseNotes: data['release_notes']?.toString(),
            )
          : null,
    );
  }

  Future<String> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final cache = await getTemporaryDirectory();
    final directory = Directory('${cache.path}/updates');
    await directory.create(recursive: true);
    final apk = File('${directory.path}/mica-fleet-${update.build}.apk');
    await dio.download(
      update.apkUrl,
      apk.path,
      onReceiveProgress: onProgress,
      options: Options(followRedirects: true),
    );
    final actual = (await sha256.bind(apk.openRead()).first).toString();
    if (actual.toLowerCase() != update.sha256Hash.toLowerCase()) {
      await apk.delete();
      throw StateError('La signature SHA-256 de l’APK ne correspond pas');
    }
    return await _channel.invokeMethod<String>('installApk', {
          'path': apk.path,
        }) ??
        'installer_opened';
  }
}
