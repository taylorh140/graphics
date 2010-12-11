module skia.core.draw;

private {
  import skia.core.bitmap;
  import skia.core.bounder;
  import skia.core.blitter;
  import skia.core.color;
  import skia.core.device;
  import skia.core.matrix;
  import skia.core.paint;
  import skia.core.path;
  import skia.core.region;
  import skia.core.rect;
  import Scan = skia.core.scan;
}

// debug=PRINTF;
debug(PRINTF) private import std.stdio : printf;

struct Draw {
public:
  Bitmap bitmap;
  Matrix matrix;
  Region clip;
  Device device;
  Bounder bounder;
  // DrawProcs drawProcs;

  this(Bitmap bitmap) {
    assert(bitmap);
    this.bitmap = bitmap;
  }

  this(Bitmap bitmap, in Matrix matrix, in Region clip) {
    this(bitmap);
    this.matrix = matrix;
    this.clip = clip;
  }

  void drawPaint(Paint paint) {
    if (this.clip.empty
        || this.bounder && !this.bounder.doIRect(this.bitmap.bounds))
      return;

    /**
     *  If we don't have a shader (i.e. we're just a solid color) we
     *  may be faster to operate directly on the device bitmap, rather
     *  than invoking a blitter. Esp. true for xfermodes, which
     *  require a colorshader to be present, which is just redundant
     *  work. Since we're drawing everywhere in the clip, we don't
     *  have to worry about antialiasing.
     */
    /*
    uint32_t procData = 0;  // to avoid the warning
    BitmapXferProc proc = ChooseBitmapXferProc(*fBitmap, paint, &procData);
    if (proc) {
        if (D_Dst_BitmapXferProc == proc)// nothing to do
            return;

        SkRegion::Iterator iter(*fClip);
        while (!iter.done()) {
            CallBitmapXferProc(*fBitmap, iter.rect(), proc, procData);
            iter.next();
        }
    } else {
    */
    Scan.fillIRect(this.bitmap.bounds, this.clip, this.getBlitter(paint));
  }

  private Blitter getBlitter(Paint paint) {
    return Blitter.Choose(this.bitmap, this.matrix, paint);
  }

  void drawColor(in Color c) {
    this.bitmap.eraseColor(PMColor(c));
  }

  void drawPath(in Path path, Paint paint) {
    if (this.clip.empty
        || this.bounder && !this.bounder.doIRect(this.bitmap.bounds))
      return;

    auto transPath = path.transformed(this.matrix);
    Scan.fillPath(transPath, this.clip, this.getBlitter(paint));
  }

  void drawRect(in IRect rect, Paint paint) {
    if (this.clip.empty
        || this.bounder && !this.bounder.doIRect(this.bitmap.bounds))
      return;

    Scan.fillIRect(rect, this.clip, this.getBlitter(paint));
  }
  //  void drawPath(in Path path, in Paint paint, in Matrix matrix, bool pathMutable) {
  //  }


  /++

  void    drawPoints(SkCanvas::PointMode, size_t count, const SkPoint[],
		     const SkPaint&) const;
  void    drawRect(const SkRect&, const SkPaint&) const;
  /*  To save on mallocs, we allow a flag that tells us that srcPath is
      mutable, so that we don't have to make copies of it as we transform it.
  */
  void    drawPath(const SkPath& srcPath, const SkPaint&,
		   const SkMatrix* prePathMatrix, bool pathIsMutable) const;
  void    drawBitmap(const SkBitmap&, const SkMatrix&, const SkPaint&) const;
  void    drawSprite(const SkBitmap&, int x, int y, const SkPaint&) const;
  void    drawText(const char text[], size_t byteLength, SkScalar x,
		   SkScalar y, const SkPaint& paint) const;
  void    drawPosText(const char text[], size_t byteLength,
		      const SkScalar pos[], SkScalar constY,
		      int scalarsPerPosition, const SkPaint& paint) const;
  void    drawTextOnPath(const char text[], size_t byteLength,
			 const SkPath&, const SkMatrix*, const SkPaint&) const;
  void    drawVertices(SkCanvas::VertexMode mode, int count,
		       const SkPoint vertices[], const SkPoint textures[],
		       const SkColor colors[], SkXfermode* xmode,
		       const uint16_t indices[], int ptCount,
		       const SkPaint& paint) const;

  void drawPath(const SkPath& src, const SkPaint& paint) const {
    this->drawPath(src, paint, NULL, false);
  }

  /** Helper function that creates a mask from a path and an optional maskfilter.
      Note however, that the resulting mask will not have been actually filtered,
      that must be done afterwards (by calling filterMask). The maskfilter is provided
      solely to assist in computing the mask's bounds (if the mode requests that).
  */
  static bool DrawToMask(const SkPath& devPath, const SkIRect* clipBounds,
			 SkMaskFilter* filter, const SkMatrix* filterMatrix,
			 SkMask* mask, SkMask::CreateMode mode);

private:
  void    drawText_asPaths(const char text[], size_t byteLength,
			   SkScalar x, SkScalar y, const SkPaint&) const;
  void    drawDevMask(const SkMask& mask, const SkPaint&) const;
  void    drawBitmapAsMask(const SkBitmap&, const SkPaint&) const;

public:
  const Bitmap mBitmap;        // required
  const Matrix mMatrix;        // required
  const Region mClip;          // required
  Device       mDevice;        // optional
  Bounder      mBounder;       // optional
  DrawProcs    mProcs;         // optional

#ifdef SK_DEBUG
    void    validate(int width, int height) const;
#endif
+/
};
