import '../models/borrower_model.dart';
import '../models/loan_model.dart';

enum SearchFieldScope {
  all('All Fields'),
  name('Customer Name'),
  mobile('Mobile No'),
  loanOrApp('Loan / App No'),
  areaOrPin('Area / Pincode'),
  kycId('PAN / CERSAI');

  const SearchFieldScope(this.label);
  final String label;
}

enum CollectionCategory {
  regular('REGULAR', 'Regular (0 DPD)'),
  dpd('DPD', 'DPD / SMA (1-89)'),
  npa('NPA', 'NPA (90+ DPD)');

  const CollectionCategory(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static CollectionCategory fromLoan(LoanModel loan) {
    final cls = (loan.assetClassification ?? '').trim().toUpperCase();
    if (loan.dpd >= 90 ||
        loan.agingBucket == AgingBucket.dpd90Plus ||
        cls.contains('NPA') ||
        cls.contains('SUB') ||
        cls.contains('DOUBT') ||
        cls.contains('LOSS')) {
      return CollectionCategory.npa;
    }
    if (loan.dpd > 0 || loan.agingBucket != AgingBucket.current) {
      return CollectionCategory.dpd;
    }
    return CollectionCategory.regular;
  }
}

class OmniSearchEngine {
  OmniSearchEngine._();

  static String _digitsOnly(String input) =>
      input.replaceAll(RegExp(r'[^0-9]'), '');

  static bool matches({
    required LoanModel loan,
    BorrowerModel? borrower,
    required String query,
    SearchFieldScope scope = SearchFieldScope.all,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final qDigits = _digitsOnly(q);
    final nameHay =
        '${borrower?.fullName ?? ""} ${borrower?.coApplicantName ?? ""} ${borrower?.businessName ?? ""}'
            .toLowerCase();
    final mobileRaw =
        '${borrower?.mobilePrimary ?? ""} ${borrower?.mobileAlternate ?? ""}';
    final mobileDigits = _digitsOnly(mobileRaw);
    final loanAppHay = '${loan.loanId} ${loan.applicationNo}'.toLowerCase();
    final areaHay =
        '${borrower?.addressText ?? ""} ${borrower?.branch ?? ""} ${borrower?.pincode ?? ""}'
            .toLowerCase();
    final kycHay =
        '${borrower?.panNumber ?? ""} ${borrower?.cersaiId ?? ""} ${borrower?.ckycId ?? ""}'
            .toLowerCase();

    bool matchMobile() {
      if (mobileRaw.toLowerCase().contains(q)) return true;
      if (qDigits.length >= 4 && mobileDigits.contains(qDigits)) return true;
      return false;
    }

    switch (scope) {
      case SearchFieldScope.name:
        return nameHay.contains(q);
      case SearchFieldScope.mobile:
        return matchMobile();
      case SearchFieldScope.loanOrApp:
        return loanAppHay.contains(q);
      case SearchFieldScope.areaOrPin:
        return areaHay.contains(q);
      case SearchFieldScope.kycId:
        return kycHay.contains(q);
      case SearchFieldScope.all:
        return nameHay.contains(q) ||
            matchMobile() ||
            loanAppHay.contains(q) ||
            areaHay.contains(q) ||
            kycHay.contains(q);
    }
  }
}
