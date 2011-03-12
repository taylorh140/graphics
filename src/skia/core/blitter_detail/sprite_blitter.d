module skia.core.blitter_detail.sprite_blitter;

private {
  import skia.core.bitmap;
  import skia.core.blitter;
  import skia.core.blitter_detail.blit_row_factory;
  import skia.core.color;
  import skia.core.paint;
  import guip.point;
  import guip.rect;
}

class SpriteBlitter : Blitter {
  //! TODO: stub
  static SpriteBlitter CreateD16(Bitmap device, in Bitmap source,
                                 Paint paint, IPoint ioff) {
    assert(device.config == Bitmap.Config.RGB_565);
    assert(0, "unimplemented");
  }

  static SpriteBlitter CreateD32(Bitmap device, in Bitmap source,
                                 Paint paint, IPoint ioff) {
    assert(device.config == Bitmap.Config.ARGB_8888);

    auto alpha = paint.color.a;
    switch (source.config) {
    case Bitmap.Config.ARGB_8888:
      if ((paint.xferMode /* || paint.filter*/)
          && (alpha == 255)) {
        // return new Sprite_D32_S32A_XferFilter(source, paint);
      } else
        return createSpriteBlitter_D32_S32(device, source, ioff, alpha);
      break;

    default:
      break;
    }
    return null;
  }

  this (Bitmap device, in Bitmap source, IPoint ioff, ubyte alpha) {
    this.device = device;
    this.source = source;
    this.ioff = ioff;
    this.alpha = alpha;
  }

protected:

  override void blitFH(float y, float xStart, float xEnd) {
    assert(false, "how did we get here?");
  }
  override void blitMask(float x, float y, in Bitmap mask) {
    assert(false, "how did we get here?");
  }

  Bitmap device;
  const Bitmap source;
  IPoint ioff;
  ubyte alpha;
}

static SpriteBlitter createSpriteBlitter_D32_S32(Bitmap device, in Bitmap source,
                                   IPoint ioff, ubyte alpha) {
  if (alpha == 255) {
    if (!source.opaque)
      return new Sprite_D32_S32!(S32A_Opaque_BlitRow32)(device, source, ioff, alpha);
    else
      return new Sprite_D32_S32!(S32_Opaque_BlitRow32)(device, source, ioff, alpha);
  } else {
    if (!source.opaque)
      return new Sprite_D32_S32!(S32A_Blend_BlitRow32)(device, source, ioff, alpha);
    else
      return new Sprite_D32_S32!(S32_Blend_BlitRow32)(device, source, ioff, alpha);
  }
}

class Sprite_D32_S32(alias blitRow) : SpriteBlitter {
public:
  this (Bitmap device, in Bitmap source, IPoint ioff, ubyte alpha) {
    super(device, source, ioff, alpha);
    assert(this.source.config == Bitmap.Config.ARGB_8888);
  }

  override void blitRect(IRect rect) {
    assert(!rect.empty);
    auto curTop = rect.top;
    while (curTop < rect.bottom) {
      auto dst = this.device.getRange!(PMColor)(rect.left, rect.right, curTop);
      auto src = this.source.getRangeConst!(const(PMColor))(
        rect.left - this.ioff.x, rect.right - this.ioff.x, curTop - this.ioff.y);
      blitRow(dst, src, this.alpha);
      ++curTop;
    }
  }
}
