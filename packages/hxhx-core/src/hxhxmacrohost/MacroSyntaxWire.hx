package hxhxmacrohost;

import haxe.macro.Expr;

/**
	Versioned, structured transport for `haxe.macro.Expr` values between the compiler and a
	project-macro plugin.

	Why a payload instead of passing `Expr` values directly
	- The compiler that loads a plugin and the plugin itself are compiled by different OCaml
	  backends. The `hxhx` binary is produced by `reflaxe.ocaml`; a project plugin is produced by
	  hxhx's own Stage3 emitter. The two represent the same Haxe enum differently in memory (for
	  example, Stage3 boxes every enum value and stores arrays as `HxBootArray`). Handing a raw
	  value from one side to the other would read memory with the wrong layout.
	- Both sides compile this one Haxe module, so the payload format has a single owner. Native
	  code only stores the plugin's callback and passes the payload string through it; it never
	  reads or builds syntax.

	What the payload is
	- A header line `hxhx-macro-syntax.v1`, then one envelope letter: `A` (call arguments), `R`
	  (returned expression), or `E` (the macro failed; a message follows).
	- The body is a prefix-encoded tree. Every enum value is its constructor name followed by its
	  arguments; every structure lists its fields in a fixed order; absent optional values are
	  written as `_`. Strings are length-prefixed (`S<length>:<text>`), so no escaping is needed.
	- This is not Haxe source text. Nothing on either side parses it as code.

	Every public `haxe.macro.Expr` constructor and record of Haxe 4.3.7 is encoded, including
	shapes the compiler's importer later rejects. Malformed or truncated payloads, an unknown
	constructor, or another version fail with a message that starts with `macro syntax wire:`.
**/
class MacroSyntaxWire {
	public static inline final VERSION:String = "hxhx-macro-syntax.v1";

	/** Encode the exported arguments of one macro call. */
	public static function encodeArguments(arguments:Array<Expr>):String {
		final writer = new MacroSyntaxWireWriter(VERSION, "A");
		writer.count(arguments.length);
		for (argument in arguments)
			writer.expr(argument);
		return writer.toString();
	}

	/** Decode call arguments inside the plugin. */
	public static function decodeArguments(payload:String):Array<Expr> {
		final reader = new MacroSyntaxWireReader(VERSION, payload, "A");
		final count = reader.count();
		final out = new Array<Expr>();
		for (slot in 0...count)
			out.push(reader.expr());
		reader.finish();
		return out;
	}

	/** Encode the expression a macro returned. */
	public static function encodeResult(result:Expr):String {
		final writer = new MacroSyntaxWireWriter(VERSION, "R");
		writer.expr(result);
		return writer.toString();
	}

	/** Encode a macro failure so it can be reported at the call site. */
	public static function encodeFailure(message:String):String {
		final writer = new MacroSyntaxWireWriter(VERSION, "E");
		writer.string(message == null ? "macro failed without a message" : message);
		return writer.toString();
	}

	/** True when the payload is a failure envelope. */
	public static function isFailure(payload:String):Bool
		return payload != null && StringTools.startsWith(payload, VERSION + "\nE");

	/** The message of a failure envelope. */
	public static function decodeFailure(payload:String):String {
		final reader = new MacroSyntaxWireReader(VERSION, payload, "E");
		final message = reader.string();
		reader.finish();
		return message;
	}

	/** Decode the returned expression inside the compiler. */
	public static function decodeResult(payload:String):Expr {
		final reader = new MacroSyntaxWireReader(VERSION, payload, "R");
		final result = reader.expr();
		reader.finish();
		return result;
	}
}

/**
	The facts of one macro `Position`: the same record `haxe.macro.Context.getPosInfos` returns.

	Outside the macro context the standard library declares `Position` as exactly this structure.
	When hxhx compiles `haxe.macro.Expr` for a plugin it applies the macro-context definition, in
	which `Position` is an opaque compiler type. hxhx's plugin runtime has no separate native
	position value: it stores this record. `MacroSyntaxWire` is the one place that converts between
	the opaque type and the record; macro code itself keeps using positions only as opaque values
	until the macro context services land (`haxe_ocaml-9sj5p.6`).
**/
typedef MacroSyntaxWirePosition = {
	final file:String;
	final min:Int;
	final max:Int;
}

/** Writes one payload. Every method appends exactly one encoded value. */
class MacroSyntaxWireWriter {
	final out:StringBuf;

