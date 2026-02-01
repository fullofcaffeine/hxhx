/**
	Keyword enum for the Haxe-in-Haxe parser subset.

	Why:
	- Keeping keywords explicit (instead of reusing strings everywhere) makes the
	  lexer and parser easier to evolve safely as we expand language coverage.
**/
enum HxKeyword {
	KPackage;
	KImport;
	KClass;
	KStatic;
	KFunction;
}

