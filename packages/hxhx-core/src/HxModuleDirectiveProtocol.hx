/**
	Decoder for one module-directive record in native frontend protocol version 3.

	The wire payload contains three newline-separated fields: kind, path, and
	optional alias. Length-prefixing and escaping are handled by the surrounding
	frontend protocol, so paths and aliases are not parsed from delimiters such as
	dots or `.*` suffixes here.
**/
class HxModuleDirectiveProtocol {
	public static function decode(payload:String):HxModuleDirective {
		final fields = payload == null ? [] : payload.split("\n");
		if (fields.length != 3)
			throw "Native frontend: malformed module directive";
		final kind = fields[0];
		final path = fields[1];
		final alias = fields[2];
		return switch (kind) {
			case "import-normal":
				requireEmptyAlias(kind, alias);
				HxModuleDirective.normalImport(path);
			case "import-alias": HxModuleDirective.aliasImport(path, alias);
			case "import-all":
				requireEmptyAlias(kind, alias);
				HxModuleDirective.wildcardImport(path);
			case "using":
				requireEmptyAlias(kind, alias);
				HxModuleDirective.usingDirective(path);
			case _: throw "Native frontend: unknown module directive kind: " + kind;
		};
	}

	static function requireEmptyAlias(kind:String, alias:String):Void {
		if (alias.length > 0)
			throw "Native frontend: " + kind + " directive must not carry an alias";
	}
}
