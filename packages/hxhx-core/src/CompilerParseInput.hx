/**
	The selected source file before and after conditional compilation.

	The parser reads filteredSource. Class positions count Unicode characters in
	originalSource, since blanking inactive bytes can change character counts.
	Both strings must retain the same host-string length and token indices.
	Cache identity includes both strings so an inactive edit cannot reuse stale
	positions. filePath identifies the selected file, including bundled sources.
**/
typedef CompilerParseInput = {
	final originalSource:String;
	final filteredSource:String;
	final filePath:String;
}
