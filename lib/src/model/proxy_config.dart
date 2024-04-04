enum ProxyType { http, socks5, socks4, direct }

class ProxyConfig {
  ProxyType type;

  String address;

  String? username;

  String? password;

  ProxyConfig({required this.type, required this.address, this.username, this.password});

  static String Function(Uri) toFindProxy(ProxyConfig? proxyConfig) {
    return (_) {
      if (proxyConfig == null) {
        return 'DIRECT';
      }

      String proxyAddress;
      if ((proxyConfig.username?.trim().isEmpty ?? true) && (proxyConfig.password?.trim().isEmpty ?? true)) {
        proxyAddress = proxyConfig.address;
      } else {
        proxyAddress = '${proxyConfig.username ?? ''}:${proxyConfig.password ?? ''}@${proxyConfig.address}';
      }

      switch (proxyConfig.type) {
        case ProxyType.http:
          return 'PROXY $proxyAddress; DIRECT';
        case ProxyType.socks5:
          return 'SOCKS5 $proxyAddress; DIRECT';
        case ProxyType.socks4:
          return 'SOCKS4 $proxyAddress; DIRECT';
        case ProxyType.direct:
        default:
          return 'DIRECT';
      }
    };
  }
}
