import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class ProfilePhotoService {
  final _storage = FirebaseStorage.instance;

  // Uploads a new profile photo and returns the download URL
  // If previousUrl is provided, delete the old file
  Future<String> uploadProfilePhoto({
    required String uid,
    required File file,
    String? previousUrl,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref().child("profilePhotos/$uid/$ts.jpg");

    await ref.putFile(
      file,
      SettableMetadata(contentType: "image/jpeg"),
    );

    final url = await ref.getDownloadURL();

    // Delete previous file
    if (previousUrl != null && previousUrl.trim().isNotEmpty) {
      try {
        final oldRef = _storage.refFromURL(previousUrl.trim());
        await oldRef.delete();
      } catch (_) {
      }
    }

    return url;
  }
}