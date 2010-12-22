module skia.core.matrixTest;

private {
  import std.array : appender;
  import std.format : formattedWrite;
  import std.math : abs;

  import skia.core.matrix;
  import skia.core.point;

  import quickcheck._;
}

private string formatString(TL...)(string fmt, TL tl) {
  auto writer = appender!string();
  formattedWrite(writer, fmt, tl);
  return writer.data;
}


unittest {
  doRun();
}
FPoint Multiply(in Matrix m, FPoint pt) {
  auto xr = pt.x * m[0][0] + pt.y * m[0][1] + m[0][2];
  auto yr = pt.x * m[1][0] + pt.y * m[1][1] + m[1][2];
  auto zr = pt.x * m[2][0] + pt.y * m[2][1] + m[2][2];
  if (zr != 0) {
    xr /= zr;
    yr /= zr;
  }
  return FPoint(xr, yr);
}

void doRun() {
  Matrix m;
  m.setRotate(45);
  auto pts = getArbitrary!(FPoint[], size(20), minValue(0.0), maxValue(2.0), Policies.RandomizeMembers)();
  auto ptsB = pts.idup;

  m.mapPoints(pts);
  foreach(i, pt; ptsB) {
    auto mpt = Multiply(m, pt);
    assert(abs(mpt.x - pts[i].x) < 2*float.epsilon, formatString("unequal pts SSEM:%s FPUM:%s", pts[i], mpt));
    assert(abs(mpt.y - pts[i].y) < 2*float.epsilon, formatString("unequal pts SSEM:%s FPUM:%s", pts[i], mpt));
  }
}