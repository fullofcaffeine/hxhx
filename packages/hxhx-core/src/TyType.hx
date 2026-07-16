/**
	Incremental semantic type representation for Stage3 typing.

	`display` remains available for existing diagnostics and target hints, while
	the semantic key records primitives, functions, type parameters, nullable
	types, and canonical nominal identities structurally. In particular, an abstract never
	becomes its primitive carrier merely because a backend may erase it later.

	This is intentionally not the complete Haxe type system. Unresolved or
	unsupported type grammar remains explicit instead of falling back to a false
	nominal identity.
**/
class TyType {
	static final KIND_UNKNOWN = "unknown";
	static final KIND_PRIMITIVE = "primitive";
	static final KIND_DYNAMIC = "dynamic";
	static final KIND_NULL = "null";
	static final KIND_NULLABLE = "nullable";
	static final KIND_NOMINAL = "nominal";
	static final KIND_FUNCTION = "function";
	static final KIND_TYPE_PARAMETER = "type-parameter";
	static final KIND_UNRESOLVED = "unresolved";

	public final display:String;

	final kind:String;
	final nominalIdentity:Null<TyNominalTypeId>;
	final typeArguments:Array<TyType>;
	final nullableInner:Null<TyType>;
	final unresolvedPath:String;
	final functionArguments:Array<TyType>;
	final functionReturn:Null<TyType>;

	function new(display:String, kind:String, nominalIdentity:Null<TyNominalTypeId>, typeArguments:Array<TyType>, nullableInner:Null<TyType>,
			unresolvedPath:String, ?functionArguments:Array<TyType>, ?functionReturn:TyType) {
		this.display = display;
		this.kind = kind;
		this.nominalIdentity = nominalIdentity;
		this.typeArguments = typeArguments == null ? [] : typeArguments;
		this.nullableInner = nullableInner;
		this.unresolvedPath = unresolvedPath == null ? "" : unresolvedPath;
		this.functionArguments = functionArguments == null ? [] : functionArguments;
		this.functionReturn = functionReturn;
	}

	public static function unknown():TyType {
		return new TyType("Unknown", KIND_UNKNOWN, null, [], null, "");
	}

	static function primitive(name:String):TyType {
		return new TyType(name, KIND_PRIMITIVE, null, [], null, "");
	}

	static function dynamicType():TyType {
		return new TyType("Dynamic", KIND_DYNAMIC, null, [], null, "");
	}

	static function nullType():TyType {
		return new TyType("Null", KIND_NULL, null, [], null, "");
	}

	public static function nullable(inner:TyType, ?display:String):TyType {
		final actualInner = inner == null ? dynamicType() : inner;
		final shown = display == null || display.length == 0 ? "Null<" + actualInner.getDisplay() + ">" : display;
		return new TyType(shown, KIND_NULLABLE, null, [], actualInner, "");
	}

	public static function nominal(identity:TyNominalTypeId, args:Array<TyType>, ?display:String):TyType {
		final actualArgs = args == null ? [] : args;
		var shown = display == null ? "" : StringTools.trim(display);
		if (shown.length == 0) {
			shown = identity.getCanonicalName();
			if (actualArgs.length > 0)
				shown += "<" + [for (arg in actualArgs) arg.getDisplay()].join(",") + ">";
		}
		return new TyType(shown, KIND_NOMINAL, identity, actualArgs, null, "");
	}

	/** Create a structural function type whose arguments and result remain available to call typing. **/
	public static function functionType(arguments:Array<TyType>, result:TyType, ?display:String):TyType {
		final actualArguments = arguments == null ? [] : arguments;
		final actualResult = result == null ? unknown() : result;
		var shown = display == null ? "" : StringTools.trim(display);
		if (shown.length == 0) {
			final argumentText = actualArguments.length == 0 ? "()" : "(" + [for (argument in actualArguments) argument.getDisplay()].join(", ") + ")";
			shown = argumentText + "->" + actualResult.getDisplay();
		}
		return new TyType(shown, KIND_FUNCTION, null, [], null, "", actualArguments, actualResult);
	}

