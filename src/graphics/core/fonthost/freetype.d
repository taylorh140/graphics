module graphics.core.fonthost.freetype;

import core.atomic, core.sync.rwmutex, std.exception, std.string, std.traits;
import std.algorithm, std.conv, std.utf;
import freetype.freetype, freetype.outline, guip.bitmap, guip.point, guip.size;
import graphics.core.glyph, graphics.core.fonthost.fontconfig, graphics.core.paint, graphics.core.path;

private shared FreeType _freeType;

@property shared(FreeType) freeType()
{
    if (_freeType is null)
    {
        auto ft = new shared(FreeType)();
        synchronized(ft)
        {
            if (cas(&_freeType, cast(shared FreeType)null, ft))
                ft.init();
        }
    }
    return _freeType;
}

private synchronized class FreeType
{
    void init()
    {
        enforce(!FT_Init_FreeType(cast(FT_Library*)&library),
                new Exception("Error during initialization of FreeType"));
    }

    ~this()
    {
        FT_Done_FreeType(cast(FT_Library)library);
        _freeType = null;
    }

    FT_Face newFace(string path)
    {
        FT_Face face;
        enforce(!FT_New_Face(cast(FT_Library)library, toStringz(path), 0, &face));
        return face;
    }

    FT_Library library;
}

enum Scale26D6 = 1.0f / 64;
FPoint ScaleFT_Vector(FT_Vector vec) {
  return FPoint(vec.x, vec.y) * Scale26D6;
}

shared(GlyphStore) _glyphStore;

@property shared(GlyphStore) glyphStore()
{
    if (_glyphStore is null)
    {
        auto gs = new shared(GlyphStore)();
        synchronized(gs)
        {
            if (cas(&_glyphStore, cast(shared GlyphStore)null, gs))
                gs.init();
        }
    }
    return _glyphStore;
}

synchronized class GlyphStore
{
    void init()
    {
    }

    ~this()
    {
        foreach(faceData; data)
            foreach(sizeData; faceData)
                FT_Done_Face(cast(FT_Face)sizeData.face);
    }

    // TODO: consider removing size based caches now that every text
    // is rendered as path
    shared(Data) getData(TypeFace typeFace, float textSize)
    {
        if (auto faceData = typeFace.filename in data)
        {
            if (auto sizeData = textSize in *faceData)
            {
                return *sizeData;
            }
            else
            {
                auto sizeData = newData(typeFace.filename, textSize);
                (*faceData)[textSize] = sizeData;
                return sizeData;
            }
        }
        else
        {
            shared(Data[float]) faceData;
            auto sizeData = newData(typeFace.filename, textSize);
            faceData[textSize] = sizeData;
            data[typeFace.filename] = faceData;
            return sizeData;
        }
    }

    shared(Data) newData(string path, float textSize)
    {
        shared(Data) d;
        d.glyphs[0] = Glyph(); // HACK needed to force creation of internal AA
        d.face = cast(shared)freeType.newFace(path);
        enforce(!FT_Set_Char_Size(cast(FT_Face)d.face, 0, to!FT_F26Dot6(textSize*64), 72, 72));
        d.mtx = cast(shared)new ReadWriteMutex();
        return d;
    }

    struct Data
    {
        Glyph[dchar] glyphs;
        FT_Face face;
        ReadWriteMutex mtx;
    }

    Data[float][string] data;
}

GlyphCache getGlyphCache(TypeFace typeFace, float textSize)
{
    if (!typeFace.valid())
        typeFace = TypeFace.defaultFace();
    assert(typeFace.valid());
    return GlyphCache(glyphStore.getData(typeFace, textSize));
}

struct GlyphCache
{
    shared(GlyphStore.Data) data;

    GlyphStream glyphStream(string text, Glyph.LoadFlag loadFlags)
    {
        return GlyphStream(text, loadFlags, &this);
    }

    TextPaint.FontMetrics fontMetrics()
    {
        auto face = data.face;
        auto emScale = 1.0 / face.units_per_EM;
        auto xscale = face.size.metrics.x_ppem * emScale;
        auto yscale = face.size.metrics.y_ppem * emScale;

        TextPaint.FontMetrics result;
        result.top = yscale * face.bbox.yMax;
        result.ascent = yscale * face.ascender;
        result.descent = yscale * face.descender;
        result.bottom = yscale * face.bbox.yMin;
        result.leading = yscale * max(0, face.height - (face.ascender - face.descender));
        result.xmin = xscale * face.bbox.xMin;
        result.xmax = xscale * face.bbox.xMax;
        result.underlinePos = yscale * face.underline_position;
        result.underlineThickness = yscale * face.underline_thickness;

        return result;
    }
}

