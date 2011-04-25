module skia.core.fonthost.freetype;

import core.atomic, core.sync.mutex, core.sync.rwmutex, std.exception, std.traits, std.c.string : memcpy;
import freetype.freetype, freetype.outline, guip.bitmap, guip.point, guip.size;
import skia.core.glyph, skia.core.fonthost.fontconfig, skia.core.paint, skia.core.path;

shared FT_Face _face;
shared FreeType _freeType;

@property shared(FreeType) freeType() {
  if (_freeType is null) {
    auto ft = new FreeType();
    if (cas(&_freeType, cast(FreeType)null, ft))
      _freeType.init();
  }
  return _freeType;
}

private synchronized class FreeType {
  ~this() {
    foreach(k, v; faces)
      FT_Done_Face(cast(FT_Face)v);
    FT_Done_FreeType(cast(FT_Library)library);
    _freeType = null;
  }

  void init() {
    enforce(!FT_Init_FreeType(cast(FT_Library*)&library),
      new Exception("Error during initialization of FreeType"));
  }

  shared(FT_Face) getFace(string path) {
    return faces.get(path, loadFace(path));
  }

  shared(FT_Face) loadFace(string path) {
    shared(FT_Face) face;
    enforce(!FT_New_Face(cast(FT_Library)library, toStringz(path), 0, cast(FT_Face*)&face));
    faces[path] = face;
    return face;
  }

  FT_Library library;
  FT_Face[string] faces;
}

enum Scale26D6 = 1.0f / 64;
FPoint ScaleFT_Vector(FT_Vector vec) {
  return FPoint(vec.x, vec.y) * Scale26D6;
}

shared(GlyphStore) _glyphStore;

@property shared(GlyphStore) glyphStore() {
  if (_glyphStore is null) {
    auto gs = new GlyphStore();
    cas(&_glyphStore, cast(GlyphStore)null, gs);
  }
  return _glyphStore;
}

synchronized class GlyphStore {
  shared(Data) getData(TextPaint paint) {
    // TODO: @@BUG@@ need paint.fontSize in hash
    return data.get(paint.typeFace.filename, newData(paint));
  }

  shared(Data) newData(TextPaint paint) {
    shared(Data) d;
    d.glyphs[0] = Glyph(); // HACK needed to force creation of internal AA
    d.face = freeType.getFace(paint.typeFace.filename);
    enforce(!FT_Set_Char_Size(cast(FT_Face)d.face, 0, to!FT_F26Dot6(paint.fontSize*64), 96, 96));
    d.mtx = new shared(ReadWriteMutex)();
    data[paint.typeFace.filename] = d;
    return d;
  }

  struct Data {
    Glyph[dchar] glyphs;
    FT_Face face;
    ReadWriteMutex mtx;
  }

  // TODO: need full hash, TypeFace doesn't work as key
  Data[string] data;
}

GlyphCache getGlyphCache(TextPaint paint) {
  auto typeFace = paint.typeFace.valid()
    ? paint.typeFace
    : TypeFace.defaultFace();
  assert(typeFace.valid());
  return GlyphCache(paint, glyphStore.getData(paint));
}

struct GlyphCache {
  TextPaint paint;
  shared(GlyphStore.Data) data;

  GlyphStream glyphStream(string text, Glyph.LoadFlag loadFlags) {
    return GlyphStream(text, loadFlags, &this);
  }
}

struct GlyphStream {
  alias int delegate(const ref Glyph) GlyphDg;

  int opApply(GlyphDg dg) {
    if (text.length == 0)
      return 0;
    auto reader = (cast(ReadWriteMutex)cache.data.mtx).reader;
    reader.lock();
    scope(exit) { reader.unlock(); }

    foreach(dchar c; text) {
      auto gl = getGlyph(c, reader);
      auto res = dg(gl); if (res) return res;
    }
    return 0;
  }

  Glyph getGlyph(dchar c, ref ReadWriteMutex.Reader reader) {
    auto cached = cast(Glyph*)(c in cache.data.glyphs);

    if (cached is null || (cached.loaded & loadFlags) != 0) {
      reader.unlock();
      auto writer = (cast(ReadWriteMutex)cache.data.mtx).writer;
      writer.lock();
      scope(exit) { writer.unlock(); reader.lock(); }

      if (cached is null) {
        std.stdio.writeln("new glyph ", c);
        cache.data.glyphs[c] = Glyph();
        cached = cast(Glyph*)(c in cache.data.glyphs);
      }

      auto charIdx = FT_Get_Char_Index(cast(FT_Face)cache.data.face, c);
      foreach(e; EnumMembers!(Glyph.LoadFlag)) {
        if ((loadFlags & e) && !(cached.loaded & e))
          updateGlyph!(e)(cast(FT_Face)cache.data.face, cached, charIdx);
      }
    }
    return *cached;
  }

