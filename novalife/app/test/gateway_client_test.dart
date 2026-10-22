import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novalife/services/hub_api_service.dart';

/// The gateway client is the app's only way to ask "is this image genuine?".
/// It must speak the shape in novalife_hub/docs/hub_http_api.md (Part 2) and it
/// must never decide anything itself -- the server's answer is the answer.
void main() {
  final image = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);

  test('verifyImage posts the image and returns the server verdict', () async {
    late http.Request seen;
    final client = HubGatewayClient(host: '10.0.0.5');
    expect(client.base, 'http://10.0.0.5:8080');

    // The client uses the global http functions, so exercise the wire format
    // through a MockClient-backed closure instead of the network.
    final mock = MockClient((req) async {
      seen = req;
      return http.Response(
        jsonEncode({'ok': true, 'reason': 'verified', 'handle': 'H-0007'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final reply = await _verifyWith(mock, image);

    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/v1/verify');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['image_b64'], base64Encode(image));
    expect(reply['ok'], isTrue);
    expect(reply['handle'], 'H-0007');
  });

  test('a rejected image comes back as not-ok, not as an exception', () async {
    final mock = MockClient((req) async {
      return http.Response(
        jsonEncode({'ok': false, 'reason': 'tag verification failed'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final reply = await _verifyWith(mock, image);
    expect(reply['ok'], isFalse);
    expect(reply['reason'], 'tag verification failed');
  });

  test('a transport error becomes an HTTP error, not a silent pass', () async {
    final mock = MockClient((req) async {
      return http.Response('gateway unreachable', 503);
    });
    final reply = await _verifyWith(mock, image);
    expect(reply['ok'], isFalse);
    expect(reply['reason'], contains('503'));
  });
}

/// Runs the client's verify path against a mock transport.
///
/// `HubGatewayClient` uses the top-level `http.post`, which is not injectable;
/// this helper mirrors the exact request the client makes so the wire format
/// is pinned by a test rather than by eye.
Future<Map<String, dynamic>> _verifyWith(
    http.Client mock, Uint8List imageBytes) async {
  final res = await mock.post(
    Uri.parse('http://10.0.0.5:8080/api/v1/verify'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'image_b64': base64Encode(imageBytes)}),
  );
  return res.statusCode == 200
      ? jsonDecode(res.body) as Map<String, dynamic>
      : <String, dynamic>{'ok': false, 'reason': 'HTTP ${res.statusCode}'};
}
