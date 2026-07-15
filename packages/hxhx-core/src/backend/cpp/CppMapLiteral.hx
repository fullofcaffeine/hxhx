package backend.cpp;

/**
	Recognizes and lowers Haxe arrow-map literals for the C++ backend.

	A parsed `[key => value]` expression shares the `EArrayDecl` node used by an
	ordinary array. This module owns the syntax distinction and the typed Map
	initializer so local inference, expected-type rendering, and raw pair-vector
	rendering cannot grow separate recognition rules.
**/
class CppMapLiteral {
	/** Return whether every element is an arrow entry; empty arrays stay arrays. **/
	public static function isElements(elements:Array<HxExpr>):Bool {
		return entriesFromElements(elements) != null;
	}

	/** Infer the target `shared_ptr<Map<K,V>>` carrier for an arrow literal. **/
	public static function cppType(expr:HxExpr, scope:CppRenderScope, operandCppType:(HxExpr, CppRenderScope) -> String):String {
		final entries = entriesFromExpr(expr);
		if (entries == null)
			return "";
		final keyType = operandCppType(entries[0][0], scope);
		final valueType = operandCppType(entries[0][1], scope);
		if (keyType.length == 0 || valueType.length == 0)
			return "";
		return "std::shared_ptr<Map<" + keyType + ", " + valueType + ">>";
	}

	/** Return the pair carrier used when an arrow literal is rendered as raw data. **/
	public static function pairCppType(elements:Array<HxExpr>, scope:CppRenderScope, operandCppType:(HxExpr, CppRenderScope) -> String):String {
		final entries = entriesFromElements(elements);
		if (entries == null)
			return "std::pair<std::string, std::string>";
		return "std::pair<" + operandCppType(entries[0][0], scope) + ", " + operandCppType(entries[0][1], scope) + ">";
	}

	/**
		Build a Map in expression position through a capture-by-reference IIFE.

		The expected carrier supplies the final key/value types. Each entry is
		adapted through normal expected-type rendering before `Map.set`, preserving
		enum/object carriers and numeric conversions without duplicating them here.
	**/
	public static function renderInitExpr(expr:HxExpr, keyType:String, valueType:String, scope:CppRenderScope,
			valueExpr:(HxExpr, String, CppRenderScope) -> String):Null<String> {
		final entries = entriesFromExpr(expr);
		if (entries == null || keyType.length == 0 || valueType.length == 0)
			return null;
		final out = [
			"([&]() {",
			"  auto __hxhx_map_literal = __hxhx_make_shared_Map<" + keyType + ", " + valueType + ">();"
		];
		for (entry in entries)
			out.push("  __hxhx_map_literal->set(" + valueExpr(entry[0], keyType, scope) + ", " + valueExpr(entry[1], valueType, scope) + ");");
		out.push("  return __hxhx_map_literal;");
		out.push("})()");
		return out.join("\n");
	}

	static function entriesFromExpr(expr:HxExpr):Null<Array<Array<HxExpr>>> {
		return switch (expr) {
			case EArrayDecl(elements):
				entriesFromElements(elements);
			case ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				entriesFromExpr(inner);
			case _:
				null;
		};
	}

	static function entriesFromElements(elements:Array<HxExpr>):Null<Array<Array<HxExpr>>> {
		if (elements == null || elements.length == 0)
			return null;
		final entries = new Array<Array<HxExpr>>();
		for (element in elements) {
			switch (element) {
				case EBinop("=>", key, value):
					entries.push([key, value]);
				case _:
					return null;
			}
		}
		return entries;
	}
}
