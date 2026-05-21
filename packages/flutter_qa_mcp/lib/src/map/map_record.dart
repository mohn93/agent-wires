// packages/flutter_qa_mcp/lib/src/map/map_record.dart
class MapEntry {
  MapEntry({
    required this.fingerprint,
    this.humanLabel,
    this.creationLocation,
    this.screenContext,
    this.observationCount = 0,
    this.proposals = const [],
    this.dismissed = false,
  });

  final String fingerprint;
  String? humanLabel;
  String? creationLocation;
  String? screenContext;
  int observationCount;
  bool dismissed;
  List<ProposalRecord> proposals;

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        if (humanLabel != null) 'human_label': humanLabel,
        if (creationLocation != null) 'creation_location': creationLocation,
        if (screenContext != null) 'screen_context': screenContext,
        'observation_count': observationCount,
        if (dismissed) 'dismissed': true,
        if (proposals.isNotEmpty) 'proposals': proposals.map((p) => p.toJson()).toList(),
      };

  static MapEntry fromJson(Map<String, dynamic> json) => MapEntry(
        fingerprint: json['fingerprint'] as String,
        humanLabel: json['human_label'] as String?,
        creationLocation: json['creation_location'] as String?,
        screenContext: json['screen_context'] as String?,
        observationCount: (json['observation_count'] as num?)?.toInt() ?? 0,
        dismissed: json['dismissed'] as bool? ?? false,
        proposals: (json['proposals'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(ProposalRecord.fromJson)
                .toList() ??
            [],
      );
}

class ProposalRecord {
  ProposalRecord({
    required this.source,
    required this.label,
    required this.confidence,
    required this.firstSeen,
  });

  final String source;
  final String label;
  final double confidence;
  final DateTime firstSeen;

  Map<String, dynamic> toJson() => {
        'source': source,
        'label': label,
        'confidence': confidence,
        'first_seen': firstSeen.toIso8601String(),
      };

  static ProposalRecord fromJson(Map<String, dynamic> json) => ProposalRecord(
        source: json['source'] as String,
        label: json['label'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        firstSeen: DateTime.parse(json['first_seen'] as String),
      );
}
