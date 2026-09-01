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

abstract interface class AppUpdateGateway {
  Future<AppUpdateCheck> check();

  Future<String> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(int received, int total)? onProgress,
  });
}

class InstalledAppVersion {
  final String version;
  final int build;

  const InstalledAppVersion({required this.version, required this.build});
}

abstract interface class AppUpdatePlatformBridge {
  bool get isSupported;

  Future<InstalledAppVersion> installedVersion();

  Future<String> installApk(String path);
}

class MethodChannelAppUpdateBridge implements AppUpdatePlatformBridge {
  static const _channel = MethodChannel('net.radoran.mica/app_update');

  const MethodChannelAppUpdateBridge();

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<InstalledAppVersion> installedVersion() async {
    final installed = await _channel.invokeMapMethod<String, dynamic>(
      'getVersion',
    );
    return InstalledAppVersion(
      version: installed?['version']?.toString() ?? '',
      build: (installed?['build'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<String> installApk(String path) async =>
      await _channel.invokeMethod<String>('installApk', {'path': path}) ??
      'installer_opened';
}

class AppUpdateService implements AppUpdateGateway {
  final Dio dio;
  final AppUpdatePlatformBridge platformBridge;

  const AppUpdateService(
    this.dio, {
    this.platformBridge = const MethodChannelAppUpdateBridge(),
  });

  @override
  Future<AppUpdateCheck> check() async {
    if (!platformBridge.isSupported) {
      throw UnsupportedError('La mise à jour directe est réservée à Android');
    }
    final installed = await platformBridge.installedVersion();
    final response = await dio.get<dynamic>(
      '/api/app/version',
      queryParameters: {'platform': 'android'},
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
        currentVersion: installed.version,
        currentBuild: installed.build,
        update: null,
      );
    }
    final version = data['version']?.toString().trim();
    final build = (data['build'] as num?)?.toInt();
    final apkUrl = data['apk_url']?.toString();
    final hash = data['sha256']?.toString().toLowerCase();
    final mandatory = data['mandatory'];
    if (version == null ||
        version.isEmpty ||
        build == null ||
        apkUrl == null ||
        hash == null ||
        hash.isEmpty ||
        mandatory is! bool) {
      throw const FormatException('Informations APK incomplètes');
    }
    if (Uri.tryParse(apkUrl)?.scheme != 'https') {
      throw const FormatException('L’URL de l’APK doit utiliser HTTPS');
    }
    return AppUpdateCheck(
      currentVersion: installed.version,
      currentBuild: installed.build,
      update: build > installed.build
          ? AppUpdateInfo(
              version: version,
              build: build,
              apkUrl: apkUrl,
              sha256Hash: hash,
              mandatory: mandatory,
              releaseNotes: data['release_notes']?.toString(),
            )
          : null,
    );
  }

  @override
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
    return platformBridge.installApk(apk.path);
  }
}
