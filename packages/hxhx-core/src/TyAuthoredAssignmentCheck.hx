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
	static inline final MAX_FUNCTION_DEPTH = 16;

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
	static function describe(expected:TyType, actual:TyType, ?writtenExpected:String):Null<String>
		return describeWalk(expected, actual, writtenExpected, 0, new haxe.ds.StringMap<Bool>());

	/**
		Compare one pair of types. `visited` holds every (expected, actual) pair this
		walk has entered. A recursive typedef such as `typedef Step = Int->Step`
		unfolds forever, and two same-shaped typedefs with different names reach the
		same pairs through every recursive occurrence. A pair seen again is treated
		as fitting: if it had not fit, the walk would already have stopped. That
		keeps the work proportional to the number of distinct pairs. The depth limit
		remains for generic typedefs whose arguments grow, where no pair repeats.
	 */
	static function describeWalk(expected:TyType, actual:TyType, writtenExpected:Null<String>, depth:Int, visited:haxe.ds.StringMap<Bool>):Null<String> {
		final expectedKey = expected.getSemanticKey();
		final actualKey = actual.getSemanticKey();
		if (depth > MAX_FUNCTION_DEPTH || expectedKey == actualKey)
			return null;
		final pair = expectedKey + "\n" + actualKey;
		if (visited.exists(pair))
			return null;
		visited.set(pair, true);
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
			// A written function spelling is normalized; a typedef name stays as written.
			return describeFunction(wanted, supplied,
				upstreamDisplay(supplied) + " should be " + (expectedText.indexOf("->") >= 0 ? upstreamDisplay(wanted) : expectedText), depth, visited);
		return null;
	}

	static function describeFunction(wanted:TyType, supplied:TyType, wholeMismatch:String, depth:Int, visited:haxe.ds.StringMap<Bool>):Null<String> {
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
		// Like upstream, the result is compared first, so the first reported mismatch matches.
		if (!wantedResult.isVoid()) {
			if (suppliedResult.isVoid())
				return suppliedResult.getDisplay() + " should be " + wantedResult.getDisplay();
			final result = describeWalk(wantedResult, suppliedResult, null, depth + 1, visited);
			if (result != null)
				return result;
		}
		for (index in 0...wantedArguments.length) {
			if (wanted.getFunctionParameters()[index].isOptional != supplied.getFunctionParameters()[index].isOptional)
				return null;
			// Arguments flow from the caller of the expected type into the supplied function.
			final argument = describeWalk(suppliedArguments[index], wantedArguments[index], null, depth + 1, visited);
			if (argument != null)
				return argument;
		}
		return null;
	}

	/**
		A function type as upstream prints it in `A should be B`: `() -> Int`,
		`Int -> Int`, or `(x : Int, ?y : Null<Int>) -> Int` once an argument is named
		or optional. Other types keep their ordinary display.
	 */
	static function upstreamDisplay(type:TyType):String {
		if (!type.isFunction() || type.isNullable() || type.getFunctionReturn() == null)
			return type.getDisplay();
		final parameters = type.getFunctionParameters();
		final result = grouped(type.getFunctionReturn());
		if (parameters.length == 0)
			return "() -> " + result;
		var labelled = false;
		for (parameter in parameters)
			if (parameter.isOptional || (parameter.name != null && parameter.name.length > 0))
				labelled = true;
		final parts = new Array<String>();
		for (parameter in parameters) {
			final shown = grouped(parameter.type);
			if (!labelled) {
				parts.push(shown);
				continue;
			}
			final inner = parameter.isOptional && !parameter.type.isNullable() ? "Null<" + shown + ">" : shown;
			final prefix = parameter.isOptional ? "?" : "";
			parts.push(parameter.name != null && parameter.name.length > 0 ? prefix + parameter.name + " : " + inner : prefix + inner);
		}
		return labelled ? "(" + parts.join(", ") + ") -> " + result : parts.join(" -> ") + " -> " + result;
	}

	/** A function type nested in another function type prints inside parentheses. */
	static function grouped(type:TyType):String
		return type.isFunction() && !type.isNullable() ? "(" + upstreamDisplay(type) + ")" : upstreamDisplay(type);

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
