package backend.ocaml;

/**
	Native text for `trace(...)` in Stage3 OCaml output.

	Upstream Haxe prints a trace through `haxe.Log.trace` and
	`haxe.Log.formatOutput`. The line starts with the call's file and line,
	and extra arguments are appended after commas:

	```haxe
	trace(flag);              // Main.hx:5: true
	trace(42, "extra", true); // Main.hx:6: 42,extra,true
	```

	Stage3 used to print only the first argument, with no prefix. It printed a
	Bool as `1`, and it emitted nothing for a call with extra arguments. The
	typed trace record (`TypedBackendTraceOccurrence`) keeps the call's line
	and each argument's type, so each value is converted from its type, as
	`Std.string` would convert it.

	Limits: the text always goes to standard output through `print_endline`. A
	program that replaces `haxe.Log.trace` is not supported, because Stage3
	does not run reassigned dynamic functions yet (haxe_ocaml-waz9w).

	File name: upstream prints the class path as given plus the module's path,
	for example `src/Main.hx` for `-cp src`. Stage3 resolves class paths to
	absolute paths before emission, so `displayFileName` prints a path under
	the compiler's working directory relative to it. That matches upstream for
	relative class paths. With an absolute `-cp`, upstream prints the absolute
	path and Stage3 prints the relative one.
**/
class Stage3OcamlTrace {
	/**
		The OCaml expression that prints one trace line. `text` renders one
		argument as an OCaml `string` expression from its checked type.
	**/
	public static function render(fact:TypedBackendTraceOccurrence, fileName:String, text:(HxExpr, TyType) -> String, quote:String->String):String {
		final prefix = fileName + ":" + fact.line + ": ";
		final parts = [quote(prefix)];
		for (index in 0...fact.arguments.length) {
			if (index > 0)
				parts.push(quote(","));
			parts.push("(" + text(fact.arguments[index], fact.argumentTypes[index]) + ")");
		}
		return "print_endline (" + (fact.arguments.length == 0 ? quote(prefix) : "Stdlib.String.concat \"\" [" + parts.join("; ") + "]") + ")";
	}

	/** The file name a trace prints for a module loaded from `path`; see the class notes. */
	public static function displayFileName(path:Null<String>, cwd:String):String {
		if (path == null)
			return "";
		final normalized = haxe.io.Path.normalize(path);
		if (!haxe.io.Path.isAbsolute(normalized))
			return normalized;
		final root = haxe.io.Path.addTrailingSlash(haxe.io.Path.normalize(cwd));
		return StringTools.startsWith(normalized, root) ? normalized.substr(root.length) : normalized;
	}

	/**
		One argument's text: a String prints `null` when it is null, and every
		other value goes through the typed runtime conversion.
	**/
	public static function argumentText(argument:HxExpr, type:TyType, rendered:String, underlying:String->Null<TyType>, names:Stage3OcamlLocalNames):String {
		if (Stage3OcamlStringConversion.isStringText(type))
			return Stage3OcamlStringConversion.stringText(argument, rendered);
		return Stage3OcamlStringConversion.convert(Stage3OcamlStringConversion.textType(type, underlying), rendered, names);
	}
}
