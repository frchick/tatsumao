part of 'mypolyline_layer.dart';

@immutable
class _MyProjectedPolyline<R extends Object> with HitDetectableElement<R> {
  final MyPolyline<R> polyline;
  final List<DoublePoint> points;

  @override
  R? get hitValue => polyline.hitValue;

  const _MyProjectedPolyline._({
    required this.polyline,
    required this.points,
  });

  _MyProjectedPolyline._fromPolyline(Projection projection, MyPolyline<R> polyline)
      : this._(
          polyline: polyline,
          points: List<DoublePoint>.generate(
            polyline.points.length,
            (j) {
              final (x, y) = projection.projectXY(polyline.points[j]);
              return DoublePoint(x, y);
            },
            growable: false,
          ),
        );
}
