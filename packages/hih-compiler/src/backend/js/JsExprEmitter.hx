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
			case ESwitch(scrutinee, cases):
				emitSwitchExpr(scrutinee, cases, scope);
			case ESwitchRaw(_):
				unsupported("ESwitchRaw");
			case ETryCatchRaw(_):
				unsupported("ETryCatchRaw");
			case ERange(_, _):
				unsupported("ERange");
			case EArrayComprehension(_, _, _):
				unsupported("EArrayComprehension");
			case ENew(typePath, args):
				emitNew(typePath, args, scope);
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

	static function resolveTypePath(typePath:String, scope:JsEmitScope):Null<String> {
		if (typePath == null || typePath.length == 0) return null;
		if (scope != null) {
			final direct = scope.resolveClassRef(typePath);
			if (direct != null) return direct;
			final parts = typePath.split(".");
			if (parts.length > 0) {
				final simple = scope.resolveClassRef(parts[parts.length - 1]);
				if (simple != null) return simple;
			}
		}
		return null;
	}

	static function emitNew(typePath:String, args:Array<HxExpr>, scope:JsEmitScope):String {
		final argsJs = args.map(a -> emit(a, scope)).join(", ");
		switch (typePath) {
			case "Array":
				if (args.length == 0) return "[]";
				return "new Array(" + argsJs + ")";
			case _:
		}

		final ctor = resolveTypePath(typePath, scope);
		if (ctor == null) {
			unsupported("ENew(" + typePath + ")");
		}
		return "new " + ctor + "(" + argsJs + ")";
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

	static function emitSwitchExpr(
		scrutinee:HxExpr,
		cases:Array<{ pattern:HxSwitchPattern, expr:HxExpr }>,
		scope:JsEmitScope
	):String {
		final out = new Array<String>();
		out.push("(function () {");
		out.push("var __sw = " + emit(scrutinee, scope) + ";");

		var isFirst = true;
		for (c in cases) {
			final lowered = JsSwitchPatternLowering.lower(c.pattern, "__sw");
			final head = isFirst ? "if" : "else if";

			var branchScope = scope;
			var bindPrefix = "";
			if (lowered.bindName != null) {
				final locals = new haxe.ds.StringMap<String>();
				final bindSafe = "__sw_bind_" + JsNameMangler.identifier(lowered.bindName);
				locals.set(lowered.bindName, bindSafe);
				branchScope = nestedScope(scope, locals);
				bindPrefix = "var " + bindSafe + " = __sw; ";
			}

			out.push(head + " (" + lowered.cond + ") { " + bindPrefix + "return " + emit(c.expr, branchScope) + "; }");
			isFirst = false;
		}

		out.push("return null;");
		out.push("})()");
		return out.join(" ");
	}
}
