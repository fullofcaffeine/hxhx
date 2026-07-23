/**
	One immutable top-of-module Haxe `import` or `using` declaration.

	`path` never contains a trailing `.*`; wildcard behavior lives in `kind`.
	This lets callers distinguish `import pack.Tools.*` from `using pack.Tools`
	without reparsing strings or guessing from suffixes.
**/
class HxModuleDirective {
	final path:String;
	final kind:HxModuleDirectiveKind;

	public function new(path:String, kind:HxModuleDirectiveKind) {
		final normalizedPath = path == null ? "" : StringTools.trim(path);
		if (normalizedPath.length == 0)
			throw "module directive path must not be empty";
		if (path != normalizedPath
			|| normalizedPath.indexOf("*") >= 0
			|| normalizedPath.indexOf("\n") >= 0
			|| normalizedPath.indexOf("\r") >= 0
			|| normalizedPath.indexOf("\t") >= 0
			|| normalizedPath.charAt(0) == "."
			|| normalizedPath.charAt(normalizedPath.length - 1) == "."
			|| normalizedPath.indexOf("..") >= 0)
			throw "module directive path is not a normalized Haxe path: " + normalizedPath;
		for (segment in normalizedPath.split("."))
			if (!isBootstrapIdentifier(segment))
				throw "module directive path contains an invalid Haxe identifier: " + normalizedPath;
		if (kind == null)
			throw "module directive kind must not be null";
		this.path = normalizedPath;
		this.kind = kind;
	}

	public static function normalImport(path:String):HxModuleDirective
		return new HxModuleDirective(path, ImportNormal);

	public static function aliasImport(path:String, alias:String):HxModuleDirective {
		final normalizedAlias = alias == null ? "" : StringTools.trim(alias);
		if (normalizedAlias.length == 0 || alias != normalizedAlias || normalizedAlias.indexOf(".") >= 0 || !isBootstrapIdentifier(normalizedAlias))
			throw "aliased import must name its local alias";
		return new HxModuleDirective(path, ImportAlias(normalizedAlias));
	}

	public static function wildcardImport(path:String):HxModuleDirective
		return new HxModuleDirective(path, ImportAll);

	public static function usingDirective(path:String):HxModuleDirective
		return new HxModuleDirective(path, Using);

	public static function getPath(directive:HxModuleDirective):String
		return directive.path;

	public static function getKind(directive:HxModuleDirective):HxModuleDirectiveKind
		return directive.kind;

	/** The local type name introduced by an exact import, or `null` for wildcard/using declarations. **/
	public static function getImportedLocalName(directive:HxModuleDirective):Null<String> {
		return switch (directive.kind) {
			case ImportNormal:
				final dot = directive.path.lastIndexOf(".");
				dot < 0 ? directive.path : directive.path.substr(dot + 1);
			case ImportAlias(alias): alias;
			case ImportAll | Using: null;
		};
	}

	public static function isImport(directive:HxModuleDirective):Bool {
		return switch (directive.kind) {
			case ImportNormal: true;
			case ImportAlias(_): true;
			case ImportAll: true;
			case Using: false;
		};
	}

	/**
		Validate the identifier subset accepted by the current native frontend lexer.

		Protocol records are produced after parsing, so this is a corruption guard,
		not a second parser. It deliberately matches the bootstrap lexer's current
		ASCII identifier grammar and rejects spaces, separators, operators, and
		leading digits instead of letting malformed wire data reach typing.
	**/
	static function isBootstrapIdentifier(value:String):Bool {
		if (value == null || value.length == 0)
			return false;
		for (index in 0...value.length) {
			final code = value.charCodeAt(index);
			final letter = (code >= "A".code && code <= "Z".code) || (code >= "a".code && code <= "z".code) || code == "_".code;
			if (!letter && !(index > 0 && code >= "0".code && code <= "9".code))
				return false;
		}
		return true;
	}

	/** Stable representation used by parsed-module integrity and future cache identities. **/
	public static function canonicalIdentity(directive:HxModuleDirective):String {
		return switch (directive.kind) {
			case ImportNormal: "import-normal:" + directive.path;
			case ImportAlias(alias): "import-alias:" + directive.path + ":" + alias;
			case ImportAll: "import-all:" + directive.path;
			case Using: "using:" + directive.path;
		};
	}
}
