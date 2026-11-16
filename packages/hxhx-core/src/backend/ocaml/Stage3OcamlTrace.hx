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

	File name: upstream prints the path relative to the class path that owns
	the module, spelled as that class path was given. `-cp src` prints
	`src/Main.hx`, `-cp ../src` prints `../src/Main.hx`, and an absolute
	`-cp /abs/src` prints `Main.hx` (or `pkg/Sub.hx`); only `-D absolute-path`
	prints absolute paths. Stage3 resolves class paths to absolute paths before
	emission and does not keep their spelling, so `displayFileName` prints the
	module path relative to the compiler's working directory. That matches
	upstream for a relative class path under the working directory, the usual
	hxml case. It differs for an absolute class path (Stage3 prints a longer
	relative path) and for a class path outside the working directory, such as
	`../src` (Stage3 prints the absolute path).

	Arguments are evaluated once, left to right, as upstream does: each is
	bound with `let` before the line is assembled, because OCaml may evaluate
	list elements and application arguments right to left.
**/
class Stage3OcamlTrace {
	/**
		The OCaml expression that prints one trace line. `text` renders one
		argument as an OCaml `string` expression from its checked type.
	**/
	public static function render(fact:TypedBackendTraceOccurrence, fileName:String, text:(HxExpr, TyType) -> String, quote:String->String,
			names:Stage3OcamlLocalNames):String {
		if (names == null)
			throw "OCaml trace rendering requires a local naming owner";
		final prefix = fileName + ":" + fact.line + ": ";
		final bound = [
			for (index in 0...fact.arguments.length)
				names.internalName("__hx_trace_argument_" + index)
		];
		final parts = [quote(prefix)];
		for (index in 0...bound.length) {
			if (index > 0)
				parts.push(quote(","));
			parts.push(bound[index]);
		}
		var body = "print_endline (Stdlib.String.concat \"\" [" + parts.join("; ") + "])";
		var index = bound.length;
		while (index-- > 0)
			body = "let " + bound[index] + " = (" + text(fact.arguments[index], fact.argumentTypes[index]) + ") in " + body;
		return "(" + body + ")";
	}

	/** Whether every argument has a checked type that the typed text conversion accepts. */
	public static function hasCompleteTypes(fact:TypedBackendTraceOccurrence):Bool {
		for (type in fact.argumentTypes)
			if (type == null || type.isUnknown() || type.isUnresolved() || type.hasUnknownComponent())
				return false;
		return true;
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
