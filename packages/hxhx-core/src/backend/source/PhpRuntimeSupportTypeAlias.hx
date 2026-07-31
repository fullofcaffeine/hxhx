package backend.source;

/**
	Owns PHP spellings for imported runtime-support types.

	Both the legacy renderer and immutable module-fact observation call this
	target-only helper. It decides only whether a resolved Haxe type has a
	namespaced PHP runtime class and, if so, returns its absolute PHP spelling.
	It does not inspect import text, compiler state, or the current module.
**/
class PhpRuntimeSupportTypeAlias {
	public static function qualifiedName(path:String):Null<String> {
		final clean = path == null ? "" : StringTools.trim(path);
		final supported = switch (clean) {
			case "haxe.Resource" | "haxe.Json" | "haxe.Serializer" | "haxe.Template" | "haxe.Unserializer" | "haxe.rtti.Meta" | "haxe.io.Bytes" |
				"haxe.io.BytesInput" | "haxe.io.BytesOutput" | "haxe.ds.GenericStack" | "haxe.crypto.Md5" | "haxe.crypto.Sha1" | "haxe.crypto.BaseCode" |
				"haxe.crypto.Base64" | "php.Syntax":
				true;
			case _:
				false;
		};
		if (!supported)
			return null;
		final qualified = PhpName.typePath(clean);
		return qualified.indexOf("\\") < 0 ? null : "\\" + qualified;
	}
}
