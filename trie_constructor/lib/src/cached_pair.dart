class CachedPair {
  int predictionLength;
  String context;

  CachedPair(this.predictionLength, this.context);

  @override
  bool operator ==(o) {
    return (o is CachedPair) &&
        (predictionLength == o.predictionLength) &&
        (context == o.context);
  }

  @override
  int get hashCode => predictionLength.hashCode + context.hashCode;
}
