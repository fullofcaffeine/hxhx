/**
	Reject a value that cannot enter a written local type or a declared return
	type, with the message Haxe 4.3.7 prints.

	Why
	- The typer accepted `var g:Float->Int = f` with `f:(Int)->Int`,
	  `function h(x:Int, y:Int):String return x + y;`, and `var x:Int = "s"`.
	  The programs then ran, although upstream Haxe rejects each one
	  (haxe_ocaml-d3urc).

	What
	- `check` runs only where the destination type is authored: a local's
	  written type and a function's declared return type. It does not run while
	  call arguments are typed against candidate parameters, because overload
	  selection may try a parameter type that the argument does not fit.
	- It rejects only two well-understood shapes, and only when both types are
	  complete (no inference variables left):
	  - two different primitives among Int, Float, String, and Bool, except Int
		entering Float (`String should be Int`);
	  - two function types whose arity differs, whose expected argument cannot
		enter the supplied function's argument, or whose supplied result cannot
		enter the expected result. A Void expected result accepts any result, a
		Dynamic component accepts anything, and Int widens to Float in the
		covariant result position (`Float should be Int` when `(Float)->Int` is
		wanted but `(Int)->Int` is supplied).
	- Everything else, such as abstracts with `@:from`/`@:to`, classes and
	  interfaces, structures, nullable types, and type parameters, is left to
	  the owners that already check it. The check never rejects a case it cannot
	  prove incompatible.
**/
class TyAuthoredAssignmentCheck {
	/** Throw the upstream diagnostic when `actual` provably cannot enter `expected`. */
	public static function check(expected:Null<TyType>, actual:Null<TyType>, untypedContext:Bool, filePath:String, position:HxPos, ?writtenExpected:String,
			?writtenExpectedLater:Void->Null<String>):Void {
		if (expected == null || actual == null || untypedContext)
			return;
		if (expected.hasUnknownComponent() || actual.hasUnknownComponent())
			return;
		if (describe(expected, actual) == null)
			return;
		// Name the destination as written only once a mismatch is certain; finding
		// that name may resolve a type hint, which a passing check never needs.
		final written = writtenExpected != null ? writtenExpected : writtenExpectedLater == null ? null : writtenExpectedLater();
		throw new TyperError(filePath, position, describe(expected, actual, written));
	}

	/**
		The upstream "A should be B" text for the first incompatible component, or null.
		Types are compared after typedefs are expanded, but the text names the
		destination as written, like upstream: `String should be R` for
		`typedef R = Int`. `writtenExpected` is that written type, when known.
	 */
	static function describe(expected:TyType, actual:TyType, ?writtenExpected:String):Null<String> {
		final expectedText = writtenExpected == null
			|| StringTools.trim(writtenExpected).length == 0 ? expected.getDisplay() : StringTools.trim(writtenExpected);
		final wanted = TyAliasExpansion.reveal(expected);
		final supplied = TyAliasExpansion.reveal(actual);
		if (wanted.isDynamic() || supplied.isDynamic())
			return null;
		if (isPlainPrimitive(wanted) && isPlainPrimitive(supplied)) {
			if (wanted.getSemanticKey() == supplied.getSemanticKey())
				return null;
			if (wanted.getSemanticKey() == "primitive:Float" && supplied.getSemanticKey() == "primitive:Int")
				return null;
			return actual.getDisplay() + " should be " + expectedText;
		}
		if (wanted.isFunction() && supplied.isFunction() && !wanted.isNullable() && !supplied.isNullable())
			return describeFunction(wanted, supplied, actual.getDisplay() + " should be " + expectedText);
		return null;
	}

	static function describeFunction(wanted:TyType, supplied:TyType, wholeMismatch:String):Null<String> {
		final wantedArguments = wanted.getFunctionArguments();
		final suppliedArguments = supplied.getFunctionArguments();
		final wantedResult = wanted.getFunctionReturn();
		final suppliedResult = supplied.getFunctionReturn();
		if (wantedArguments == null || suppliedArguments == null || wantedResult == null || suppliedResult == null)
			return null;
		if (wanted.getFunctionParameters().length != wantedArguments.length
			|| supplied.getFunctionParameters().length != suppliedArguments.length)
			return null;
		for (parameter in wanted.getFunctionParameters().concat(supplied.getFunctionParameters()))
			if (parameter.isRest)
				return null;
		if (wantedArguments.length != suppliedArguments.length)
			return wholeMismatch;
		for (index in 0...wantedArguments.length) {
			if (wanted.getFunctionParameters()[index].isOptional != supplied.getFunctionParameters()[index].isOptional)
				return null;
			// Arguments flow from the caller of the expected type into the supplied function.
			final argument = describe(suppliedArguments[index], wantedArguments[index]);
			if (argument != null)
				return argument;
		}
		if (wantedResult.isVoid())
			return null;
		if (suppliedResult.isVoid())
			return wholeMismatch;
		return describe(wantedResult, suppliedResult);
	}

	/** Int, Float, String, or Bool, not wrapped in Null. */
	static function isPlainPrimitive(type:TyType):Bool {
		if (type.isNullable())
			return false;
		return switch type.getSemanticKey() {
			case "primitive:Int" | "primitive:Float" | "primitive:String" | "primitive:Bool": true;
			case _: false;
		};
	}
}
