import 'router.dart';

/// Stores a RouteBuilder<T> associated to an arbitrary key.
/// - Uses Expando for non-primitive objects (identity semantics, no memory leaks).
/// - Uses a Map for primitives (String/int/double/bool/record/null).
class RouteProvenanceStore<T> {
  final Expando<RouteBuilder<T>> _expando = Expando<RouteBuilder<T>>();
  final Map<Object?, RouteBuilder<T>> _valueMap = <Object?, RouteBuilder<T>>{};

  // Treat these as "not supported by Expando" keys.
  static bool _isPrimitive(final Object? o) =>
      o == null || o is String || o is num || o is bool || o is Record;

  void set(final Object? key, final RouteBuilder<T> builder) {
    if (_isPrimitive(key)) {
      _valueMap[key] = builder;
    } else {
      _expando[key!] = builder;
    }
  }

  RouteBuilder<T>? get(final Object? key) {
    if (_isPrimitive(key)) {
      return _valueMap[key];
    } else {
      return _expando[key!];
    }
  }

  bool containsKey(final Object? key) {
    if (_isPrimitive(key)) {
      return _valueMap.containsKey(key);
    } else {
      return _expando[key!] != null;
    }
  }

  /// Returns the removed builder if present.
  RouteBuilder<T>? remove(final Object? key) {
    if (_isPrimitive(key)) {
      return _valueMap.remove(key);
    } else {
      final prev = _expando[key!];
      if (prev != null) _expando[key] = null; // break association
      return prev;
    }
  }

  /// Only clears the Map side (the Expando side can’t be bulk-cleared).
  void clearPrimitives() => _valueMap.clear();
}
