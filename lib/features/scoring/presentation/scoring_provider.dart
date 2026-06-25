import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/scoring_engine.dart';

final scoringEngineProvider = Provider((ref) => ScoringEngine());
