Future<void> sendWebRelayPost(String endpoint, String payload) async {
  // No-op on non-JS VM/native targets; native HttpClient handles non-web.
}
