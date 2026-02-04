package reflaxe.ocaml;

/**
 * Shared naming utilities for reflaxe.ocaml emission.
 *
 * Why this exists:
 * - Haxe modules can contain **multiple types** (e.g. `Main.hx` contains `Main` + `Counter`).
 * - Reflaxe writes output **per module** (`FilePerModule`), so all those types end up in a single
 *   OCaml compilation unit (`Main.ml`).
 * - OCaml requires identifiers in a module to be unique, so per-type “instance surfaces”
 *   (`type t`, `create`, instance methods, static members) must be *namespaced* to avoid collisions.
 *
 * Mapping policy (portable mode, current milestone):
 * - If a Haxe type is the “primary” type of its module (`Type.name == moduleBaseName(Type.module)`),
 *   we keep the short OCaml names:
 *   - `type t`, `let create`, `let foo`, ...
 * - Otherwise (secondary types in a module), we scope identifiers with a stable, lowercase prefix:
 *   - `type counter_t`, `let counter_create`, `let counter_foo`, ...
 *
 * This keeps output stable for the common “one type per file” case, while making multi-type
 * modules safe and deterministic.
 */
class OcamlNameTools {
	/**
		True if `name` is an OCaml reserved keyword (value identifier).

		Why this exists:
		- Haxe allows members named like `match`, `end`, `type`, ...
		- OCaml does not: emitting those verbatim as `let match = ...` is a syntax error.
		- We keep the mapping stable by prefixing such names with `hx_` at emission time.
	**/
	public static function isOcamlReservedValueName(name:String):Bool {
		return switch (name) {
			// Keywords (OCaml 4.x/5.x)
			case "and", "as", "assert", "asr", "begin",
				"class", "constraint",
				"do", "done", "downto",
				"else", "end", "exception", "external",
				"false", "for", "fun", "function", "functor",
				"if", "in", "include", "inherit", "initializer",
				"land", "lazy", "let", "lor", "lsl", "lsr", "lxor",
				"match", "method", "mod", "module", "mutable",
				"new", "nonrec",
				"object", "of", "open", "or",
				"private",
				"rec",
				"sig", "struct",
				"then", "to", "true", "try", "type",
				"val", "virtual",
				"when", "while", "with":
				true;
			case _:
				false;
		}
	}

	/**
	 * Returns the last segment of a Haxe module id.
	 *
	 * Example:
	 * - `"haxe.io.Path"` -> `"Path"`
	 * - `"Main"` -> `"Main"`
	 */
	public static function moduleBaseName(moduleId:String):String {
		if (moduleId == null || moduleId.length == 0) return "";
		final parts = moduleId.split(".");
		return parts.length == 0 ? moduleId : parts[parts.length - 1];
	}

	/**
	 * True when the type name matches the module's base name.
	 *
	 * In Haxe, this is the “primary” type and can be referenced as `pack.Module` (without `.Type`).
	 */
	public static function isPrimaryTypeInModule(moduleId:String, typeName:String):Bool {
		return moduleBaseName(moduleId) == typeName;
	}

	/**
	 * Convert a Haxe-ish identifier to a safe, lowercase OCaml value/type identifier segment.
	 *
	 * - Lowercases ASCII letters.
	 * - Non-alphanumeric characters become `_`.
	 * - Leading digit becomes `_` prefix.
	 */
	public static function sanitizeLowerIdent(name:String):String {
		if (name == null) return "";
		final out = new StringBuf();
		for (i in 0...name.length) {
			final c = name.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
			out.add(isAlphaNum ? String.fromCharCode(c).toLowerCase() : "_");
		}
		var s = out.toString();
		if (s.length == 0) return s;
		final first = s.charCodeAt(0);
		if (first >= 48 && first <= 57) s = "_" + s;
		return s;
	}

	/**
	 * Returns the per-type identifier prefix used for “secondary types” in a module.
	 *
	 * Example: `Counter` -> `counter`
	 */
	public static function typePrefix(typeName:String):String {
		return sanitizeLowerIdent(typeName);
	}

	/**
	 * OCaml type name for the Haxe type's “instance record”.
	 *
	 * - Primary type: `"t"`
	 * - Secondary type: `"<prefix>_t"`
	 */
	public static function scopedInstanceTypeName(moduleId:String, typeName:String):String {
		return isPrimaryTypeInModule(moduleId, typeName) ? "t" : (typePrefix(typeName) + "_t");
	}

	/**
	 * OCaml value name for a member (function/let binding) belonging to a given Haxe type.
	 *
	 * - Primary type: `memberName`
	 * - Secondary type: `"<prefix>_<memberName>"`
	 */
	public static function scopedValueName(moduleId:String, typeName:String, memberName:String):String {
		return isPrimaryTypeInModule(moduleId, typeName) ? memberName : (typePrefix(typeName) + "_" + memberName);
	}
}
