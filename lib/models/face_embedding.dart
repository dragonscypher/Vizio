class FaceEmbedding {
  final String id;
  final List<double> embedding;

  FaceEmbedding({required this.id, required this.embedding});

  factory FaceEmbedding.fromJson(Map<String, dynamic> json) {
    return FaceEmbedding(
      id: json['id'],
      embedding: List<double>.from(json['embedding']),
    );
  }
}
