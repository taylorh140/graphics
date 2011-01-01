module skia.core.stroke;

private {
  import std.traits : isDynamicArray, Unqual;
  import std.math : abs, SQRT1_2;

  import skia.core.paint;
  import skia.core.path;
  import skia.core.point;
  import skia.core.stroke_detail._;
  import skia.core.edge_detail.algo;
  import skia.math.fixed_ary;
}

//! TODO: implement joiner
struct Stroke {
  const Paint paint;
  float radius;
  //  float invMiterLimit;

  FVector prevNormal;
  Path outer;
  Path inner;
  Path result;

  Capper capper;
  Joiner joiner;
  bool fillSrcPath;

  this(in Paint paint, float width) {
    assert(width > 0);
    this.paint = paint;
    this.radius = width * 0.5;
    this.capper = getCapper(paint.capStyle);
    this.joiner = getJoiner(paint.joinStyle);
    this.fillSrcPath = paint.fillStyle == Paint.Fill.FillAndStroke;
  }

  void done() {
    if (!this.outer.empty) {
      this.finishContour(true);
    }
  }

  void close(bool capClose) {
    this.finishContour(capClose);
  }

  FVector getNormal(FPoint pt1, FPoint pt2) {
    FVector normal = pt1 - pt2;
    normal.setLength(radius);
    normal.rotateCCW();
    return normal;
  }

  Path strokePath(in Path path) {
    if (radius <= 0)
      return Path();

    path.forEach((const Path.Verb verb, const FPoint[] pts) {
      final switch(verb) {
      case Path.Verb.Move:
        this.moveTo(pts[0]);
        break;
      case Path.Verb.Line:
        this.lineTo(fixedAry!2(pts));
        break;
      case Path.Verb.Quad:
        this.quadTo(fixedAry!3(pts));
        break;
      case Path.Verb.Cubic:
        this.cubicTo(fixedAry!4(pts));
        break;
      case Path.Verb.Close:
        this.close(pts.length != 0);
      }
      });

    this.done();
    if (this.fillSrcPath) {
      this.result.addPath(path);
    }
    return this.result;
  }

  void join(FPoint pt, FVector normalAfter) {
    if (!this.outer.empty)
      this.joiner(pt, this.prevNormal, normalAfter, this.inner, this.outer);
    else {
      this.inner.moveTo(pt - normalAfter);
      this.outer.moveTo(pt + normalAfter);
    }
  }

  void finishContour(bool capClose) {
    if (capClose) {
      FVector normal = this.getNormal(this.outer.pointsRetro[0], this.outer.pointsRetro[1]);
      FPoint pt = (this.inner.lastPoint + this.outer.lastPoint) * 0.5;
      this.capper(pt, normal, this.outer);

      this.outer.reversePathTo(this.inner);

      normal = this.getNormal(this.outer.points[0], this.outer.points[1]);
      pt = (this.outer.pointsRetro[0] + this.outer.points[0]) * 0.5;
      this.capper(pt, normal, this.outer);
    } else {
      this.outer.moveTo(this.inner.lastPoint);
      this.outer.reversePathTo(this.inner);
    }
    this.outer.close();

    this.result.addPath(this.outer);
    this.inner.reset();
    this.outer.reset();
  }

  void moveTo(FPoint pt) {
    if (!this.outer.empty) {
      this.finishContour(true);
    }
  }

  private bool degenerate(FPoint pt1, FPoint pt2) {
    enum tol = 1e-3;
    return distance(pt1, pt2) < tol;
  }

  void lineTo(FPoint[2] pts) {
    //! degenerate line
    if (degenerate(pts[0], pts[1])) {
      return;
    }
    auto normal = getNormal(pts[0], pts[1]);
    this.join(pts[0], normal);
    this.prevNormal = this.__lineTo(pts, normal);
  }

  FVector __lineTo(FPoint[2] pts, FVector normal) {
    this.outer.lineTo(pts[1] + normal);
    this.inner.lineTo(pts[1] - normal);
    return normal;
  }

  void quadTo(FPoint[3] pts) {
    //! degenerate line
    if (degenerate(pts[0], pts[1])) {
      this.lineTo(fixedAry!2(pts[0], pts[2]));
      return;
    }

    auto normalAB = getNormal(pts[0], pts[1]);
    this.join(pts[0], normalAB);
    this.prevNormal = this.__quadTo(pts, normalAB);
  }

  FVector __quadTo(FPoint[3] pts, FVector normalAB) {
    if (degenerate(pts[1], pts[2])) {
      return this.__lineTo(fixedAry!2(pts[0], pts[1]), normalAB);
    }

    auto normalBC = getNormal(pts[1], pts[2]);
    if (normalsTooCurvy(normalAB, normalBC)) {
      auto ptss = splitBezier(pts, 0.5f);
      auto normal1BC = this.__quadTo(ptss[0], normalAB);
      return this.__quadTo(ptss[1], normal1BC);
    } else {
      auto normalB = getNormal(pts[0], pts[2]);
      this.outer.quadTo(pts[1] + normalB, pts[2] + normalBC);
      this.inner.quadTo(pts[1] - normalB, pts[2] - normalBC);
      return normalBC;
    }
  }

  void cubicTo(FPoint[4] pts) {
    if (degenerate(pts[0], pts[1])) {
      this.quadTo(fixedAry!3(pts[0], pts[2], pts[3]));
      return;
    }

    auto normalAB = getNormal(pts[0], pts[1]);
    this.join(pts[0], normalAB);
    this.prevNormal = this.__cubicTo(pts, normalAB);
  }

  FVector __cubicTo(FPoint[4] pts, FVector normalAB) {
    if (degenerate(pts[2], pts[3])) {
      this.__quadTo(fixedAry!3(pts[0], pts[1], pts[2]), normalAB);
    }

    auto normalCD = getNormal(pts[2], pts[3]);
    auto normalB = getNormal(pts[0], pts[2]);
    auto normalC = getNormal(pts[1], pts[3]);
    if (normalsTooCurvy(normalAB, normalCD)
        || normalsTooCurvy(normalAB, normalB)
        || normalsTooCurvy(normalC, normalCD)) {
      auto ptss = splitBezier(pts, 0.5f);
      auto normal1CD = this.__cubicTo(ptss[0], normalAB);
      return this.__cubicTo(ptss[1], normal1CD);
    } else {
      this.outer.cubicTo(pts[1] + normalB, pts[2] + normalC, pts[3] + normalCD);
      this.inner.cubicTo(pts[1] - normalB, pts[2] - normalC, pts[3] - normalCD);
      return normalCD;
    }
  }

  static bool normalsTooCurvy(FVector normal1, FVector normal2) {
    const limit = SQRT1_2 * normal1.length * normal2.length;
    return dotProduct(normal1, normal2) <= limit;
  }
}