  string text;
  Glyph.LoadFlag loadFlags;
  private GlyphCache* cache;
}

private:

void updateGlyph(Glyph.LoadFlag f : Glyph.LoadFlag.NoFlag)(FT_Face face, Glyph* glyph, FT_UInt charIdx) {
}

void updateGlyph(Glyph.LoadFlag f : Glyph.LoadFlag.Metrics)(FT_Face face, Glyph* glyph, FT_UInt charIdx) {
  enforce(!FT_Load_Glyph(face, charIdx, FT_LOAD.NO_BITMAP));

  glyph.advance = ScaleFT_Vector(face.glyph.advance);
  glyph.lsbDelta = face.glyph.lsb_delta * Scale26D6;
  glyph.rsbDelta = face.glyph.rsb_delta * Scale26D6;
  glyph.size = FSize(face.glyph.metrics.width * Scale26D6, face.glyph.metrics.height * Scale26D6);
  std.stdio.writeln("glyph adv", glyph.rsbDelta, "|", glyph.size.width);
  glyph.loaded |= Glyph.LoadFlag.Metrics;
}

void updateGlyph(Glyph.LoadFlag f : Glyph.LoadFlag.Bitmap)(FT_Face face, Glyph* glyph, FT_UInt charIdx) {
  enforce(!FT_Load_Glyph(face, charIdx, FT_LOAD.Render));

  auto w = face.glyph.bitmap.width;
  auto h = face.glyph.bitmap.rows;
  glyph.bmp.setConfig(Bitmap.Config.A8, w, h);
  glyph.bmp.getBuffer!(ubyte)()[] = face.glyph.bitmap.buffer[0 .. w * h];
  glyph.bmpPos = FPoint(face.glyph.bitmap_left, -face.glyph.bitmap_top);

  glyph.loaded |= Glyph.LoadFlag.Bitmap;
}

void updateGlyph(Glyph.LoadFlag f : Glyph.LoadFlag.Path)(FT_Face face, Glyph* glyph, FT_UInt charIdx) {
  enforce(!FT_Load_Glyph(face, charIdx, FT_LOAD.NO_BITMAP));

  glyph.path.reset();
  auto cbs = outlineCallbacks();
  enforce(!FT_Outline_Decompose(&face.glyph.outline, &cbs, &glyph.path));
  glyph.path.close();

  glyph.loaded |= Glyph.LoadFlag.Path;
}

/*
 * Callback for transforming freetype outlines to paths.
 */
FT_Outline_Funcs outlineCallbacks() {
    FT_Outline_Funcs funcs;

    funcs.move_to = &moveTo;
    funcs.line_to = &lineTo;
    funcs.conic_to = &quadTo;
    funcs.cubic_to = &cubicTo;
    funcs.shift = 0;
    funcs.delta = 0;
    return funcs;
}

FPoint ConvFT_Vector(const FT_Vector* v) {
  auto fp = ScaleFT_Vector(*v);
  fp.y = -fp.y;
  return fp;
}
extern(C):

int moveTo(const FT_Vector* to, void* user) {
  auto path = cast(Path*)user;
  path.close();
  path.moveTo(ConvFT_Vector(to));
  return 0;
}

int lineTo(const FT_Vector* to, void* user) {
  auto path = cast(Path*)user;
  path.lineTo(ConvFT_Vector(to));
  return 0;
}

int quadTo(const FT_Vector* c1, const FT_Vector* to, void* user) {
  auto path = cast(Path*)user;
  path.quadTo(ConvFT_Vector(c1), ConvFT_Vector(to));
  return 0;
}

int cubicTo(const FT_Vector* c1, const FT_Vector* c2,
             const FT_Vector* to, void* user) {
  auto path = cast(Path*)user;
  path.cubicTo(ConvFT_Vector(c1), ConvFT_Vector(c2), ConvFT_Vector(to));
  return 0;
}