	public static function typeParameter(name:String):TyType {
		final clean = name == null ? "" : StringTools.trim(name);
		return new TyType(clean, KIND_TYPE_PARAMETER, null, [], null, clean);
	}

	public static function unresolved(path:String, args:Array<TyType>, ?display:String):TyType {
		final cleanPath = path == null ? "" : StringTools.trim(path);
		final actualArgs = args == null ? [] : args;
		var shown = display == null ? "" : StringTools.trim(display);
		if (shown.length == 0) {
			shown = cleanPath;
			if (actualArgs.length > 0)
				shown += "<" + [for (arg in actualArgs) arg.getDisplay()].join(",") + ">";
		}
		return new TyType(shown, KIND_UNRESOLVED, null, actualArgs, null, cleanPath);
	}

	public function isUnknown():Bool
		return kind == KIND_UNKNOWN;

	public function isVoid():Bool
		return kind == KIND_PRIMITIVE && display == "Void";

	public function isNumeric():Bool
		return kind == KIND_PRIMITIVE && (display == "Int" || display == "Float");

	public function isDynamic():Bool
		return kind == KIND_DYNAMIC;

	public function isFunction():Bool
		return kind == KIND_FUNCTION;

	public function isNullWrapped():Bool
		return kind == KIND_NULLABLE;

	public function isNullable():Bool
		return kind == KIND_NULLABLE;

	public function isUnresolved():Bool
		return kind == KIND_UNRESOLVED;

	public function isTypeParameter():Bool
		return kind == KIND_TYPE_PARAMETER;

	public function unwrapNull():TyType {
		return nullableInner == null ? this : nullableInner;
	}

	public function getNullableInner():Null<TyType>
		return nullableInner;

	public function getNominalIdentity():Null<TyNominalTypeId>
		return nominalIdentity;

	public function getTypeArguments():Array<TyType>
		return typeArguments;

	public function getUnresolvedPath():String
		return unresolvedPath;

	public function getFunctionArguments():Array<TyType>
		return functionArguments;

	public function getFunctionReturn():Null<TyType>
		return functionReturn;

	public function getSemanticKey():String {
		if (kind == KIND_PRIMITIVE)
			return "primitive:" + display;
		if (kind == KIND_DYNAMIC)
			return "dynamic";
		if (kind == KIND_NULL)
			return "null";
		if (kind == KIND_UNKNOWN)
			return "unknown";
		if (kind == KIND_TYPE_PARAMETER)
			return "type-parameter:" + unresolvedPath;
		if (kind == KIND_NULLABLE)
			return "nullable:" + (nullableInner == null ? "dynamic" : nullableInner.getSemanticKey());
		if (kind == KIND_FUNCTION) {
			final arguments = [for (argument in functionArguments) argument.getSemanticKey()].join(",");
			return "function:(" + arguments + ")->" + (functionReturn == null ? "unknown" : functionReturn.getSemanticKey());
		}
		final args = typeArguments.length == 0 ? "" : "<" + [for (arg in typeArguments) arg.getSemanticKey()].join(",") + ">";
		if (kind == KIND_NOMINAL)
			return "nominal:" + (nominalIdentity == null ? "" : nominalIdentity.getCanonicalName()) + args;
		return "unresolved:" + unresolvedPath + args;
	}

	static function genericStart(text:String):Int {
		for (i in 0...text.length)
			if (text.charAt(i) == "<")
				return i;
		return -1;
	}

	static function splitTypeArguments(text:String):Array<String> {
		final out = new Array<String>();
		var depth = 0;
		var start = 0;
		for (i in 0...text.length) {
			final ch = text.charAt(i);
			if (ch == "<") {
				depth++;
			} else if (ch == ">") {
				if (depth > 0)
					depth--;
			} else if (ch == "," && depth == 0) {
				out.push(StringTools.trim(text.substring(start, i)));
				start = i + 1;
			}
		}
		final tail = StringTools.trim(text.substr(start));
		if (tail.length > 0)
			out.push(tail);
		return out;
	}