	/** `version` is `MacroSyntaxWire.VERSION`; passing it keeps this class free of a module cycle. */
	public function new(version:String, envelope:String) {
		out = new StringBuf();
		out.add(version);
		out.add("\n");
		out.add(envelope);
	}

	public function toString():String
		return out.toString();

	public function absent():Void
		out.add("_");

	public function string(value:String):Void {
		if (value == null)
			throw "macro syntax wire: a required string is missing";
		out.add("S");
		out.add(Std.string(value.length));
		out.add(":");
		out.add(value);
	}

	public function optionalString(value:Null<String>):Void {
		if (value == null)
			absent()
		else
			string(value);
	}

	public function int(value:Int):Void {
		out.add("I");
		out.add(Std.string(value));
		out.add(";");
	}

	public function count(value:Int):Void {
		out.add("[");
		out.add(Std.string(value));
		out.add(";");
	}

	public function bool(value:Bool):Void
		out.add(value ? "T" : "F");

	public function optionalBool(value:Null<Bool>):Void {
		if (value == null)
			absent()
		else
			bool(value == true);
	}

	public function tag(name:String):Void
		string(name);

	public function strings(values:Array<String>):Void {
		count(values.length);
		for (value in values)
			string(value);
	}

	public function position(value:Position):Void {
		if (value == null)
			throw "macro syntax wire: a required position is missing";
		final facts:MacroSyntaxWirePosition = cast value;
		string(facts.file);
		int(facts.min);
		int(facts.max);
	}

	public function optionalPosition(value:Null<Position>):Void {
		if (value == null)
			absent()
		else
			position(value);
	}

	public function expr(value:Expr):Void {
		if (value == null)
			throw "macro syntax wire: a required expression is missing";
		exprDef(value.expr);
		position(value.pos);
	}

	public function optionalExpr(value:Null<Expr>):Void {
		if (value == null)
			absent()
		else
			expr(value);
	}

	public function exprs(values:Array<Expr>):Void {
		if (values == null)
			throw "macro syntax wire: a required expression list is missing";
		count(values.length);
		for (value in values)
			expr(value);
	}

	public function optionalExprs(values:Null<Array<Expr>>):Void {
		if (values == null)
			absent()
		else
			exprs(values);
	}

	function exprDef(value:ExprDef):Void {
		if (value == null)
			throw "macro syntax wire: an expression has no definition";
		switch value {
			case EConst(c):
				tag("EConst");
				constant(c);
			case EArray(e1, e2):
				tag("EArray");
				expr(e1);
				expr(e2);
			case EBinop(op, e1, e2):
				tag("EBinop");
				binop(op);
				expr(e1);
				expr(e2);
			case EField(e, field, kind):
				tag("EField");
				expr(e);
				string(field);
				fieldKind(kind);
			case EParenthesis(e):
				tag("EParenthesis");
				expr(e);
			case EObjectDecl(fields):
				tag("EObjectDecl");
				objectFields(fields);
			case EArrayDecl(values):
				tag("EArrayDecl");
				exprs(values);
			case ECall(e, params):
				tag("ECall");
				expr(e);
				exprs(params);
			case ENew(t, params):
				tag("ENew");
				typePath(t);
				exprs(params);
			case EUnop(op, postFix, e):
				tag("EUnop");
				unop(op);
				bool(postFix);
				expr(e);
			case EVars(vars):
				tag("EVars");
				variables(vars);
			case EFunction(kind, f):
				tag("EFunction");
				functionKind(kind);
				functionValue(f);
			case EBlock(values):
				tag("EBlock");
				exprs(values);
			case EFor(it, e):
				tag("EFor");
				expr(it);
				expr(e);
			case EIf(econd, eif, eelse):
				tag("EIf");
				expr(econd);
				expr(eif);
				optionalExpr(eelse);
			case EWhile(econd, e, normalWhile):
				tag("EWhile");
				expr(econd);
				expr(e);
				bool(normalWhile);
			case ESwitch(e, cases, edef):
				tag("ESwitch");
				expr(e);
				switchCases(cases);
				optionalExpr(edef);
			case ETry(e, catches):
				tag("ETry");
				expr(e);
				catchClauses(catches);
			case EReturn(e):
				tag("EReturn");
				optionalExpr(e);
			case EBreak:
				tag("EBreak");
			case EContinue:
				tag("EContinue");
			case EUntyped(e):
				tag("EUntyped");
				expr(e);
			case EThrow(e):
				tag("EThrow");
				expr(e);
			case ECast(e, t):
				tag("ECast");
				expr(e);
				optionalComplexType(t);
			case EDisplay(e, displayKind):
				tag("EDisplay");
				expr(e);
				display(displayKind);
			case ETernary(econd, eif, eelse):
				tag("ETernary");
				expr(econd);
				expr(eif);
				expr(eelse);
			case ECheckType(e, t):
				tag("ECheckType");
				expr(e);
				complexType(t);
			case EMeta(s, e):
				tag("EMeta");
				metadataEntry(s);
				expr(e);
			case EIs(e, t):
				tag("EIs");
				expr(e);
				complexType(t);
		}
	}

