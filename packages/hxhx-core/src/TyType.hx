/**
	Incremental semantic type representation for Stage3 typing.

	`display` remains available for existing diagnostics and target hints, while
	the semantic key records primitives, type parameters, nullable types, and
	canonical nominal identities structurally. In particular, an abstract never
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
	static final KIND_TYPE_PARAMETER = "type-parameter";
	static final KIND_UNRESOLVED = "unresolved";

	public final display:String;

	final kind:String;
	final nominalIdentity:Null<TyNominalTypeId>;
	final typeArguments:Array<TyType>;
	final nullableInner:Null<TyType>;
	final unresolvedPath:String;

	function new(display:String, kind:String, nominalIdentity:Null<TyNominalTypeId>, typeArguments:Array<TyType>, nullableInner:Null<TyType>,
			unresolvedPath:String) {
		this.display = display;
		this.kind = kind;
		this.nominalIdentity = nominalIdentity;
		this.typeArguments = typeArguments == null ? [] : typeArguments;
		this.nullableInner = nullableInner;
		this.unresolvedPath = unresolvedPath == null ? "" : unresolvedPath;
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
