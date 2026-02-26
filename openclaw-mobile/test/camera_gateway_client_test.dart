import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../lib/infrastructure/camera_gateway_client.dart';

void main() {
  test('builds auth header and parses cameras', () async {
    final client = CameraGatewayClient(
      baseUrl: 'http://10.0.2.2:8799',
      bearerToken: 'demo-token',
      client: MockClient((request) async {
        expect(request.url.toString(), 'http://10.0.2.2:8799/cameras');
        expect(request.headers['authorization'], 'Bearer demo-token');
        return http.Response('{"cameras":[{"cameraId":"cam-living","name":"Living","location":"Living","status":"online","enabled":true}]}', 200);
      }),
    );

    final cameras = await client.listCameras();
    expect(cameras.single['cameraId'], 'cam-living');
  });

  test('handles 401 as unauthorized', () async {
    final client = CameraGatewayClient(
      baseUrl: 'http://10.0.2.2:8799',
      bearerToken: 'bad',
      client: MockClient((_) async => http.Response('{}', 401)),
    );

    expect(
      () => client.listCameras(),
      throwsA(isA<CameraGatewayException>().having((e) => e.code, 'code', 'unauthorized')),
    );
  });

  test('snapshot uses mode query', () async {
    final client = CameraGatewayClient(
      baseUrl: 'http://10.0.2.2:8799',
      bearerToken: 'demo-token',
      client: MockClient((request) async {
        expect(request.url.toString(), 'http://10.0.2.2:8799/cameras/cam-living/snapshot?mode=test_fall');
        return http.Response('{"cameraId":"cam-living","capturedAt":"2025-01-01T00:00:00Z"}', 200);
      }),
    );

    final snapshot = await client.getSnapshot(cameraId: 'cam-living', mode: 'test_fall');
    expect(snapshot['cameraId'], 'cam-living');
  });
}
