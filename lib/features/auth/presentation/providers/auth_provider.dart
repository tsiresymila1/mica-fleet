import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../data/datasources/auth_local_ds.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/usecases/login.dart';

final loginProvider = Provider<Login>((ref) =>
    Login(AuthRepositoryImpl(AuthLocalDataSource(ref.watch(dbProvider)))));