	static function hasWrappingParentheses(text:String):Bool {
		if (!StringTools.startsWith(text, "(") || !StringTools.endsWith(text, ")"))
			return false;
		var depth = 0;
		for (i in 0...text.length) {
			final ch = text.charAt(i);
			if (ch == "(")
				depth++;
			else if (ch == ")") {
				depth--;
				if (depth == 0 && i < text.length - 1)
					return false;
			}
		}
		return depth == 0;
	}

	static function splitTopLevel(text:String, separator:String):Array<String> {
		final out = new Array<String>();
		var parenDepth = 0;
		var angleDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		var start = 0;
		for (i in 0...text.length) {
			final ch = text.charAt(i);
			switch (ch) {
				case "(":
					parenDepth++;
				case ")":
					if (parenDepth > 0)
						parenDepth--;
				case "<":
					angleDepth++;
				case ">":
					if (angleDepth > 0)
						angleDepth--;
				case "[":
					bracketDepth++;
				case "]":
					if (bracketDepth > 0)
						bracketDepth--;
				case "{":
					braceDepth++;
				case "}":
					if (braceDepth > 0)
						braceDepth--;
				case _:
			}
			if (ch == separator && parenDepth == 0 && angleDepth == 0 && bracketDepth == 0 && braceDepth == 0) {
				out.push(StringTools.trim(text.substring(start, i)));
				start = i + 1;
			}
		}
		out.push(StringTools.trim(text.substr(start)));
		return out;
	}

	static function splitFunctionSegments(text:String):Array<String> {
		final out = new Array<String>();
		var parenDepth = 0;
		var angleDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		var start = 0;
		var index = 0;
		while (index < text.length) {
			final ch = text.charAt(index);
			switch (ch) {
				case "(":
					parenDepth++;
				case ")":
					if (parenDepth > 0)
						parenDepth--;
				case "<":
					angleDepth++;
				case ">":
					if (angleDepth > 0)
						angleDepth--;
				case "[":
					bracketDepth++;
				case "]":
					if (bracketDepth > 0)
						bracketDepth--;
				case "{":
					braceDepth++;
				case "}":
					if (braceDepth > 0)
						braceDepth--;
				case _:
			}
			if (ch == "-" && index + 1 < text.length && text.charAt(index + 1) == ">" && parenDepth == 0 && angleDepth == 0 && bracketDepth == 0
				&& braceDepth == 0) {
				out.push(StringTools.trim(text.substring(start, index)));
				index += 2;
				start = index;
				continue;
			}
			index++;
		}
		if (out.length == 0)
			return [];
		out.push(StringTools.trim(text.substr(start)));
		for (segment in out)
			if (segment.length == 0)
				return [];
		return out;
	}

	static function functionArgumentTypeText(text:String):String {
		final trimmed = StringTools.trim(text);
		var parenDepth = 0;
		var angleDepth = 0;
		var bracketDepth = 0;
		var braceDepth = 0;
		for (i in 0...trimmed.length) {
			final ch = trimmed.charAt(i);
			switch (ch) {
				case "(":
					parenDepth++;
				case ")":
					if (parenDepth > 0)
						parenDepth--;
				case "<":
					angleDepth++;
				case ">":
					if (angleDepth > 0)
						angleDepth--;
				case "[":
					bracketDepth++;
				case "]":
					if (bracketDepth > 0)
						bracketDepth--;
				case "{":
					braceDepth++;
				case "}":
					if (braceDepth > 0)
						braceDepth--;
				case _:
			}
			if (ch == ":" && parenDepth == 0 && angleDepth == 0 && bracketDepth == 0 && braceDepth == 0)
				return StringTools.trim(trimmed.substr(i + 1));
		}
		return trimmed;
	}

