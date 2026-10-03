enum StorageType {
  local,
  remote;

  bool get isLocal => this == StorageType.local;
  bool get isRemote => this == StorageType.remote;
}
