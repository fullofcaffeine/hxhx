/**
	The four Haxe meanings represented by a top-of-module `import` or `using` declaration.

	Keeping this family closed prevents an alias or wildcard from being reduced to
	an ordinary path string before name resolution. `ImportAlias` represents both
	the current `as` spelling and the legacy `in` spelling because they have the
	same source-language behavior.
**/
enum HxModuleDirectiveKind {
	ImportNormal;
	ImportAlias(alias:String);
	ImportAll;
	Using;
}