	function constant(value:Constant):Void {
		switch value {
			case CInt(v, s):
				tag("CInt");
				string(v);
				optionalString(s);
			case CFloat(f, s):
				tag("CFloat");
				string(f);
				optionalString(s);
			case CString(s, kind):
				tag("CString");
				string(s);
				stringKind(kind);
			case CIdent(s):
				tag("CIdent");
				string(s);
			case CRegexp(r, opt):
				tag("CRegexp");
				string(r);
				string(opt);
		}
	}

	function stringKind(value:Null<StringLiteralKind>):Void {
		if (value == null) {
			absent();
			return;
		}
		final written:StringLiteralKind = value;
		switch written {
			case DoubleQuotes:
				tag("DoubleQuotes");
			case SingleQuotes:
				tag("SingleQuotes");
		}
	}

	function fieldKind(value:Null<EFieldKind>):Void {
		if (value == null) {
			absent();
			return;
		}
		final written:EFieldKind = value;
		switch written {
			case Normal:
				tag("Normal");
			case Safe:
				tag("Safe");
		}
	}

	function quoteStatus(value:Null<QuoteStatus>):Void {
		if (value == null) {
			absent();
			return;
		}
		final written:QuoteStatus = value;
		switch written {
			case Unquoted:
				tag("Unquoted");
			case Quoted:
				tag("Quoted");
		}
	}

	function binop(value:Binop):Void {
		switch value {
			case OpAssignOp(inner):
				tag("OpAssignOp");
				binop(inner);
			case OpAdd:
				tag("OpAdd");
			case OpMult:
				tag("OpMult");
			case OpDiv:
				tag("OpDiv");
			case OpSub:
				tag("OpSub");
			case OpAssign:
				tag("OpAssign");
			case OpEq:
				tag("OpEq");
			case OpNotEq:
				tag("OpNotEq");
			case OpGt:
				tag("OpGt");
			case OpGte:
				tag("OpGte");
			case OpLt:
				tag("OpLt");
			case OpLte:
				tag("OpLte");
			case OpAnd:
				tag("OpAnd");
			case OpOr:
				tag("OpOr");
			case OpXor:
				tag("OpXor");
			case OpBoolAnd:
				tag("OpBoolAnd");
			case OpBoolOr:
				tag("OpBoolOr");
			case OpShl:
				tag("OpShl");
			case OpShr:
				tag("OpShr");
			case OpUShr:
				tag("OpUShr");
			case OpMod:
				tag("OpMod");
			case OpInterval:
				tag("OpInterval");
			case OpArrow:
				tag("OpArrow");
			case OpIn:
				tag("OpIn");
			case OpNullCoal:
				tag("OpNullCoal");
		}
	}

	function unop(value:Unop):Void {
		switch value {
			case OpIncrement:
				tag("OpIncrement");
			case OpDecrement:
				tag("OpDecrement");
			case OpNot:
				tag("OpNot");
			case OpNeg:
				tag("OpNeg");
			case OpNegBits:
				tag("OpNegBits");
			case OpSpread:
				tag("OpSpread");
		}
	}

	function display(value:DisplayKind):Void {
		switch value {
			case DKCall:
				tag("DKCall");
			case DKDot:
				tag("DKDot");
			case DKStructure:
				tag("DKStructure");
			case DKMarked:
				tag("DKMarked");
			case DKPattern(outermost):
				tag("DKPattern");
				bool(outermost);
		}
	}

	function functionKind(value:Null<FunctionKind>):Void {
		if (value == null) {
			absent();
			return;
		}
		final written:FunctionKind = value;
		switch written {
			case FAnonymous:
				tag("FAnonymous");
			case FNamed(name, inlined):
				tag("FNamed");
				string(name);
				optionalBool(inlined);
			case FArrow:
				tag("FArrow");
		}
	}