struct GlyphStream
{
    alias int delegate(const ref Glyph) GlyphDg;

    int opApply(scope GlyphDg dg)
    {
        if (text.length == 0)
            return 0;
        auto reader = (cast(ReadWriteMutex)cache.data.mtx).reader;
        reader.lock();
        scope(exit) { reader.unlock(); }

        size_t i;
        while (i < text.length)
        {
            immutable c = decode(text, i);
            auto gl = getGlyph(c, reader);
            if (auto res = dg(gl))
                return res;
        }
        return 0;
    }

    Glyph getGlyph(dchar c, ref ReadWriteMutex.Reader reader)
    {
        auto cached = cast(Glyph*)(c in cache.data.glyphs);

        if (cached is null || (cached.loaded & loadFlags) != 0)
        {
            reader.unlock();
            auto writer = (cast(ReadWriteMutex)cache.data.mtx).writer;
            writer.lock();
            scope(exit) { writer.unlock(); reader.lock(); }

            if (cached is null)
            {
                cache.data.glyphs[c] = Glyph();
                cached = cast(Glyph*)(c in cache.data.glyphs);
            }

            auto charIdx = FT_Get_Char_Index(cast(FT_Face)cache.data.face, c);
            foreach(e; EnumMembers!(Glyph.LoadFlag))
            {
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

void updateGlyph(Glyph.LoadFlag f : Glyph.LoadFlag.NoFlag)(FT_Face face, Glyph* glyph, FT_UInt charIdx)
{
}

void updateGlyph(Glyph.LoadFlag f : Glyph.LoadFlag.Metrics)(FT_Face face, Glyph* glyph, FT_UInt charIdx)
{
    enforce(!FT_Load_Glyph(face, charIdx, FT_LOAD.NO_BITMAP));

    glyph.advance = ScaleFT_Vector(face.glyph.advance);
    glyph.lsbDelta = face.glyph.lsb_delta * Scale26D6;
    glyph.rsbDelta = face.glyph.rsb_delta * Scale26D6;
    glyph.size = FSize(face.glyph.metrics.width * Scale26D6, face.glyph.metrics.height * Scale26D6);
    glyph.loaded |= Glyph.LoadFlag.Metrics;
}

void updateGlyph(Glyph.LoadFlag f : Glyph.LoadFlag.Path)(FT_Face face, Glyph* glyph, FT_UInt charIdx)
{
    enforce(!FT_Load_Glyph(face, charIdx, FT_LOAD.NO_BITMAP));

    assert(glyph.path.empty);
    enforce(!FT_Outline_Decompose(&face.glyph.outline, &outlineCallbacks, &glyph.path));
    glyph.path.close();

    glyph.loaded |= Glyph.LoadFlag.Path;
}

/*
 * Callback for transforming freetype outlines to paths.
 */
immutable outlineCallbacks =
{
    FT_Outline_Funcs funcs;

    funcs.move_to = &moveTo;
    funcs.line_to = &lineTo;
    funcs.conic_to = &quadTo;
    funcs.cubic_to = &cubicTo;
    funcs.shift = 0;
    funcs.delta = 0;
    return funcs;
}();

FPoint ConvFT_Vector(const FT_Vector* v)
{
    auto fp = ScaleFT_Vector(*v);
    fp.y = -fp.y;
    return fp;
}

extern(C):

int moveTo(const FT_Vector* to, void* user)
{
    auto path = cast(Path*)user;
    path.close();
    path.moveTo(ConvFT_Vector(to));
    return 0;
}

int lineTo(const FT_Vector* to, void* user)
{
    auto path = cast(Path*)user;
    path.lineTo(ConvFT_Vector(to));
    return 0;
}

int quadTo(const FT_Vector* c1, const FT_Vector* to, void* user)
{
    auto path = cast(Path*)user;
    path.quadTo(ConvFT_Vector(c1), ConvFT_Vector(to));
    return 0;
}

int cubicTo(const FT_Vector* c1, const FT_Vector* c2,
             const FT_Vector* to, void* user)
{
    auto path = cast(Path*)user;
    path.cubicTo(ConvFT_Vector(c1), ConvFT_Vector(c2), ConvFT_Vector(to));
    return 0;
}