	static function parseFunctionType(text:String):Null<TyType> {
		final segments = splitFunctionSegments(text);
		if (segments.length < 2)
			return null;
		final arguments = new Array<TyType>();
		for (index in 0...segments.length - 1) {
			var argumentGroup = StringTools.trim(segments[index]);
			if (hasWrappingParentheses(argumentGroup))
				argumentGroup = StringTools.trim(argumentGroup.substr(1, argumentGroup.length - 2));
			if (argumentGroup.length == 0)
				continue;
			for (argument in splitTopLevel(argumentGroup, ",")) {
				final typeText = functionArgumentTypeText(argument);
				if (typeText.length == 0)
					return null;
				arguments.push(fromHintText(typeText));
			}
		}
		var resultText = StringTools.trim(segments[segments.length - 1]);
		if (hasWrappingParentheses(resultText))
			resultText = StringTools.trim(resultText.substr(1, resultText.length - 2));
		if (resultText.length == 0)
			return null;
		return functionType(arguments, fromHintText(resultText), text);
	}

	/** Parse the supported nominal/generic/nullable hint spine without guessing unresolved identities. **/
	public static function fromHintText(hint:String):TyType {
		if (hint == null)
			return unknown();
		final text = StringTools.trim(hint);
		if (text.length == 0)
			return unknown();
		if (text == "Int" || text == "Float" || text == "Bool" || text == "String" || text == "Void")
			return primitive(text);
		if (text == "Dynamic")
			return dynamicType();
		if (text == "Null")
			return nullType();
		final parsedFunction = parseFunctionType(text);
		if (parsedFunction != null)
			return parsedFunction;

		final open = genericStart(text);
		if (open > 0 && StringTools.endsWith(text, ">")) {
			final base = StringTools.trim(text.substring(0, open));
			final inner = text.substring(open + 1, text.length - 1);
			final args = [for (part in splitTypeArguments(inner)) fromHintText(part)];
			if (base == "Null" && args.length == 1)
				return nullable(args[0], text);
			return unresolved(base, args, text);
		}
		return unresolved(text, [], text);
	}

	/**
		Best-effort unification retained for the bootstrap typer.

		Semantic identities improve equality but do not broaden compatibility:
		unknown, numeric widening, nullable wrappers, null, and Dynamic keep their
		existing bounded behavior.
	**/
	public static function unify(a:TyType, b:TyType):Null<TyType> {
		if (a == null || b == null)
			return null;
		if (a.isUnknown())
			return b;
		if (b.isUnknown())
			return a;
		if (a.getSemanticKey() == b.getSemanticKey())
			return a;
		if (a.isFunction() && b.isFunction()) {
			final aArguments = a.getFunctionArguments();
			final bArguments = b.getFunctionArguments();
			if (aArguments.length != bArguments.length)
				return null;
			final arguments = new Array<TyType>();
			for (index in 0...aArguments.length) {
				final left = aArguments[index];
				final right = bArguments[index];
				final argument = left.isUnknown()
					|| left.isDynamic() ? right : right.isUnknown() || right.isDynamic() ? left : unify(left, right);
				if (argument == null)
					return null;
				arguments.push(argument);
			}
			final aReturn = a.getFunctionReturn();
			final bReturn = b.getFunctionReturn();
			if (aReturn == null || bReturn == null)
				return null;
			final result = aReturn.isUnknown()
				|| aReturn.isDynamic() ? bReturn : bReturn.isUnknown() || bReturn.isDynamic() ? aReturn : unify(aReturn, bReturn);
			return result == null ? null : functionType(arguments, result, a.getDisplay());
		}
		if (a.display == "Null")
			return b;
		if (b.display == "Null")
			return a;
		if (a.isNullWrapped() && b.isNullWrapped()) {
			final unified = unify(a.unwrapNull(), b.unwrapNull());
			return unified == null ? null : nullable(unified);
		}
		if (a.isNullWrapped()) {
			final unified = unify(a.unwrapNull(), b);
			return unified == null ? null : a;
		}
		if (b.isNullWrapped()) {
			final unified = unify(a, b.unwrapNull());
			return unified == null ? null : b;
		}
		if (a.isNumeric() && b.isNumeric())
			return primitive("Float");
		if (a.display == "Dynamic")
			return a;
		if (b.display == "Dynamic")
			return b;
		return null;
	}

	public function toString():String
		return display;

	/** Non-inline diagnostic-display getter for cross-module OCaml builds. **/
	public function getDisplay():String
		return display;
}
