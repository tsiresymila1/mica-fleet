import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/mock_location_guard_impl.dart';
import '../../data/plate_ocr_service_impl.dart';
import '../../domain/services/mock_location_guard.dart';
import '../../domain/services/plate_ocr_service.dart';

final plateOcrServiceProvider =
    Provider<PlateOcrService>((ref) => MlkitPlateOcrService());

final mockLocationGuardProvider =
    Provider<MockLocationGuard>((ref) => GeolocatorMockGuard());