	function objectFields(values:Array<ObjectField>):Void {
		count(values.length);
		for (value in values) {
			string(value.field);
			expr(value.expr);
			quoteStatus(value.quotes);
		}
	}

	function variables(values:Array<Var>):Void {
		count(values.length);
		for (value in values) {
			string(value.name);
			optionalPosition(value.namePos);
			optionalComplexType(value.type);
			optionalExpr(value.expr);
			optionalBool(value.isFinal);
			optionalBool(value.isStatic);
			optionalMetadata(value.meta);
		}
	}

	function switchCases(values:Array<Case>):Void {
		count(values.length);
		for (value in values) {
			exprs(value.values);
			optionalExpr(value.guard);
			optionalExpr(value.expr);
		}
	}

	function catchClauses(values:Array<Catch>):Void {
		count(values.length);
		for (value in values) {
			string(value.name);
			optionalComplexType(value.type);
			expr(value.expr);
		}
	}

	public function functionValue(value:Function):Void {
		if (value == null)
			throw "macro syntax wire: a function has no definition";
		final arguments:Array<FunctionArg> = value.args;
		count(arguments.length);
		for (argument in arguments) {
			string(argument.name);
			optionalBool(argument.opt);
			optionalComplexType(argument.type);
			optionalExpr(argument.value);
			optionalMetadata(argument.meta);
		}
		optionalComplexType(value.ret);
		optionalExpr(value.expr);
		optionalTypeParamDecls(value.params);
	}

	function optionalTypeParamDecls(values:Null<Array<TypeParamDecl>>):Void {
		if (values == null)
			absent()
		else
			typeParamDecls(values);
	}

	function typeParamDecls(values:Array<TypeParamDecl>):Void {
		count(values.length);
		for (value in values)
			typeParamDecl(value);
	}

	function typeParamDecl(value:TypeParamDecl):Void {
		string(value.name);
		optionalComplexTypes(value.constraints);
		final nested = value.params;
		if (nested == null) {
			absent();
		} else {
			count(nested.length);
			for (child in nested)
				typeParamDecl(child);
		}
		optionalMetadata(value.meta);
		optionalComplexType(value.defaultType);
	}

	function metadataEntry(value:MetadataEntry):Void {
		string(value.name);
		optionalExprs(value.params);
		position(value.pos);
	}

	function optionalMetadata(values:Null<Metadata>):Void {
		if (values == null) {
			absent();
			return;
		}
		count(values.length);
		for (value in values)
			metadataEntry(value);
	}

	public function complexType(value:ComplexType):Void {
		if (value == null)
			throw "macro syntax wire: a required type is missing";
		switch value {
			case TPath(p):
				tag("TPath");
				typePath(p);
			case TFunction(args, ret):
				tag("TFunction");
				complexTypes(args);
				complexType(ret);
			case TAnonymous(fields):
				tag("TAnonymous");
				typeFields(fields);
			case TParent(t):
				tag("TParent");
				complexType(t);
			case TExtend(p, fields):
				tag("TExtend");
				typePaths(p);
				typeFields(fields);
			case TOptional(t):
				tag("TOptional");
				complexType(t);
			case TNamed(n, t):
				tag("TNamed");
				string(n);
				complexType(t);
			case TIntersection(tl):
				tag("TIntersection");
				complexTypes(tl);
		}
	}

	function optionalComplexType(value:Null<ComplexType>):Void {
		if (value == null)
			absent()
		else
			complexType(value);
	}

	function complexTypes(values:Array<ComplexType>):Void {
		count(values.length);
		for (value in values)
			complexType(value);
	}

	function optionalComplexTypes(values:Null<Array<ComplexType>>):Void {
		if (values == null)
			absent()
		else
			complexTypes(values);
	}

	function typePaths(values:Array<TypePath>):Void {
		count(values.length);
		for (value in values)
			typePath(value);
	}

	function typePath(value:TypePath):Void {
		if (value == null)
			throw "macro syntax wire: a required type path is missing";
		strings(value.pack);
		string(value.name);
		final params:Null<Array<TypeParam>> = value.params;
		if (params == null) {
			absent();
		} else {
			count(params.length);
			for (param in params)
				typeParam(param);
		}
		optionalString(value.sub);
	}

