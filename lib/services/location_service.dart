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

/// Handles device GPS capture, city/pincode coordinate sanity resolution,
/// Google Maps URL parsing, and 1-tap Call / WhatsApp / Navigation.
class LocationService {
  LocationService._();

  /// Madurai HQ fallback coordinates (Saro Devi Enterprises).
  static const double defaultLat = 9.9252;
  static const double defaultLng = 78.1198;

  static const Map<String, List<double>> _cityCenters = {
    'HODAL': [27.8920, 77.3680],
    '121106': [27.8920, 77.3680],
    'PALWAL': [28.1487, 77.3320],
    '121102': [28.1487, 77.3320],
    'FARIDABAD': [28.4089, 77.3178],
    'DELHI': [28.6139, 77.2090],
    'GURUGRAM': [28.4595, 77.0266],
    'TIRUMANGALAM': [9.8235, 77.9866],
    '625706': [9.8235, 77.9866],
    'USILAMPATTI': [9.9650, 77.7885],
    '625532': [9.9650, 77.7885],
    'MELUR': [10.0315, 78.3385],
    '625106': [10.0315, 78.3385],
    'VADIPATTI': [10.0872, 77.9597],
    '625218': [10.0872, 77.9597],
    'DINDIGUL': [10.3624, 77.9695],
    '624001': [10.3624, 77.9695],
    'SIVAKASI': [9.4533, 77.8024],
    '626123': [9.4533, 77.8024],
    'VIRUDHUNAGAR': [9.5680, 77.9624],
    '626001': [9.5680, 77.9624],
    'THENI': [10.0104, 77.4768],
    '625531': [10.0104, 77.4768],
    'RAMANATHAPURAM': [9.3639, 78.8395],
    'PARAMAKUDI': [9.5453, 78.5906],
    'KARAIKUDI': [10.0735, 78.7732],
    'SIVAGANGA': [9.8433, 78.4809],
    'TRICHY': [10.7905, 78.7047],
    'TIRUCHIRAPPALLI': [10.7905, 78.7047],
    'SALEM': [11.6643, 78.1460],
    'COIMBATORE': [11.0168, 76.9558],
    'TIRUNELVELI': [8.7139, 77.7567],
    'TUTICORIN': [8.7642, 78.1348],
    'THOOTHUKUDI': [8.7642, 78.1348],
    'CHENNAI': [13.0827, 80.2707],
    'MADURAI': [9.9252, 78.1198],
  };

  /// Checks whether coordinates fall inside valid Indian geographic bounds (6°N–38°N, 68°E–98°E).
  static bool isValidIndiaCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.abs() < 0.01 || lng.abs() < 0.01) return false;
    return lat >= 6.0 && lat <= 38.0 && lng >= 68.0 && lng <= 98.0;
  }

  /// Resolves city/branch/pincode to known town coordinates, overriding missing,
  /// out-of-India wrong-degree entries, or generic Madurai fallback pins when a non-Madurai town is specified.
  static ({double lat, double lng, bool resolvedFromPlace})
      resolveCoordinatesForPlace({
    double? rawLat,
    double? rawLng,
    String? addressOrCity,
    String? branch,
    String? pincode,
  }) {
    final hay =
        '${addressOrCity ?? ""} ${branch ?? ""} ${pincode ?? ""}'.toUpperCase();

    List<double>? placeMatch;
    for (final entry in _cityCenters.entries) {
      if (hay.contains(entry.key)) {
        placeMatch = entry.value;
        break;
      }
    }
    if (placeMatch == null && pincode != null) {
      final pin = pincode.trim();
      if (pin.startsWith('121')) placeMatch = _cityCenters['HODAL'];
      if (pin.startsWith('624')) placeMatch = _cityCenters['DINDIGUL'];
      if (pin.startsWith('626')) placeMatch = _cityCenters['VIRUDHUNAGAR'];
      if (pin.startsWith('625')) placeMatch = _cityCenters['MADURAI'];
    }

    final validIndia = isValidIndiaCoordinate(rawLat, rawLng);
    final isGenericMaduraiFallback = validIndia &&
        (rawLat! - 9.9252).abs() < 0.015 &&
        (rawLng! - 78.1198).abs() < 0.015;

    if (validIndia && (!isGenericMaduraiFallback || placeMatch == null)) {
      return (lat: rawLat!, lng: rawLng!, resolvedFromPlace: false);
    }

    if (placeMatch != null) {
      return (lat: placeMatch[0], lng: placeMatch[1], resolvedFromPlace: true);
    }

    return (lat: defaultLat, lng: defaultLng, resolvedFromPlace: false);
  }

  /// Extracts `lat, lng` from raw text or a pasted Google Maps URL (`@lat,lng`, `q=lat,lng`, `!3dlat!4dlng`).
  static ({double lat, double lng})? extractCoordinatesFromInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final patterns = [
      RegExp(r'@(-?\d+\.\d+),\s*(-?\d+\.\d+)'),
      RegExp(r'[?&](?:q|query|ll|destination)=(-?\d+\.\d+),\s*(-?\d+\.\d+)'),
      RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
      RegExp(r'(-?\d+\.\d+)[,\s]+(-?\d+\.\d+)'),
    ];

    for (final re in patterns) {
      final m = re.firstMatch(trimmed);
      if (m != null) {
        final lat = double.tryParse(m.group(1)!);
        final lng = double.tryParse(m.group(2)!);
        if (isValidIndiaCoordinate(lat, lng)) {
          return (lat: lat!, lng: lng!);
        }
      }
    }
    return null;
  }

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

  static Future<bool> launchExternalUrl(String url) async {
    final uri = Uri.parse(url);
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


