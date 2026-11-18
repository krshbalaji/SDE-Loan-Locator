import 'package:flutter_test/flutter_test.dart';
import 'package:loan_locator_app/main.dart';
import 'package:loan_locator_app/services/firestore_loan_service.dart';

void main() {
  testWidgets('App boots in Demo Mode, signs into Master Dashboard, and switches tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      LoanLocatorApp(
        useFirebase: false,
        repository: InMemoryDemoLoanService(),
      ),
    );
    await tester.pumpAndSettle();

    // Login screen renders Saro Devi Enterprises branding & Demo Mode banner
    expect(find.text('Saro Devi Enterprises'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);

    // Sign in as Master via default credentials
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    // Master Dashboard KPIs render
    expect(find.text('Deployed Capital'), findsOneWidget);
    expect(find.text('PAR > 30 Days'), findsOneWidget);

    // Navigate to Collections Queue tab
    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();
    expect(find.text('EARLY WARNING'), findsWidgets);

    // Navigate to Loans tab & open Loan 360° file
    await tester.tap(find.text('Loans'));
    await tester.pumpAndSettle();
    expect(find.text('New Loan'), findsOneWidget);
  });
}
