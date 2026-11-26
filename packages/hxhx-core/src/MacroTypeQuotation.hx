import haxe.macro.Expr;

/**
	The syntax upstream's parser writes for a type quotation, `macro : T`.

	Why
	- Haxe 4.3.7 turns a type quotation into ordinary syntax while it parses: `macro : Null<$t>`
	  becomes `(TPath({ pack : [], name : "Null", params : [TPType(t)] }) : haxe.macro.Expr.ComplexType)`,
	  an expression that builds the `ComplexType` value. hxhx keeps the quotation as
	  `HxExpr.EMacroType(text)` until the typer lowers it (`MacroReificationLowering.lowerType`).
	  A macro argument and the parse oracle need the parsed form that upstream gives.

	What
	- `expression` reads the quoted type with the shared type grammar (`HxTypedefParser` and
	  `HxMacroTypeSyntax`) and writes the construction syntax:
	  - enum constructors by their bare names (`TPath`, `TPType`, `TFunction`, ...);
	  - a type path as `{pack, name, params}`, plus `sub` when the path names a subtype;
	  - `$name` as the identifier `name`: a `ComplexType` value in place of a type, or a
		`TypePath` value whose `pack`, `name` and `sub` are kept when parameters follow
		(`$tp<Int>`).
	- Every node receives the position of the quotation.

	Not written (explicit errors): structure types and structure extensions. Upstream writes the
	exact source range of each field into them (`pos : { file, min, max }`), and hxhx's parser
	records no end offsets (`haxe_ocaml-9sj5p.2`). The shared type grammar reads no expression
	type parameters (`Foo<1>`), so such a quotation fails as unreadable.
**/
class MacroTypeQuotation {
	final position:Position;

	function new(position:Position) {
		this.position = position;
	}

	/** The construction syntax of `macro : <typeText>`; `typeText` is the quoted type as written. */
	public static function expression(typeText:String, position:Position):Expr {
		final quotation = new MacroTypeQuotation(position);
		final target:ComplexType = TPath({
			pack: ["haxe", "macro"],
			name: "Expr",
			sub: "ComplexType",
			params: []
		});
		return quotation.make(ECheckType(quotation.complexType(read(typeText, position)), target));
	}

	/**
		The shared type grammar has no `$name` splice, so each splice is read as a placeholder
		type name and turned back into `$name` afterwards.
	**/
	static function read(typeText:String, position:Position):ComplexType {
		final authored = typeText == null ? "" : StringTools.trim(typeText);
		if (authored.length == 0)
			throw failure("a type quotation requires a type");
		final text = new StringBuf();
		for (index in 0...authored.length) {
			final code = authored.charCodeAt(index);
			if (code == "$".code)
				text.add(splicePrefix());
			else
				text.addChar(code);
		}
		final parsed = try {
			HxTypedefParser.parseTypeHint(text.toString());
		} catch (error:HxParseError) {
			throw failure("quoted type `" + authored + "` could not be read: " + error.message);
		}
		return HxMacroTypeSyntax.convert(parsed, position, _ -> throw failure("metadata inside a quoted type is not exported yet"));
	}

	static inline function splicePrefix():String
		return "__hxhx_type_quotation_splice_";

	/** The authored name: a placeholder becomes `$name` again. */
	static function authoredName(name:String):String
		return StringTools.startsWith(name, splicePrefix()) ? "$" + name.substr(splicePrefix().length) : name;

	static function isSplice(name:String):Bool
		return name.length > 1 && name.charCodeAt(0) == "$".code;

	function complexType(type:ComplexType):Expr {
		return switch type {
			case TPath(path)
				if (path.pack.length == 0
					&& (path.params == null || path.params.length == 0)
					&& path.sub == null
					&& isSplice(authoredName(path.name))):
				text(authoredName(path.name));
			case TPath(path):
				constructor("TPath", [typePath(path)]);
			case TFunction(arguments, result):
				constructor("TFunction", [array([for (argument in arguments) complexType(argument)]), complexType(result)]);
			case TParent(inner):
				constructor("TParent", [complexType(inner)]);
			case TOptional(inner):
				constructor("TOptional", [complexType(inner)]);
			case TNamed(name, inner):
				constructor("TNamed", [text(authoredName(name)), complexType(inner)]);
			case TIntersection(members):
				constructor("TIntersection", [array([for (member in members) complexType(member)])]);
			case TAnonymous(_) | TExtend(_, _):
				throw failure("a structure type inside a type quotation is not exported yet; upstream writes its exact source range (haxe_ocaml-9sj5p.2)");
		};
	}

	function typePath(path:TypePath):Expr {
		final parameters = path.params == null ? [] : path.params;
		final name = authoredName(path.name);
		if (path.pack.length == 0 && isSplice(name)) {
			final value = text(name);
			if (parameters.length == 0)
				return value;
			return object([
				field("pack", make(EField(value, "pack"))),
				field("name", make(EField(value, "name"))),
				field("sub", make(EField(value, "sub"))),
				field("params", array([for (parameter in parameters) typeParameter(parameter)]))
			]);
		}
		final fields = [
			field("pack", array([for (segment in path.pack) text(authoredName(segment))])),
			field("name", text(name)),
			field("params", array([for (parameter in parameters) typeParameter(parameter)]))
		];
		if (path.sub != null)
			fields.push(field("sub", text(authoredName(path.sub))));
		return object(fields);
	}

	function typeParameter(parameter:TypeParam):Expr {
		return switch parameter {
			case TPType(type): constructor("TPType", [complexType(type)]);
			case TPExpr(_): throw failure("an expression type parameter inside a type quotation is not exported yet");
		};
	}

	/** A name as upstream writes it: `$name` is the identifier `name`, any other name a string. */
	function text(value:String):Expr
		return make(isSplice(value) ? EConst(CIdent(value.substr(1))) : EConst(CString(value, DoubleQuotes)));

	function constructor(name:String, arguments:Array<Expr>):Expr
		return make(ECall(make(EConst(CIdent(name))), arguments));

	static function field(name:String, value:Expr):ObjectField
		return {field: name, expr: value, quotes: Unquoted};

	function array(values:Array<Expr>):Expr
		return make(EArrayDecl(values));

	function object(fields:Array<ObjectField>):Expr
		return make(EObjectDecl(fields));

	function make(definition:ExprDef):Expr
		return {expr: definition, pos: position};

	static function failure(message:String):String
		return "macro syntax export: " + message;
}