	function typeParam(value:TypeParam):Void {
		switch value {
			case TPType(t):
				tag("TPType");
				complexType(t);
			case TPExpr(e):
				tag("TPExpr");
				expr(e);
		}
	}

	function typeFields(values:Array<Field>):Void {
		count(values.length);
		for (value in values) {
			string(value.name);
			optionalString(value.doc);
			final access:Null<Array<Access>> = value.access;
			if (access == null) {
				absent();
			} else {
				count(access.length);
				for (entry in access)
					accessModifier(entry);
			}
			fieldType(value.kind);
			position(value.pos);
			optionalMetadata(value.meta);
		}
	}

	function accessModifier(value:Access):Void {
		switch value {
			case APublic:
				tag("APublic");
			case APrivate:
				tag("APrivate");
			case AStatic:
				tag("AStatic");
			case AOverride:
				tag("AOverride");
			case ADynamic:
				tag("ADynamic");
			case AInline:
				tag("AInline");
			case AMacro:
				tag("AMacro");
			case AFinal:
				tag("AFinal");
			case AExtern:
				tag("AExtern");
			case AAbstract:
				tag("AAbstract");
			case AOverload:
				tag("AOverload");
		}
	}

	function fieldType(value:FieldType):Void {
		switch value {
			case FVar(t, e):
				tag("FVar");
				optionalComplexType(t);
				optionalExpr(e);
			case FFun(f):
				tag("FFun");
				functionValue(f);
			case FProp(get, set, t, e):
				tag("FProp");
				string(get);
				string(set);
				optionalComplexType(t);
				optionalExpr(e);
		}
	}
}

/** Reads one payload produced by `MacroSyntaxWireWriter`, in the same field order. */
class MacroSyntaxWireReader {
	final source:String;
	var cursor:Int;

	/** `version` is `MacroSyntaxWire.VERSION`; passing it keeps this class free of a module cycle. */
	public function new(version:String, payload:String, envelope:String) {
		if (payload == null)
			throw "macro syntax wire: missing payload";
		final header = version + "\n";
		if (!StringTools.startsWith(payload, header))
			throw "macro syntax wire: unsupported payload version (expected `" + version + "`)";
		source = payload;
		cursor = header.length;
		final found = take(1);
		if (found != envelope)
			throw "macro syntax wire: expected envelope `" + envelope + "`, found `" + found + "`";
	}

	function failure(message:String):String
		return "macro syntax wire: " + message + " at offset " + cursor;

	function take(length:Int):String {
		if (length < 0 || cursor + length > source.length)
			throw failure("truncated payload");
		final out = source.substr(cursor, length);
		cursor += length;
		return out;
	}

	function peek():String {
		if (cursor >= source.length)
			throw failure("truncated payload");
		return source.substr(cursor, 1);
	}

	function expect(marker:String):Void {
		final found = take(1);
		if (found != marker)
			throw failure("expected `" + marker + "`, found `" + found + "`");
	}

	/** Consume `_` and return true when the next value is absent. */
	function absent():Bool {
		if (peek() != "_")
			return false;
		cursor++;
		return true;
	}

	/** Read decimal digits (with an optional leading minus) up to `terminator`. */
	function number(terminator:String):Int {
		final start = cursor;
		while (peek() != terminator)
			cursor++;
		final text = source.substr(start, cursor - start);
		cursor++;
		final value = Std.parseInt(text);
		if (value == null || Std.string(value) != text)
			throw failure("invalid number `" + text + "`");
		return value;
	}

	public function finish():Void {
		if (cursor != source.length)
			throw failure("unexpected trailing data");
	}

	public function string():String {
		expect("S");
		final length = number(":");
		return take(length);
	}

	function optionalString():Null<String>
		return absent() ? null : string();

	function int():Int {
		expect("I");
		return number(";");
	}

	public function count():Int {
		expect("[");
		final value = number(";");
		if (value < 0)
			throw failure("negative count");
		return value;
	}

	function bool():Bool {
		final found = take(1);
		return switch found {
			case "T": true;
			case "F": false;
			case _: throw failure("expected a Bool, found `" + found + "`");
		};
	}

	function optionalBool():Null<Bool>
		return absent() ? null : bool();

	function strings():Array<String> {
		final total = count();
		final out = new Array<String>();
		for (slot in 0...total)
			out.push(string());
		return out;
	}

	function position():Position {
		final file = string();
		final min = int();
		final max = int();
		final facts:MacroSyntaxWirePosition = {file: file, min: min, max: max};
		return cast facts;
	}

