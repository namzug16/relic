import 'dart:async';

import '../../relic.dart';

const _middlewareRouterContextKey = 'relic_router_middleware';

final _pathParametersStorage = ContextProperty<Map<Symbol, String>>();

extension RouteBuilderMiddlewareEx on RouteBuilder<Handler> {
  Middleware? get middleware {
    if (parent?.middleware != null) {
      if (_middleware != null) {
        return parent!.middleware!.addMiddleware(_middleware!);
      } else {
        return parent!.middleware;
      }
    }

    return _middleware;
  }

  Middleware? get _middleware =>
      (context[_middlewareRouterContextKey] as Middleware?);

  void _setMiddleware(final Middleware middleware) {
    context[_middlewareRouterContextKey] = middleware;
  }

  void use(final Middleware middleware) {
    if (_middleware == null) {
      _setMiddleware(middleware);
    } else {
      _setMiddleware(_middleware!.addMiddleware(middleware));
    }
  }
}

extension RouterCallEx on Router<Handler> {
  FutureOr<HandledContext> call(final NewContext ctx) async {
    final req = ctx.request;
    final url = ctx.request.url; // TODO: Use requestUri
    final match = lookup(req.method.convert(), url.path);
    if (match != null) {
      ctx._pathParameters = match.parameters;
      final handler = match.value;
      final builder = getRouteProvenance(handler);
      final middleware = builder.middleware;
      if (middleware != null) {
        return builder.middleware!(handler)(ctx);
      }
      return handler(ctx);
    } else {
      //NOTE: what should we do here?
      throw UnimplementedError();
    }
  }
}

extension RequestContextCallerEx on RequestContext {
  Map<Symbol, String> get pathParameters => _pathParametersStorage[this];

  set _pathParameters(final Map<Symbol, String> value) =>
      _pathParametersStorage[this] = value;
}

extension on RequestMethod {
  Method convert() {
    return switch (this) {
      RequestMethod.get => Method.get,
      RequestMethod.post => Method.post,
      RequestMethod.put => Method.put,
      RequestMethod.delete => Method.delete,
      RequestMethod.head => Method.head,
      RequestMethod.options => Method.options,
      RequestMethod.patch => Method.patch,
      RequestMethod.trace => Method.trace,
      RequestMethod.connect => Method.connect,
      _ => throw UnimplementedError(),
    };
  }
}

