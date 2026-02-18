package backend.js;

/**
	Expression-to-JS lowering for `js-native` MVP.

	Why
	- Stage3 already has a parsed expression AST; this mapper turns the MVP subset into JS text.
	- Unsupported shapes fail fast so bring-up diffs are explicit and actionable.
**/
class JsExprEmitter {
	static function unsupported(kind:String):String {
		throw "js-native MVP does not support expression kind: " + kind;
	}

	static function nestedScope(parent:JsEmitScope, locals:haxe.ds.StringMap<String>):JsEmitScope {
		return {
			resolveLocal: function(name:String):Null<String> {
				final v = locals.get(name);
				if (v != null) return v;
				return parent == null ? null : parent.resolveLocal(name);
			},
			resolveClassRef: function(name:String):Null<String> {
				return parent == null ? null : parent.resolveClassRef(name);
			}
		};
	}

	public static function emit(expr:HxExpr, scope:JsEmitScope):String {
		return switch (expr) {
			case ENull:
				"null";
			case EBool(v):
				v ? "true" : "false";
			case EString(v):
				JsNameMangler.quoteString(v);
			case EInt(v):
				Std.string(v);
			case EFloat(v):
				Std.string(v);
			case EEnumValue(name):
				JsNameMangler.quoteString(name);
			case EThis:
				"this";
			case ESuper:
				"super";
			case EIdent(name):
				resolveIdent(name, scope);
			case EField(obj, field):
				emit(obj, scope) + JsNameMangler.propertySuffix(field);
			case ECall(callee, args):
				emitCall(callee, args, scope);
			case EUnop(op, inner):
				"(" + op + emit(inner, scope) + ")";
			case EBinop(op, left, right):
				emitBinop(op, left, right, scope);
			case ETernary(cond, thenExpr, elseExpr):
				"(" + emit(cond, scope) + " ? " + emit(thenExpr, scope) + " : " + emit(elseExpr, scope) + ")";
			case EAnon(fieldNames, fieldValues):
				emitAnon(fieldNames, fieldValues, scope);
			case EArrayDecl(values):
				"[" + values.map(v -> emit(v, scope)).join(", ") + "]";
			case EArrayAccess(array, index):
				emit(array, scope) + "[" + emit(index, scope) + "]";
			case ELambda(args, body):
				emitLambda(args, body, scope);
			case ECast(inner, _):
				emit(inner, scope);
			case EUntyped(inner):
				emit(inner, scope);
			case ESwitch(_, _):
				unsupported("ESwitch");
			case ESwitchRaw(_):
				unsupported("ESwitchRaw");
			case ETryCatchRaw(_):
				unsupported("ETryCatchRaw");
			case ERange(_, _):
				unsupported("ERange");
			case EArrayComprehension(_, _, _):
				unsupported("EArrayComprehension");
			case ENew(_, _):
				unsupported("ENew");
			case EUnsupported(raw):
				unsupported("EUnsupported(" + raw + ")");
		}
	}

	static function resolveIdent(name:String, scope:JsEmitScope):String {
		if (scope != null) {
			final local = scope.resolveLocal(name);
			if (local != null) return local;
			final cls = scope.resolveClassRef(name);
			if (cls != null) return cls;
		}
		return JsNameMangler.identifier(name);
	}

	static function emitCall(callee:HxExpr, args:Array<HxExpr>, scope:JsEmitScope):String {
		switch (callee) {
			case EIdent("trace"):
				return "console.log(" + args.map(a -> emit(a, scope)).join(", ") + ")";
			case EField(EIdent("Sys"), "println"):
				return "console.log(" + args.map(a -> emit(a, scope)).join(", ") + ")";
			case EField(EIdent("Sys"), "print"):
				final arg = args.length > 0 ? emit(args[0], scope) : "\"\"";
				return "process.stdout.write(String(" + arg + "))";
			case _:
		}
		final calleeJs = emit(callee, scope);
		final argsJs = args.map(a -> emit(a, scope)).join(", ");
		return calleeJs + "(" + argsJs + ")";
	}

	static function emitBinop(op:String, left:HxExpr, right:HxExpr, scope:JsEmitScope):String {
		if (op == "??") {
			final l = emit(left, scope);
			final r = emit(right, scope);
			return "((" + l + " != null) ? " + l + " : " + r + ")";
		}
		final normalized = switch (op) {
			case "==": "===";
			case "!=": "!==";
			case _: op;
		}
		return "(" + emit(left, scope) + " " + normalized + " " + emit(right, scope) + ")";
	}

	static function emitAnon(fieldNames:Array<String>, fieldValues:Array<HxExpr>, scope:JsEmitScope):String {
		final pairs = new Array<String>();
		final n = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
		for (i in 0...n) {
			final key = JsNameMangler.quoteString(fieldNames[i]);
			final value = emit(fieldValues[i], scope);
			pairs.push(key + ": " + value);
		}
		return "{" + pairs.join(", ") + "}";
	}

	static function emitLambda(args:Array<String>, body:HxExpr, scope:JsEmitScope):String {
		final lambdaLocals = new haxe.ds.StringMap<String>();
		final params = new Array<String>();
		for (a in args) {
			final safe = JsNameMangler.identifier(a);
			lambdaLocals.set(a, safe);
			params.push(safe);
		}
		final nested = nestedScope(scope, lambdaLocals);
		return "function(" + params.join(", ") + ") { return " + emit(body, nested) + "; }";
	}
}
