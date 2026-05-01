/// LRU (Least Recently Used) Cache implementation
/// Automatically evicts least recently used items when max capacity is reached
class LRUCache<K, V> {
  final int maxCapacity;
  final Map<K, V> _cache = {};
  final List<K> _accessOrder = [];

  LRUCache({required this.maxCapacity}) : assert(maxCapacity > 0);

  /// Get value from cache, updates access order
  V? get(K key) {
    if (_cache.containsKey(key)) {
      _accessOrder.remove(key);
      _accessOrder.add(key);
      return _cache[key];
    }
    return null;
  }

  /// Put value in cache, evicts LRU item if needed
  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      _accessOrder.remove(key);
    } else if (_cache.length >= maxCapacity) {
      _evictLRU();
    }
    _cache[key] = value;
    _accessOrder.add(key);
  }

  /// Check if key exists
  bool containsKey(K key) => _cache.containsKey(key);

  /// Get all cached values
  List<V> getAll() => _cache.values.toList();

  /// Get cache size
  int get size => _cache.length;

  /// Clear entire cache
  void clear() {
    _cache.clear();
    _accessOrder.clear();
  }

  /// Remove specific key
  V? remove(K key) {
    _accessOrder.remove(key);
    return _cache.remove(key);
  }

  /// Get cache stats for debugging
  Map<String, dynamic> getStats() => {
    'capacity': maxCapacity,
    'size': _cache.length,
    'utilization': '${(_cache.length / maxCapacity * 100).toStringAsFixed(1)}%',
  };

  /// Evict least recently used item
  void _evictLRU() {
    if (_accessOrder.isNotEmpty) {
      final lruKey = _accessOrder.removeAt(0);
      _cache.remove(lruKey);
    }
  }
}
