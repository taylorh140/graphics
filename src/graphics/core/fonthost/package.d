module graphics.core.fonthost;

version (FreeBSD) {
  version = FreeType;
} else version (Linux) {
  version = FreeType;
} else version (Solaris) {
  version = FreeType;
} else version (Windows) {
  version = GDI;
} else version (OSX) {
  version = CoreText;
}

// match FreeType first so it can also be used on windows, osx
version (FreeType) {
  public import graphics.core.fonthost.fontconfig;
  public import graphics.core.fonthost.freetype;
} else version (GDI) {
  // TODO: gdi binding
  public import graphics.core.fonthost.gdi;
  public import graphics.core.fonthost.fontconfig_gdi;
} else version(CoreText) {
  // TODO: coretext binding, atsui for 10.4 ?
  // public import graphics.core.fonthost.coretext;
}
