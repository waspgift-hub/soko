class EnvConfig {
  EnvConfig._();

  /// Groq API key — provide via --dart-define=GROQ_API_KEY=... at build time.
  /// RELEASE: must be provided at build time or proxied through the server.
  static const String groqApiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );
}
