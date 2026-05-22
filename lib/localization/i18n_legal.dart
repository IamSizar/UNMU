// Legal screen chrome (titles). The actual Privacy Policy / Terms BODY text
// lives as full English + Arabic markdown constants in
// lib/screens/legal/legal_content.dart (kPrivacyPolicy{En,Ar} /
// kTermsOfService{En,Ar}) — long-form prose is kept as locale-selected
// documents rather than per-paragraph keys. Only the app-bar titles are
// routed through the central .tr table here.

const Map<String, String> legalEn = {
  'legal.privacyTitle': 'Privacy Policy',
  'legal.termsTitle': 'Terms of Service',
};

const Map<String, String> legalAr = {
  'legal.privacyTitle': 'سياسة الخصوصية',
  'legal.termsTitle': 'شروط الخدمة',
};