	function optionalPosition():Null<Position>
		return absent() ? null : position();

	public function expr():Expr {
		final definition = exprDef();
		final pos = position();
		return {expr: definition, pos: pos};
	}

	function optionalExpr():Null<Expr>
		return absent() ? null : expr();

	function exprs():Array<Expr> {
		final total = count();
		final out = new Array<Expr>();
		for (slot in 0...total)
			out.push(expr());
		return out;
	}

	function optionalExprs():Null<Array<Expr>>
		return absent() ? null : exprs();

	function exprDef():ExprDef {
		final name = string();
		return switch name {
			case "EConst": EConst(constant());
			case "EArray":
				final e1 = expr();
				final e2 = expr();
				EArray(e1, e2);
			case "EBinop":
				final op = binop();
				final e1 = expr();
				final e2 = expr();
				EBinop(op, e1, e2);
			case "EField":
				final e = expr();
				final field = string();
				final kind = fieldKind();
				EField(e, field, kind);
			case "EParenthesis": EParenthesis(expr());
			case "EObjectDecl": EObjectDecl(objectFields());
			case "EArrayDecl": EArrayDecl(exprs());
			case "ECall":
				final e = expr();
				final params = exprs();
				ECall(e, params);
			case "ENew":
				final t = typePath();
				final params = exprs();
				ENew(t, params);
			case "EUnop":
				final op = unop();
				final postFix = bool();
				final e = expr();
				EUnop(op, postFix, e);
			case "EVars": EVars(variables());
			case "EFunction":
				final kind = functionKind();
				final f = functionValue();
				EFunction(kind, f);
			case "EBlock": EBlock(exprs());
			case "EFor":
				final it = expr();
				final e = expr();
				EFor(it, e);
			case "EIf":
				final econd = expr();
				final eif = expr();
				final eelse = optionalExpr();
				EIf(econd, eif, eelse);
			case "EWhile":
				final econd = expr();
				final e = expr();
				final normalWhile = bool();
				EWhile(econd, e, normalWhile);
			case "ESwitch":
				final e = expr();
				final cases = switchCases();
				final edef = optionalExpr();
				ESwitch(e, cases, edef);
			case "ETry":
				final e = expr();
				final catches = catchClauses();
				ETry(e, catches);
			case "EReturn": EReturn(optionalExpr());
			case "EBreak": EBreak;
			case "EContinue": EContinue;
			case "EUntyped": EUntyped(expr());
			case "EThrow": EThrow(expr());
			case "ECast":
				final e = expr();
				final t = optionalComplexType();
				ECast(e, t);
			case "EDisplay":
				final e = expr();
				final kind = display();
				EDisplay(e, kind);
			case "ETernary":
				final econd = expr();
				final eif = expr();
				final eelse = expr();
				ETernary(econd, eif, eelse);
			case "ECheckType":
				final e = expr();
				final t = complexType();
				ECheckType(e, t);
			case "EMeta":
				final s = metadataEntry();
				final e = expr();
				EMeta(s, e);
			case "EIs":
				final e = expr();
				final t = complexType();
				EIs(e, t);
			case _: throw failure("unknown expression constructor `" + name + "`");
		};
	}

	function constant():Constant {
		final name = string();
		return switch name {
			case "CInt":
				final v = string();
				final s = optionalString();
				CInt(v, s);
			case "CFloat":
				final f = string();
				final s = optionalString();
				CFloat(f, s);
			case "CString":
				final s = string();
				final kind = stringKind();
				CString(s, kind);
			case "CIdent": CIdent(string());
			case "CRegexp":
				final r = string();
				final opt = string();
				CRegexp(r, opt);
			case _: throw failure("unknown constant constructor `" + name + "`");
		};
	}

	function stringKind():Null<StringLiteralKind> {
		if (absent())
			return null;
		final name = string();
		return switch name {
			case "DoubleQuotes": DoubleQuotes;
			case "SingleQuotes": SingleQuotes;
			case _: throw failure("unknown string literal kind `" + name + "`");
		};
	}

	function fieldKind():Null<EFieldKind> {
		if (absent())
			return null;
		final name = string();
		return switch name {
			case "Normal": Normal;
			case "Safe": Safe;
			case _: throw failure("unknown field access kind `" + name + "`");
		};
	}

