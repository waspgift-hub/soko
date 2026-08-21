/// Country metadata for the phone-number field.
///
/// [dial] is the international calling code without the leading `+`; the UI
/// renders it as `+255`. Tanzania is first because it is the default market.
class AuthCountry {
  const AuthCountry({
    required this.name,
    required this.flag,
    required this.dial,
    required this.placeholder,
  });

  final String name;
  final String flag;
  final String dial;
  final String placeholder;

  String get displayDial => '+$dial';
}

const List<AuthCountry> kAuthCountries = <AuthCountry>[
  AuthCountry(name: 'Tanzania', flag: '🇹🇿', dial: '255', placeholder: '7XX XXX XXX'),
  AuthCountry(name: 'Kenya', flag: '🇰🇪', dial: '254', placeholder: '7XX XXX XXX'),
  AuthCountry(name: 'Uganda', flag: '🇺🇬', dial: '256', placeholder: '7XX XXX XXX'),
  AuthCountry(name: 'Rwanda', flag: '🇷🇼', dial: '250', placeholder: '7XX XXX XXX'),
  AuthCountry(name: 'Burundi', flag: '🇧🇮', dial: '257', placeholder: '7X XX XX XX'),
  AuthCountry(name: 'DR Congo', flag: '🇨🇩', dial: '243', placeholder: '8XX XXX XXX'),
  AuthCountry(name: 'Zambia', flag: '🇿🇲', dial: '260', placeholder: '9X XXX XXX'),
  AuthCountry(name: 'Malawi', flag: '🇲🇼', dial: '265', placeholder: '9XX XXX XXX'),
  AuthCountry(name: 'Mozambique', flag: '🇲🇿', dial: '258', placeholder: '8X XXX XXX'),
  AuthCountry(name: 'Ethiopia', flag: '🇪🇹', dial: '251', placeholder: '9XX XXX XXX'),
  AuthCountry(name: 'Somalia', flag: '🇸🇴', dial: '252', placeholder: '6X XXX XXX'),
  AuthCountry(name: 'South Africa', flag: '🇿🇦', dial: '27', placeholder: '7X XXX XXXX'),
  AuthCountry(name: 'Nigeria', flag: '🇳🇬', dial: '234', placeholder: '8XX XXX XXXX'),
  AuthCountry(name: 'Ghana', flag: '🇬🇭', dial: '233', placeholder: '2X XXX XXXX'),
];