/**
	Read the argument of `e.match(argument)` as a `case` pattern.

	Why
	- Haxe 4.3.7 types `e.match(pattern)` on an enum value as
	  `switch e { case pattern: true; case _: false }` (typer.ml:1802-1814). Upstream patterns are
	  expressions, so the argument needs no conversion there. hxhx parses `case` patterns into
	  `HxSwitchPattern`, and the argument of a call into `HxExpr`, so the typer converts the
	  argument before it types the switch (haxe_ocaml-56lt0, haxe_ocaml-d592g).

	What
	- `_` is a wildcard. A name is a constructor or a capture by `HxSwitchPatternName`, the
	  parser's rule. A constructor call takes nested patterns. Constants, arrays, objects,
	  parentheses and `a | b` keep their `case` meaning.
	- `fromExpr` returns null for any other form; the caller then keeps the ordinary call.
**/
final class HxMatchPattern {
	public static function fromExpr(expression:HxExpr):Null<HxSwitchPattern> {
		return switch expression {
			case EIdent(name):
				identifier(name);
			case EEnumValue(name):
				HxSwitchPatternName.isConstructor(name, false) ? PEnumValue(name) : PBind(name);
			case EField(_, _):
				final path = qualifiedPath(expression);
				path == null ? null : PEnumValue(path);
			case ECall(callee, arguments):
				final name = constructorName(callee);
				if (name == null)
					return null;
				final patterns = new Array<HxSwitchPattern>();
				for (argument in arguments) {
					final pattern = fromExpr(argument);
					if (pattern == null)
						return null;
					patterns.push(pattern);
				}
				PEnumExtract(name, patterns, arguments.length > 0 && isWildcard(arguments[arguments.length - 1]));
			case EBinop(op, left, right):
				binary(op, left, right);
			case EParenthesized(inner, _):
				fromExpr(inner);
			case ENull:
				PNull;
			case EBool(value):
				PBool(value);
			case EString(value, _):
				PString(value);
			case EInt(value):
				PInt(value);
			case EFloat(value):
				PFloat(HxFloatPatternText.of(null, value, false));
			case EUnop(Negate, Prefix, EInt(value)):
				PInt(-value);
			case EUnop(Negate, Prefix, EFloat(value)):
				PFloat(HxFloatPatternText.of(null, value, true));
			case EArrayDecl(values):
				final items = new Array<HxSwitchPattern>();
				for (value in values) {
					final pattern = fromExpr(value);
					if (pattern == null)
						return null;
					items.push(pattern);
				}
				PArray(items);
			case EAnon(fieldNames, fieldValues):
				final patterns = new Array<HxSwitchPattern>();
				for (value in fieldValues) {
					final pattern = fromExpr(value);
					if (pattern == null)
						return null;
					patterns.push(pattern);
				}
				PObject(fieldNames.copy(), patterns);
			case _:
				null;
		}
	}

	/**
		Payloads are bound with plain captures and compared in the body, never matched against a
		String literal or guarded on one: the OCaml backend generator loses such a payload binding in
		the self-compile (haxe_ocaml-yuymr).
	**/
	static function identifier(name:String):HxSwitchPattern {
		if (name == "_")
			return PWildcard;
		return HxSwitchPatternName.isConstructor(name, false) ? PEnumValue(name) : PBind(name);
	}

	/** `a | b` is an or-pattern; `name = pattern` captures; any other operator is not a pattern. **/
	static function binary(op:String, left:HxExpr, right:HxExpr):Null<HxSwitchPattern> {
		if (op == "|") {
			final first = fromExpr(left);
			final second = fromExpr(right);
			if (first == null || second == null)
				return null;
			return POr(alternatives(first).concat(alternatives(second)));
		}
		if (op != "=")
			return null;
		switch left {
			case EIdent(name):
				if (HxSwitchPatternName.isConstructor(name, false))
					return null;
				final pattern = fromExpr(right);
				return pattern == null ? null : PCapture(name, pattern);
			case _:
				return null;
		}
	}

	static function isWildcard(expression:HxExpr):Bool {
		switch expression {
			case EIdent(name):
				return name == "_";
			case _:
				return false;
		}
	}

	/** Whether `pattern` captures a value: upstream rejects that in a `.match` pattern (matcher.ml:196). */
	public static function captures(pattern:HxSwitchPattern):Bool {
		return switch pattern {
			case PBind(name): name != "_";
			case PCapture(_, _): true;
			case PEnumExtract(_, args, _): Lambda.exists(args, captures);
			case PObject(_, patterns) | PArray(patterns) | POr(patterns): Lambda.exists(patterns, captures);
			case _: false;
		}
	}

	static function alternatives(pattern:HxSwitchPattern):Array<HxSwitchPattern>
		return switch pattern {
			case POr(patterns): patterns.copy();
			case _: [pattern];
		}

	static function constructorName(callee:HxExpr):Null<String> {
		return switch callee {
			case EEnumValue(name) | EIdent(name):
				HxSwitchPatternName.isConstructor(name, false) ? name : null;
			case EField(_, _):
				qualifiedPath(callee);
			case _:
				null;
		}
	}

	/** `a.b.C` written as nested field reads; null for any other receiver. */
	static function qualifiedPath(expression:HxExpr):Null<String> {
		return switch expression {
			case EIdent(name) | EEnumValue(name):
				name;
			case EField(object, field):
				final owner = qualifiedPath(object);
				owner == null ? null : owner + "." + field;
			case _:
				null;
		}
	}
}