	function quoteStatus():Null<QuoteStatus> {
		if (absent())
			return null;
		final name = string();
		return switch name {
			case "Unquoted": Unquoted;
			case "Quoted": Quoted;
			case _: throw failure("unknown quote status `" + name + "`");
		};
	}

	function binop():Binop {
		final name = string();
		return switch name {
			case "OpAssignOp": OpAssignOp(binop());
			case "OpAdd": OpAdd;
			case "OpMult": OpMult;
			case "OpDiv": OpDiv;
			case "OpSub": OpSub;
			case "OpAssign": OpAssign;
			case "OpEq": OpEq;
			case "OpNotEq": OpNotEq;
			case "OpGt": OpGt;
			case "OpGte": OpGte;
			case "OpLt": OpLt;
			case "OpLte": OpLte;
			case "OpAnd": OpAnd;
			case "OpOr": OpOr;
			case "OpXor": OpXor;
			case "OpBoolAnd": OpBoolAnd;
			case "OpBoolOr": OpBoolOr;
			case "OpShl": OpShl;
			case "OpShr": OpShr;
			case "OpUShr": OpUShr;
			case "OpMod": OpMod;
			case "OpInterval": OpInterval;
			case "OpArrow": OpArrow;
			case "OpIn": OpIn;
			case "OpNullCoal": OpNullCoal;
			case _: throw failure("unknown binary operator `" + name + "`");
		};
	}

	function unop():Unop {
		final name = string();
		return switch name {
			case "OpIncrement": OpIncrement;
			case "OpDecrement": OpDecrement;
			case "OpNot": OpNot;
			case "OpNeg": OpNeg;
			case "OpNegBits": OpNegBits;
			case "OpSpread": OpSpread;
			case _: throw failure("unknown unary operator `" + name + "`");
		};
	}

	function display():DisplayKind {
		final name = string();
		return switch name {
			case "DKCall": DKCall;
			case "DKDot": DKDot;
			case "DKStructure": DKStructure;
			case "DKMarked": DKMarked;
			case "DKPattern": DKPattern(bool());
			case _: throw failure("unknown display kind `" + name + "`");
		};
	}

	function functionKind():Null<FunctionKind> {
		if (absent())
			return null;
		final name = string();
		return switch name {
			case "FAnonymous": FAnonymous;
			case "FNamed":
				final functionName = string();
				final inlined = optionalBool();
				FNamed(functionName, inlined);
			case "FArrow": FArrow;
			case _: throw failure("unknown function kind `" + name + "`");
		};
	}

	function objectFields():Array<ObjectField> {
		final total = count();
		final out = new Array<ObjectField>();
		for (slot in 0...total) {
			final field = string();
			final value = expr();
			final quotes = quoteStatus();
			out.push({field: field, expr: value, quotes: quotes});
		}
		return out;
	}

	function variables():Array<Var> {
		final total = count();
		final out = new Array<Var>();
		for (slot in 0...total) {
			final name = string();
			final namePos = optionalPosition();
			final type = optionalComplexType();
			final value = optionalExpr();
			final isFinal = optionalBool();
			final isStatic = optionalBool();
			final meta = optionalMetadata();
			out.push({
				name: name,
				namePos: namePos,
				type: type,
				expr: value,
				isFinal: isFinal,
				isStatic: isStatic,
				meta: meta
			});
		}
		return out;
	}

	function switchCases():Array<Case> {
		final total = count();
		final out = new Array<Case>();
		for (slot in 0...total) {
			final values = exprs();
			final guard = optionalExpr();
			final body = optionalExpr();
			out.push({values: values, guard: guard, expr: body});
		}
		return out;
	}

	function catchClauses():Array<Catch> {
		final total = count();
		final out = new Array<Catch>();
		for (slot in 0...total) {
			final name = string();
			final type = optionalComplexType();
			final body = expr();
			out.push({name: name, type: type, expr: body});
		}
		return out;
	}

	function functionValue():Function {
		final total = count();
		final args = new Array<FunctionArg>();
		for (slot in 0...total) {
			final name = string();
			final opt = optionalBool();
			final type = optionalComplexType();
			final value = optionalExpr();
			final meta = optionalMetadata();
			args.push({
				name: name,
				opt: opt,
				type: type,
				value: value,
				meta: meta
			});
		}
		final ret = optionalComplexType();
		final body = optionalExpr();
		final params = optionalTypeParamDecls();
		return {
			args: args,
			ret: ret,
			expr: body,
			params: params
		};
	}

