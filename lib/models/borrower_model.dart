import '../utils/indian_formatters.dart';

/// Table 1: `borrowers` — Customer master, KYC, and geo-coordinates.
class BorrowerModel {
  const BorrowerModel({
    required this.borrowerId,
    required this.fullName,
    required this.mobilePrimary,
    this.mobileAlternate,
    this.businessName,
    this.panNumber = '',
    this.aadhaarMasked = '',
    this.gstin,
    this.bankAccountNo,
    this.bankIfsc,
    this.kycDocUrls = const [],
    required this.addressText,
    required this.latitude,
    required this.longitude,
    this.geohash = '',
    this.geoVerified = false,
    required this.assignedAgentId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String borrowerId;
  final String fullName;
  final String mobilePrimary;
  final String? mobileAlternate;
  final String? businessName;
  final String panNumber;
  final String aadhaarMasked;
  final String? gstin;
  final String? bankAccountNo;
  final String? bankIfsc;
  final List<String> kycDocUrls;
  final String addressText;
  final double latitude;
  final double longitude;
  final String geohash;
  final bool geoVerified;
  final String assignedAgentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasValidCoordinates =>
      latitude.abs() > 0.0001 &&
      longitude.abs() > 0.0001 &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  BorrowerModel copyWith({
    String? borrowerId,
    String? fullName,
    String? mobilePrimary,
    String? mobileAlternate,
    String? businessName,
    String? panNumber,
    String? aadhaarMasked,
    String? gstin,
    String? bankAccountNo,
    String? bankIfsc,
    List<String>? kycDocUrls,
    String? addressText,
    double? latitude,
    double? longitude,
    String? geohash,
    bool? geoVerified,
    String? assignedAgentId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BorrowerModel(
      borrowerId: borrowerId ?? this.borrowerId,
      fullName: fullName ?? this.fullName,
      mobilePrimary: mobilePrimary ?? this.mobilePrimary,
      mobileAlternate: mobileAlternate ?? this.mobileAlternate,
      businessName: businessName ?? this.businessName,
      panNumber: panNumber ?? this.panNumber,
      aadhaarMasked: aadhaarMasked ?? this.aadhaarMasked,
      gstin: gstin ?? this.gstin,
      bankAccountNo: bankAccountNo ?? this.bankAccountNo,
      bankIfsc: bankIfsc ?? this.bankIfsc,
      kycDocUrls: kycDocUrls ?? this.kycDocUrls,
      addressText: addressText ?? this.addressText,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geohash: geohash ?? this.geohash,
      geoVerified: geoVerified ?? this.geoVerified,
      assignedAgentId: assignedAgentId ?? this.assignedAgentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory BorrowerModel.fromMap(Map<String, dynamic> map, {String? id}) {
    return BorrowerModel(
      borrowerId: id ?? (map['borrower_id'] as String? ?? ''),
      fullName: map['full_name'] as String? ?? '',
      mobilePrimary: map['mobile_primary'] as String? ?? '',
      mobileAlternate: map['mobile_alternate'] as String?,
      businessName: map['business_name'] as String?,
      panNumber: map['pan_number'] as String? ?? '',
      aadhaarMasked: map['aadhaar_masked'] as String? ?? '',
      gstin: map['gstin'] as String?,
      bankAccountNo: map['bank_account_no'] as String?,
      bankIfsc: map['bank_ifsc'] as String?,
      kycDocUrls: (map['kyc_doc_urls'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      addressText: map['address_text'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      geohash: map['geohash'] as String? ?? '',
      geoVerified: map['geo_verified'] as bool? ?? false,
      assignedAgentId: map['assigned_agent_id'] as String? ?? '',
      createdAt: IndianFormatters.parseDate(map['created_at']),
      updatedAt: IndianFormatters.parseDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() => {
        'borrower_id': borrowerId,
        'full_name': fullName,
        'mobile_primary': mobilePrimary,
        'mobile_alternate': mobileAlternate,
        'business_name': businessName,
        'pan_number': panNumber,
        'aadhaar_masked': aadhaarMasked,
        'gstin': gstin,
        'bank_account_no': bankAccountNo,
        'bank_ifsc': bankIfsc,
        'kyc_doc_urls': kycDocUrls,
        'address_text': addressText,
        'latitude': latitude,
        'longitude': longitude,
        'geohash': geohash,
        'geo_verified': geoVerified,
        'assigned_agent_id': assignedAgentId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
