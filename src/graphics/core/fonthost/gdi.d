module graphics.core.fonthost.gdi;

import graphics.core.fonthost.fontconfig_gdi, graphics.core.glyph, graphics.core.paint, graphics.core.path;

GlyphCache getGlyphCache(TypeFace typeFace, float textSize){ GlyphCache a; return a;}
 
struct GlyphCache
{
    GlyphStream glyphStream(string text, Glyph.LoadFlag loadFlags)
    {
		GlyphStream a;
        return a;
    }

    TextPaint.FontMetrics fontMetrics()
    {
		TextPaint.FontMetrics result;
        return result;
    }
}


struct GlyphStream
{
alias int delegate(const ref Glyph) GlyphDg;

 Path path;
 
     int opApply(scope GlyphDg dg)
    {
        return 0;
    }
 
}