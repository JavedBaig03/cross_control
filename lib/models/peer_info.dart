class PeerInfo {
  final String key;
  final String name;
  final String ip;
  final int port;
  final String os;
  final DateTime lastSeen;

  PeerInfo({
    required this.key,
    required this.name,
    required this.ip,
    required this.port,
    required this.os,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'ip': ip,
        'port': port,
        'os': os,
      };

  factory PeerInfo.fromJson(Map<String, dynamic> json, [String? fallbackIp]) {
    return PeerInfo(
      key: json['key'] as String? ?? 'UNKNOWN',
      name: json['name'] as String? ?? 'Remote Device',
      ip: (json['ip'] as String?)?.isNotEmpty == true
          ? (json['ip'] as String)
          : (fallbackIp ?? '127.0.0.1'),
      port: json['port'] as int? ?? 42070,
      os: json['os'] as String? ?? 'unknown',
      lastSeen: DateTime.now(),
    );
  }

  PeerInfo copyWith({
    String? key,
    String? name,
    String? ip,
    int? port,
    String? os,
    DateTime? lastSeen,
  }) {
    return PeerInfo(
      key: key ?? this.key,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      os: os ?? this.os,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