	function optionalTypeParamDecls():Null<Array<TypeParamDecl>> {
		if (absent())
			return null;
		final total = count();
		final out = new Array<TypeParamDecl>();
		for (slot in 0...total) {
			final name = string();
			final constraints = optionalComplexTypes();
			final params = optionalTypeParamDecls();
			final meta = optionalMetadata();
			final defaultType = optionalComplexType();
			out.push({
				name: name,
				constraints: constraints,
				params: params,
				meta: meta,
				defaultType: defaultType
			});
		}
		return out;
	}

	function metadataEntry():MetadataEntry {
		final name = string();
		final params = optionalExprs();
		final pos = position();
		return {name: name, params: params, pos: pos};
	}

	function optionalMetadata():Null<Metadata> {
		if (absent())
			return null;
		final total = count();
		final out = new Array<MetadataEntry>();
		for (slot in 0...total)
			out.push(metadataEntry());
		return out;
	}

	function complexType():ComplexType {
		final name = string();
		return switch name {
			case "TPath": TPath(typePath());
			case "TFunction":
				final args = complexTypes();
				final ret = complexType();
				TFunction(args, ret);
			case "TAnonymous": TAnonymous(typeFields());
			case "TParent": TParent(complexType());
			case "TExtend":
				final paths = typePaths();
				final fields = typeFields();
				TExtend(paths, fields);
			case "TOptional": TOptional(complexType());
			case "TNamed":
				final typeName = string();
				final t = complexType();
				TNamed(typeName, t);
			case "TIntersection": TIntersection(complexTypes());
			case _: throw failure("unknown type constructor `" + name + "`");
		};
	}

	function optionalComplexType():Null<ComplexType>
		return absent() ? null : complexType();

	function complexTypes():Array<ComplexType> {
		final total = count();
		final out = new Array<ComplexType>();
		for (slot in 0...total)
			out.push(complexType());
		return out;
	}

	function optionalComplexTypes():Null<Array<ComplexType>>
		return absent() ? null : complexTypes();

	function typePaths():Array<TypePath> {
		final total = count();
		final out = new Array<TypePath>();
		for (slot in 0...total)
			out.push(typePath());
		return out;
	}

	function typePath():TypePath {
		final pack = strings();
		final name = string();
		var params:Null<Array<TypeParam>> = null;
		if (!absent()) {
			final total = count();
			final values = new Array<TypeParam>();
			for (slot in 0...total)
				values.push(typeParam());
			params = values;
		}
		final sub = optionalString();
		return {
			pack: pack,
			name: name,
			params: params,
			sub: sub
		};
	}

	function typeParam():TypeParam {
		final name = string();
		return switch name {
			case "TPType": TPType(complexType());
			case "TPExpr": TPExpr(expr());
			case _: throw failure("unknown type parameter constructor `" + name + "`");
		};
	}

	function typeFields():Array<Field> {
		final total = count();
		final out = new Array<Field>();
		for (slot in 0...total) {
			final name = string();
			final doc = optionalString();
			var access:Null<Array<Access>> = null;
			if (!absent()) {
				final accessCount = count();
				final values = new Array<Access>();
				for (slot in 0...accessCount)
					values.push(accessModifier());
				access = values;
			}
			final kind = fieldType();
			final pos = position();
			final meta = optionalMetadata();
			out.push({
				name: name,
				doc: doc,
				access: access,
				kind: kind,
				pos: pos,
				meta: meta
			});
		}
		return out;
	}

	function accessModifier():Access {
		final name = string();
		return switch name {
			case "APublic": APublic;
			case "APrivate": APrivate;
			case "AStatic": AStatic;
			case "AOverride": AOverride;
			case "ADynamic": ADynamic;
			case "AInline": AInline;
			case "AMacro": AMacro;
			case "AFinal": AFinal;
			case "AExtern": AExtern;
			case "AAbstract": AAbstract;
			case "AOverload": AOverload;
			case _: throw failure("unknown access modifier `" + name + "`");
		};
	}

	function fieldType():FieldType {
		final name = string();
		return switch name {
			case "FVar":
				final t = optionalComplexType();
				final e = optionalExpr();
				FVar(t, e);
			case "FFun": FFun(functionValue());
			case "FProp":
				final get = string();
				final set = string();
				final t = optionalComplexType();
				final e = optionalExpr();
				FProp(get, set, t, e);
			case _: throw failure("unknown field type `" + name + "`");
		};
	}
}
