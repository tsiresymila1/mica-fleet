import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import '../domain/entities/sync_operation.dart';
import '../domain/repositories/remote_data_source.dart';

part 'remote_data_source_retrofit.g.dart';

@RestApi()
abstract class OdooApi {
  factory OdooApi(Dio dio, {String baseUrl}) = _OdooApi;

  @POST('/mica/sync/operation')
  Future<void> pushOperation(@Body() Map<String, dynamic> body);

  @GET('/mica/mines')
  Future<dynamic> fetchMines();
}

class RetrofitRemoteDataSource implements RemoteDataSource {
  final OdooApi api;
  RetrofitRemoteDataSource(this.api);

  @override
  Future<void> pushOperation(SyncOperation op) {
    return api.pushOperation({
      'op_id': op.opId,
      'entity_type': op.entityType,
      'entity_id': op.entityId,
      'op_type': op.opType.name,
      'payload': op.payload,
    });
  }

  @override
  Future<List<RemoteMine>> fetchMines() async {
    final raw = (await api.fetchMines()) as List<dynamic>;
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      return RemoteMine(
        m['id'].toString(),
        m['nom'] as String,
        (m['lat'] as num).toDouble(),
        (m['lon'] as num).toDouble(),
        (m['rayon_metres'] as num?)?.toDouble() ?? 20,
        m['district'] as String?,
        m['commune'] as String?,
        m['region'] as String?,
        m['actif'] as bool? ?? true,
      );
    }).toList();
  }
}
