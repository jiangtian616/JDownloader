import 'dart:io';

extension FileExtension on File {
  void deleteSyncIgnoreError({bool recursive = false}) {
    try {
      deleteSync(recursive: recursive);
    } catch (e) {}
  }
}
