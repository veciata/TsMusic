class LRUCache<K, V> {
  final int maxCapacity;
  final Map<K, V> _cache = {};
  final List<K> _accessOrder = [];
  LRUCache({required this.maxCapacity}) : assert(maxCapacity > 0);
  V? get(K key) {
    if (_cache.containsKey(key)) {
      _accessOrder.remove(key);
      _accessOrder.add(key);
      return _cache[key];
    }
    return null;
  }
  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      _accessOrder.remove(key);
    } else if (_cache.length >= maxCapacity) {
      _evictLRU();
    }
    _cache[key] = value;
    _accessOrder.add(key);
  }
  bool containsKey(K key) => _cache.containsKey(key);
  List<V> getAll() => _cache.values.toList();
  int get size => _cache.length;
  void clear() {
    _cache.clear();
    _accessOrder.clear();
  }
  V? remove(K key) {
    _accessOrder.remove(key);
    return _cache.remove(key);
  }
  Map<String, dynamic> getStats() => {
    'capacity': maxCapacity,
    'size': _cache.length,
    'utilization': '${(_cache.length / maxCapacity * 100).toStringAsFixed(1)}%',
  };
  void _evictLRU() {
    if (_accessOrder.isNotEmpty) {
      final lruKey = _accessOrder.removeAt(0);
      _cache.remove(lruKey);
    }
  }
}
