module graphics.core.fonthost.fontconfig_gdi;

import gdi.gdi;

enum Slant { Roman, Italic, Oblique }

struct TypeFace
{
    static TypeFace defaultFace(Weight weight = Weight.Normal, Slant slant = Slant.Roman)
    {
		TypeFace a;
        return a;
    }
	
	void getGlyphCache(){}
}

