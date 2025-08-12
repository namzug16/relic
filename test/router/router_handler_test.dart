import 'package:http/http.dart' as http;
import 'package:relic/relic.dart';
import 'package:test/test.dart';

import '../headers/headers_test_utils.dart';

extension on RequestContext {
  ResponseContext responseOkString(final String res) =>
      (this as RespondableContext)
          .withResponse(Response.ok(body: Body.fromString(res)));
}

Middleware _groupMiddleware(final String id) {
  return (final innerHandler) {
    return (final ctx) async {
      final handledCtx = await innerHandler(ctx);
      return switch (handledCtx) {
        final ResponseContext rc => rc.withResponse(
            rc.response.copyWith(headers: rc.response.headers.transform(
              (final mh) {
                mh['x-group'] = [id];
              },
            )),
          ),
        _ => handledCtx,
      };
    };
  };
}

Router<Handler> _createRouter() {
  final router = Router<Handler>()
    ..get('/hello', (final ctx) => ctx.responseOkString('Hello'))
    ..any('/universal', (final ctx) => ctx.responseOkString('Universal'))
    ..get(
        '/user/:id',
        (final ctx) =>
            ctx.responseOkString('User ${ctx.pathParameters[const Symbol("id")]}'));

  router.group('/api')
    ..use(_groupMiddleware('1'))
    ..get('/ping', (final ctx) => ctx.responseOkString('pong'));

  router.group('/g1')
    ..use(_groupMiddleware('g1'))
    ..get('/a', (final ctx) => ctx.responseOkString('a'));

  final g2 = router.group('/g2')
    ..use(_groupMiddleware('g2'))
    ..get('/b', (final ctx) => ctx.responseOkString('b'))
    //NOTE: test a middleware that has been added later one
    ..use((final innerHandler) {
      return (final ctx) async {
        final handledCtx = await innerHandler(ctx);
        return switch (handledCtx) {
          final ResponseContext rc => rc.withResponse(
              rc.response.copyWith(headers: rc.response.headers.transform(
                (final mh) {
                  mh['x-extra'] = [''];
                },
              )),
            ),
          _ => handledCtx,
        };
      };
    });

  //NOTE: nested group
  final _ = g2.group('/n')
    ..use((final innerHandler) {
      return (final ctx) async {
        final handledCtx = await innerHandler(ctx);
        return switch (handledCtx) {
          final ResponseContext rc => rc.withResponse(
              rc.response.copyWith(headers: rc.response.headers.transform(
                (final mh) {
                  mh['x-nested'] = ['g2/n'];
                },
              )),
            ),
          _ => handledCtx,
        };
      };
    })
    ..get('/c', (final ctx) => ctx.responseOkString('c'));

  //NOTE: tests also the correctness of middleware chaining in groups
  router.use((final innerHandler) {
    return (final ctx) async {
      final handledCtx = await innerHandler(ctx);
      return switch (handledCtx) {
        final ResponseContext rc => rc.withResponse(
            rc.response.copyWith(headers: rc.response.headers.transform(
              (final mh) {
                mh.xPoweredBy = 'test';
              },
            )),
          ),
        _ => handledCtx,
      };
    };
  });

  return router;
}

void main() {
  late RelicServer server;

  setUp(() async {
    server = await createServer(strictHeaders: false);

    await server.mountAndStart(_createRouter().call);
  });

  tearDown(() => server.close());

  Uri url(final String path) => Uri.parse('${server.url}$path');

  Future<String> read(final String path) => http.read(url(path));
  Future<int> head(final String path) async =>
      (await http.head(url(path))).statusCode;
  Future<http.Response> get(final String path) => http.get(url(path));
  Future<http.Response> put(final String path) => http.put(url(path));
  Future<http.Response> post(final String path) => http.post(url(path));

  test('should return correct handler', () async {
    expect(await head('/hello'), 200);
    expect(await read('/hello'), 'Hello');
  });

  // test('should return not found handler', () async {
  //   final res = await get('/notfound');
  //   expect(res.statusCode, 404);
  //   expect(res.body, 'Route not found');
  // });

  test("should support 'ANY' method fallback", () async {
    var res = await get('/universal');
    expect(res.statusCode, 200);
    expect(res.body, 'Universal');
    res = await put('/universal');
    expect(res.statusCode, 200);
    expect(res.body, 'Universal');
    res = await post('/universal');
    expect(res.statusCode, 200);
    expect(res.body, 'Universal');
  });

  test('should pass params to handler correctly', () async {
    expect(await read('/user/42'), 'User 42');
  });

  test('should apply middleware to matched route', () async {
    final res = await get('/hello');
    expect(res.statusCode, 200);
    expect(res.headers['x-powered-by'], 'test');
  });

  test('should apply group middleware to group routes', () async {
    final res = await get('/api/ping');
    expect(res.statusCode, 200);
    expect(res.headers['x-group'], '1');
  });

  test('should isolate middleware between groups', () async {
    final res1 = await get('/g1/a');
    final res2 = await get('/g2/b');

    expect(res1.statusCode, 200);
    expect(res2.statusCode, 200);

    expect(res1.headers['x-group'], 'g1');
    expect(res2.headers['x-group'], 'g2');
  });

  test('should add middleware globally to a group', () async {
    final res = await get('/g2/b');

    expect(res.statusCode, 200);

    expect(res.headers['x-group'], 'g2');
    expect(res.headers['x-extra'], '');
  });

  test('should nest groups correctly', () async {
    final res = await get('/g2/n/c');

    expect(res.statusCode, 200);
    expect(res.headers['x-group'], 'g2');
    expect(res.headers['x-extra'], '');
    expect(res.headers['x-nested'], 'g2/n');
    expect(res.body, 'c');
  });

  test('should all be powered by test', () async {
    Future<String?> getPoweredBy(final String path) async {
      final res = await get(path);
      return res.headers['x-powered-by'];
    }

    const s = 'test';

    expect(await getPoweredBy('/hello'), s);
    expect(await getPoweredBy('/universal'), s);
    expect(await getPoweredBy('/api/ping'), s);
    expect(await getPoweredBy('/g1/a'), s);
    expect(await getPoweredBy('/g2/b'), s);
    expect(await getPoweredBy('/g2/n/c'), s);
  });
}
