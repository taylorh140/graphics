module guip.bitmap;

import core.atomic;
import std.conv, std.exception, std.string, std.range;
import guip.color, guip.rect, guip.size;

/*
 * Bitmap
 */
struct Bitmap
{
    enum Config
    {
        NoConfig,   //!< Empty default
        A8,         //!< 8-bits per pixel, with only alpha specified (0 is transparent, 0xFF is opaque)
        ARGB_8888,  //!< 32-bits per pixel
    };

private:
    uint _width;
    uint _height;
    Config _config;
    ubyte _flags;
    ubyte[] _buffer;

public:

    this(Config config, uint width, uint height)
    {
        setConfig(config, width, height);
    }

    void setConfig(Bitmap.Config config, uint width, uint height, ubyte[] buf=null)
    {
        _width  = width;
        _height = height;
        _config = config;
        if (buf !is null)
            buffer = buf;
        else
            _buffer.length = width * height * BytesPerPixel(config);
    }

    @property uint width() const
    {
        return _width;
    }

    @property uint height() const
    {
        return _height;
    }

    @property ISize size() const
    {
        return ISize(_width, _height);
    }

    @property IRect bounds() const
    {
        return IRect(size);
    }

    @property Config config() const
    {
        return _config;
    }

    @property inout(ubyte)[] buffer() inout
    {
        return _buffer[];
    }

    @property void buffer(ubyte[] buffer)
    in
    {
        assert(buffer.length >= width * height * BytesPerPixel(config));
    }
    body
    {
        _buffer = buffer;
    }

    inout(T)[] getBuffer(T=Color)() inout
    {
        return cast(inout(T)[])_buffer;
    }

    inout(T)[] getLine(T=Color)(uint y) inout
    {
        immutable off = y * _width;
        return getBuffer!T()[off .. off + _width];
    }

    inout(T)[] getRange(T=Color)(uint xstart, uint xend, uint y) inout
    in
    {
        assert(xend <= _width);
    }
    body
    {
        immutable off = y * _width;
        return getBuffer!T()[off + xstart .. off + xend];
    }


    @property void opaque(bool isOpaque)
    {
        if (isOpaque)
        {
            _flags |= Flags.opaque;
        }
        else
        {
            _flags &= ~Flags.opaque;
        }
    }

    @property bool opaque() const
    {
        return !!(_flags & Flags.opaque);
    }

    void eraseColor(Color c)
    {
        assert(_config == Bitmap.Config.ARGB_8888);
        getBuffer!Color()[] = c;
    }

    void save(string filename) 
    {
        import core.stdc.stdio; //Code shamelessly stolen from arsd's repo
		FILE* fp = fopen((filename ~ "\0").ptr, "wb".ptr);
		if(fp is null)
			throw new Exception("can't open save file");
		scope(exit) fclose(fp);

		void write4(uint what)  { fwrite(&what, 4, 1, fp); }
		void write2(ushort what){ fwrite(&what, 2, 1, fp); }
		void write1(ubyte what) { fputc(what, fp); }

		int width = _width;
		int height = _height;
		ushort bitsPerPixel;

		alias _buffer data;
		Color[] palette;

		// FIXME we should be able to write RGBA bitmaps too, though it seems like not many
		// programs correctly read them!

		if(_config==Config.ARGB_8888) {
			bitsPerPixel = 24;

			// we could also realistically do 16 but meh
		} else if(_config==Config.A8) {
			// FIXME: implement other bpps for more efficiency
			/*
			if(pi.palette.length == 2)
				bitsPerPixel = 1;
			else if(pi.palette.length <= 16)
				bitsPerPixel = 4;
			else
			*/
				bitsPerPixel = 8;
			data = data;
			//palette = pi.palette;
		} else throw new Exception("I can't save this image type");

		ushort offsetToBits;
		if(bitsPerPixel == 8)
			offsetToBits = 1078;
		if (bitsPerPixel == 24 || bitsPerPixel == 16)
			offsetToBits = 54;
		else
			offsetToBits = cast(ushort)(54 + 4 * 1 << bitsPerPixel); // room for the palette...

		uint fileSize = offsetToBits;
		if(bitsPerPixel == 8)
			fileSize += height * (width + width%4);
		else if(bitsPerPixel == 24)
			fileSize += height * ((width * 3) + (!((width*3)%4) ? 0 : 4-((width*3)%4)));
		else assert(0, "not implemented"); // FIXME

		write1('B');
		write1('M');

		write4(fileSize); // size of file in bytes
		write2(0); 	// reserved
		write2(0); 	// reserved
		write4(offsetToBits); // offset to the bitmap data

		write4(40); // size of BITMAPINFOHEADER

		write4(width); // width
		write4(height); // height

		write2(1); // planes
		write2(bitsPerPixel); // bpp
		write4(0); // compression
		write4(0); // size of uncompressed
		write4(0); // x pels per meter
		write4(0); // y pels per meter
		write4(0); // colors used
		write4(0); // colors important

		// And here we write the palette
		if(bitsPerPixel <= 8)
			foreach(c; palette[0..(1 << bitsPerPixel)]){
				write1(c.b);
				write1(c.g);
				write1(c.r);
				write1(0);
			}

		// And finally the data

		int bytesPerPixel;
		if(bitsPerPixel == 8)
			bytesPerPixel = 1;
		else if(bitsPerPixel == 24)
			bytesPerPixel = 4;
		else assert(0, "not implemented"); // FIXME

		int offsetStart = cast(int) data.length;
		for(int y = height; y > 0; y--) {
			offsetStart -= width * bytesPerPixel;
			int offset = offsetStart;
			int b = 0;
			foreach(x; 0 .. width) {
				if(bitsPerPixel == 8) {
					write1(data[offset]);
					b++;
				} else if(bitsPerPixel == 24) {
					write1(data[offset + 2]); // blue
					write1(data[offset + 1]); // green
					write1(data[offset + 0]); // red
					b += 3;
				} else assert(0); // FIXME
				offset += bytesPerPixel;
			}

			int w = b%4;
			if(w)
			for(int a = 0; a < 4-w; a++)
				write1(0); // pad until divisible by four
		}	
    }

    static Bitmap load(string path)
    {
        assert(0, "unimplemented");
    }

private:

    enum Flags
    {
        opaque = 1 << 0,
    }
}

uint BytesPerPixel(Bitmap.Config c)
{
    final switch (c)
    {
    case Bitmap.Config.NoConfig:
        return 0;
    case Bitmap.Config.A8:
        return 1;
    case Bitmap.Config.ARGB_8888:
        return 4;
    }
}
