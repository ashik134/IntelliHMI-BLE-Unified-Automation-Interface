/// The permanent biometric credential (spec sections 10-11): a face
/// embedding vector, never a raw image. [modelVersion] lets a future
/// embedding-model change be detected instead of silently comparing
/// incompatible embedding spaces (spec section 25) — see
/// FaceMatchingService, which excludes templates whose modelVersion
/// doesn't match the current embedding model.
class FaceTemplate {
  const FaceTemplate({
    required this.templateId,
    required this.operatorId,
    required this.embedding,
    required this.modelVersion,
    required this.createdAt,
    this.schemaVersion = 1,
  });

  final String templateId;
  final String operatorId;

  /// L2-normalized embedding vector (see FaceEmbeddingService).
  final List<double> embedding;

  final String modelVersion;
  final DateTime createdAt;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
    'templateId': templateId,
    'operatorId': operatorId,
    'embedding': embedding,
    'modelVersion': modelVersion,
    'createdAt': createdAt.toIso8601String(),
    'schemaVersion': schemaVersion,
  };

  factory FaceTemplate.fromJson(Map<String, dynamic> json) {
    return FaceTemplate(
      templateId: json['templateId'] as String,
      operatorId: json['operatorId'] as String,
      embedding: (json['embedding'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
      modelVersion: json['modelVersion'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      schemaVersion: (json['schemaVersion'] as int?) ?? 1,
    );
  }
}
