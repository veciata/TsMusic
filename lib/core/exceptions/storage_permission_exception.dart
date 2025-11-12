class StoragePermissionException implements Exception {
  final String message;
  StoragePermissionException(this.message);

  @override
  String toString() => 'StoragePermissionException: $message';
}
