import 'package:flutter/services.dart';

abstract interface class BackgroundTripService {
  Future<void> start(String chargementId);
  Future<void> stop();
  Future<bool> isRunning();
}

class MethodChannelBackgroundTripService implements BackgroundTripService {
  static const _channel = MethodChannel('net.radoran.mica/trip_tracking');

  const MethodChannelBackgroundTripService();

  @override
  Future<void> start(String chargementId) =>
      _channel.invokeMethod<void>('start', {'chargementId': chargementId});

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  @override
  Future<bool> isRunning() async =>
      await _channel.invokeMethod<bool>('isRunning') ?? false;
}
