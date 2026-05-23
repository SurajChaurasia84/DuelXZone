import 'dart:io';
import 'package:cloudinary_public/cloudinary_public.dart';

class CloudinaryService {
  static final CloudinaryService _instance = CloudinaryService._internal();
  factory CloudinaryService() => _instance;
  CloudinaryService._internal();

  final CloudinaryPublic _cloudinary = CloudinaryPublic(
    'dahva9bx6', // Your Cloud Name
    'dgOpxof1', // Your Unsigned Upload Preset
    cache: false,
  );

  /// Uploads a file to Cloudinary and returns the secure URL.
  /// [folder] is the path inside Cloudinary where the file should be stored.
  /// [resourceType] can be 'image' or 'video'.
  Future<String> uploadFile({
    required File file,
    required String folder,
    required CloudinaryResourceType resourceType,
  }) async {
    try {
      CloudinaryResponse response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          folder: folder,
          resourceType: resourceType,
        ),
      );
      return response.secureUrl;
    } catch (e) {
      throw Exception('Cloudinary Upload Failed: $e');
    }
  }
}
