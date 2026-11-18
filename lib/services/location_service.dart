import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class GeoPointResult {
  const GeoPointResult({
    required this.latitude,
    required this.longitude,
    required this.isFallback,
    this.statusMessage,
  });

  final double latitude;
  final double longitude;
  final bool isFallback;
  final String? statusMessage;
}

/// Handles device GPS capture, permission requests, and 1-tap Call / WhatsApp / Google Maps navigation.
class LocationService {
  LocationService._();

  /// Madurai HQ fallback coordinates (Saro Devi Enterprises).
  static const double defaultLat = 9.9252;
  static const double defaultLng = 78.1198;

  static Future<GeoPointResult> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const GeoPointResult(
          latitude: defaultLat,
          longitude: defaultLng,
          isFallback: true,
          statusMessage: 'Location services disabled; using Madurai HQ center.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const GeoPointResult(
          latitude: defaultLat,
          longitude: defaultLng,
          isFallback: true,
          statusMessage: 'Location permission denied; using Madurai HQ center.',
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return GeoPointResult(
        latitude: pos.latitude,
        longitude: pos.longitude,
        isFallback: false,
      );
    } catch (e) {
      return GeoPointResult(
        latitude: defaultLat,
        longitude: defaultLng,
        isFallback: true,
        statusMessage: 'GPS unavailable ($e); using Madurai HQ center.',
      );
    }
  }

  static Future<bool> launchGoogleMapsNavigation(
    double latitude,
    double longitude,
  ) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=driving',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> launchPhoneCall(String mobile) async {
    final clean = mobile.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    return launchUrl(uri);
  }

  static Future<bool> launchWhatsAppReminder({
    required String mobile,
    required String message,
  }) async {
    final digits = mobile.replaceAll(RegExp(r'[^0-9]'), '');
    final phone = digits.length == 10 ? '91$digits' : digits;
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$phone?text=$encoded');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
