package hxhx;

private typedef UnsupportedTraceCounters = {
	var rawCount:Int;
	var fnCount:Int;
}

/**
	Stage3 unsupported-expression analysis and diagnostic formatting helpers.

	Why
	- `Stage3Compiler` still mixes orchestration with unsupported-expression counting,
	  raw-snippet collection, and error-string formatting.
	- Those helpers are diagnostic support logic, not driver control flow.

	What
	- Counts unsupported expressions across expressions, statements, functions, and modules.
	- Collects raw unsupported snippets for trace logging.
	- Formats Stage3 typer and runtime diagnostics consistently.
	- Reports internal macro defines without exposing paths, arguments, or unknown values.
	- Prints repeated type-only/no-emit diagnostic reports.

	How
	- Preserve the existing walk shapes and message formatting exactly.
	- Expose only the helper surface already used by `Stage3Compiler`.
**/
class Stage3DiagnosticsSupport {
	static inline final PRIVATE_DEFINE_MARKER = "<set>";

	static function bool01(v:Bool):String {
		return v ? "1" : "0";
	}

	public static function escapeOneLine(source:String):String {
		if (source == null)
			return "";
		return StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(source, "\\", "\\\\"), "\r", "\\r"), "\n", "\\n"), "\t", "\\t");
	}

	public static function countUnsupportedExprsInExpr(expr:Null<HxExpr>):Int {
		if (expr == null)
			return 0;
		return switch (expr) {
			case EUnsupported(_): 1;
			case EField(obj, _) | ENullSafeField(obj, _): countUnsupportedExprsInExpr(obj);
			case ECall(callee, args):
				var count = countUnsupportedExprsInExpr(callee);
				for (arg in args)
					count += countUnsupportedExprsInExpr(arg);
				count;
			case EVars(declarations):
				var count = 0;
				for (declaration in declarations)
					count += countUnsupportedExprsInExpr(HxExprVarDecl.getInitializer(declaration));
				count;
			case EVariableDeclaration(_, _, initializer, _, _, _): countUnsupportedExprsInExpr(initializer);
			case EWhile(condition, body, _, _):
				var count = countUnsupportedExprsInExpr(condition);
				for (entry in body)
					count += countUnsupportedExprsInExpr(entry);
				count;
			case EBreak(_) | EContinue(_): 0;
			case ELambda(_args, body):
				countUnsupportedExprsInExpr(body);
			case ETryCatchRaw(_raw):
				0;
			case ENew(_typePath, args):
				var count = 0;
				for (arg in args)
					count += countUnsupportedExprsInExpr(arg);
				count;
			case EUnop(_op, _fixity, inner): countUnsupportedExprsInExpr(inner);
			case EBinop(_op, left, right): countUnsupportedExprsInExpr(left) + countUnsupportedExprsInExpr(right);
			case ETernary(cond, thenExpr, elseExpr):
				countUnsupportedExprsInExpr(cond) + countUnsupportedExprsInExpr(thenExpr) + countUnsupportedExprsInExpr(elseExpr);
			case EAnon(_names, values):
				var count = 0;
				for (value in values)
					count += countUnsupportedExprsInExpr(value);
				count;
			case EArrayDecl(values):
				var count = 0;
				for (value in values)
					count += countUnsupportedExprsInExpr(value);
				count;
			case EArrayComprehension(_name, iterable, guardExpr, yieldExpr):
				countUnsupportedExprsInExpr(iterable) + (guardExpr == null ? 0 : countUnsupportedExprsInExpr(guardExpr)) +
				countUnsupportedExprsInExpr(yieldExpr);
			case EArrayAccess(arrayExpr, indexExpr):
				countUnsupportedExprsInExpr(arrayExpr) + countUnsupportedExprsInExpr(indexExpr);
			case ECast(inner, _hint):
				countUnsupportedExprsInExpr(inner);
			case EUntyped(inner):
				countUnsupportedExprsInExpr(inner);
			case _:
				0;
		}
	}

	static function collectUnsupportedExprRawInExpr(expr:Null<HxExpr>, out:Array<String>, max:Int):Void {
		if (expr == null || out.length >= max)
			return;
		switch (expr) {
			case EUnsupported(raw):
				if (out.length < max)
					out.push(raw);
			case EField(obj, _) | ENullSafeField(obj, _):
				collectUnsupportedExprRawInExpr(obj, out, max);
			case ECall(callee, args):
				collectUnsupportedExprRawInExpr(callee, out, max);
				for (arg in args)
					collectUnsupportedExprRawInExpr(arg, out, max);
			case EVars(declarations):
				for (declaration in declarations)
					collectUnsupportedExprRawInExpr(HxExprVarDecl.getInitializer(declaration), out, max);
			case EVariableDeclaration(_, _, initializer, _, _, _):
				collectUnsupportedExprRawInExpr(initializer, out, max);
			case EWhile(condition, body, _, _):
				collectUnsupportedExprRawInExpr(condition, out, max);
				for (entry in body)
					collectUnsupportedExprRawInExpr(entry, out, max);
			case EBreak(_) | EContinue(_):
			case ELambda(_args, body):
				collectUnsupportedExprRawInExpr(body, out, max);
			case ETryCatchRaw(_raw):
			case ENew(_typePath, args):
				for (arg in args)
					collectUnsupportedExprRawInExpr(arg, out, max);
			case EUnop(_op, _fixity, inner):
				collectUnsupportedExprRawInExpr(inner, out, max);
			case EBinop(_op, left, right):
				collectUnsupportedExprRawInExpr(left, out, max);
				collectUnsupportedExprRawInExpr(right, out, max);
			case ETernary(cond, thenExpr, elseExpr):
				collectUnsupportedExprRawInExpr(cond, out, max);
				collectUnsupportedExprRawInExpr(thenExpr, out, max);
				collectUnsupportedExprRawInExpr(elseExpr, out, max);
			case EAnon(_names, values):
				for (value in values)
					collectUnsupportedExprRawInExpr(value, out, max);
			case EArrayDecl(values):
				for (value in values)
					collectUnsupportedExprRawInExpr(value, out, max);
			case EArrayComprehension(_name, iterable, guardExpr, yieldExpr):
				collectUnsupportedExprRawInExpr(iterable, out, max);
				if (guardExpr != null)
					collectUnsupportedExprRawInExpr(guardExpr, out, max);
				collectUnsupportedExprRawInExpr(yieldExpr, out, max);
			case EArrayAccess(arrayExpr, indexExpr):
				collectUnsupportedExprRawInExpr(arrayExpr, out, max);
				collectUnsupportedExprRawInExpr(indexExpr, out, max);
			case ECast(inner, _hint):
				collectUnsupportedExprRawInExpr(inner, out, max);
			case EUntyped(inner):
				collectUnsupportedExprRawInExpr(inner, out, max);
			case _:
		}
	}

	static function collectUnsupportedExprRawInStmt(stmt:HxStmt, out:Array<String>, max:Int):Void {
		if (out.length >= max)
			return;
		switch (stmt) {
			case SBlock(stmts, _pos):
				for (child in stmts)
					collectUnsupportedExprRawInStmt(child, out, max);
			case SVar(_name, _hint, init, _pos):
				collectUnsupportedExprRawInExpr(init, out, max);
			case SIf(cond, thenBranch, elseBranch, _pos):
				collectUnsupportedExprRawInExpr(cond, out, max);
				collectUnsupportedExprRawInStmt(thenBranch, out, max);
				if (elseBranch != null)
					collectUnsupportedExprRawInStmt(elseBranch, out, max);
			case SWhile(cond, body, _pos):
				collectUnsupportedExprRawInExpr(cond, out, max);
				collectUnsupportedExprRawInStmt(body, out, max);
			case SDoWhile(body, cond, _pos):
				collectUnsupportedExprRawInStmt(body, out, max);
				collectUnsupportedExprRawInExpr(cond, out, max);
			case SForIn(_name, iterable, body, _pos):
				collectUnsupportedExprRawInExpr(iterable, out, max);
				collectUnsupportedExprRawInStmt(body, out, max);
			case SForKeyValue(_keyName, _valueName, iterable, body, _pos):
				collectUnsupportedExprRawInExpr(iterable, out, max);
				collectUnsupportedExprRawInStmt(body, out, max);
			case STry(tryBody, catches, _pos):
				collectUnsupportedExprRawInStmt(tryBody, out, max);
				for (catchBranch in catches)
					collectUnsupportedExprRawInStmt(catchBranch.body, out, max);
			case SBreak(_pos):
			case SContinue(_pos):
			case SThrow(expr, _pos):
				collectUnsupportedExprRawInExpr(expr, out, max);
			case SSwitch(scrutinee, _patterns, bodies, _pos):
				collectUnsupportedExprRawInExpr(scrutinee, out, max);
				for (body in bodies)
					collectUnsupportedExprRawInStmt(body, out, max);
			case SReturnVoid(_pos):
			case SReturn(expr, _pos):
				collectUnsupportedExprRawInExpr(expr, out, max);
			case SExpr(expr, _pos):
				collectUnsupportedExprRawInExpr(expr, out, max);
		}
	}

	public static function collectUnsupportedExprRawInModule(pm:ParsedModule, max:Int):Array<String> {
		final out = new Array<String>();
		final decl = pm.getDecl();
		for (cls in HxModuleDecl.getClasses(decl)) {
			for (field in HxClassDecl.getFields(cls))
				collectUnsupportedExprRawInExpr(HxFieldDecl.getInit(field), out, max);
			for (fn in HxClassDecl.getFunctions(cls)) {
				for (stmt in HxFunctionDecl.getBody(fn))
					collectUnsupportedExprRawInStmt(stmt, out, max);
			}
		}
		return out;
	}

	static function countUnsupportedExprsInStmt(stmt:HxStmt):Int {
		return switch (stmt) {
			case SBlock(stmts, _pos):
				var count = 0;
				for (child in stmts)
					count += countUnsupportedExprsInStmt(child);
				count;
			case SVar(_name, _hint, init, _pos):
				countUnsupportedExprsInExpr(init);
			case SIf(cond, thenBranch, elseBranch, _pos):
				countUnsupportedExprsInExpr(cond) + countUnsupportedExprsInStmt(thenBranch) +
				(elseBranch == null ? 0 : countUnsupportedExprsInStmt(elseBranch));
			case SWhile(cond, body, _pos):
				countUnsupportedExprsInExpr(cond) + countUnsupportedExprsInStmt(body);
			case SDoWhile(body, cond, _pos):
				countUnsupportedExprsInStmt(body) + countUnsupportedExprsInExpr(cond);
			case SForIn(_name, iterable, body, _pos):
				countUnsupportedExprsInExpr(iterable) + countUnsupportedExprsInStmt(body);
			case SForKeyValue(_keyName, _valueName, iterable, body, _pos):
				countUnsupportedExprsInExpr(iterable) + countUnsupportedExprsInStmt(body);
			case STry(tryBody, catches, _pos):
				var count = countUnsupportedExprsInStmt(tryBody);
				for (catchBranch in catches)
					count += countUnsupportedExprsInStmt(catchBranch.body);
				count;
			case SBreak(_pos):
				0;
			case SContinue(_pos):
				0;
			case SThrow(expr, _pos):
				countUnsupportedExprsInExpr(expr);
			case SSwitch(scrutinee, _patterns, bodies, _pos):
				var count = countUnsupportedExprsInExpr(scrutinee);
				for (body in bodies)
					count += countUnsupportedExprsInStmt(body);
				count;
			case SReturnVoid(_pos):
				0;
			case SReturn(expr, _pos):
				countUnsupportedExprsInExpr(expr);
			case SExpr(expr, _pos):
				countUnsupportedExprsInExpr(expr);
		}
	}

	public static function countUnsupportedExprsInModule(pm:ParsedModule):Int {
		var count = 0;
		final decl = pm.getDecl();
		for (cls in HxModuleDecl.getClasses(decl)) {
			for (field in HxClassDecl.getFields(cls))
				count += countUnsupportedExprsInExpr(HxFieldDecl.getInit(field));
			for (fn in HxClassDecl.getFunctions(cls)) {
				for (stmt in HxFunctionDecl.getBody(fn))
					count += countUnsupportedExprsInStmt(stmt);
			}
		}
		return count;
	}

	public static function countUnsupportedExprsInFunction(fn:HxFunctionDecl):Int {
		var count = 0;
		for (stmt in HxFunctionDecl.getBody(fn))
			count += countUnsupportedExprsInStmt(stmt);
		return count;
	}

	public static function newUnsupportedTraceCounters():UnsupportedTraceCounters {
		return {rawCount: 0, fnCount: 0};
	}

	public static function reportUnsupportedForParsedModule(pm:ParsedModule, filePath:String, unsupportedFileIndex:Int, traceUnsupported:Bool,
			counters:UnsupportedTraceCounters, ?output:CompilationRequestOutput):Int {
		final unsupportedInFile = countUnsupportedExprsInModule(pm);
		if (unsupportedInFile <= 0)
			return 0;

		CompilationRequestOutput.writeStdoutLine(output,
			"unsupported_file["
			+ unsupportedFileIndex
			+ "]="
			+ filePath
			+ " header_only="
			+ bool01(HxModuleDecl.getHeaderOnly(pm.getDecl()))
			+ " unsupported_exprs="
			+ unsupportedInFile);

		if (traceUnsupported) {
			final cls = HxModuleDecl.getMainClass(pm.getDecl());
			for (fn in HxClassDecl.getFunctions(cls)) {
				final fnUnsupported = countUnsupportedExprsInFunction(fn);
				if (fnUnsupported <= 0)
					continue;
				CompilationRequestOutput.writeStdoutLine(output,
					"unsupported_fn["
					+ counters.fnCount
					+ "]="
					+ filePath
					+ ":"
					+ HxFunctionDecl.getName(fn)
					+ " unsupported_exprs="
					+ fnUnsupported);
				counters.fnCount += 1;
				if (counters.fnCount >= 50)
					break;
			}
			for (raw in collectUnsupportedExprRawInModule(pm, 20)) {
				final escaped = escapeOneLine(raw);
				CompilationRequestOutput.writeStdoutLine(output,
					"unsupported_expr["
					+ counters.rawCount
					+ "]="
					+ filePath
					+ ":raw="
					+ escaped
					+ " len="
					+ (raw == null ? 0 : raw.length));
				counters.rawCount += 1;
				if (counters.rawCount >= 50)
					break;
			}
		}

		return unsupportedInFile;
	}

	public static function parsedMethodCount(pm:ParsedModule):Int {
		return HxClassDecl.getFunctions(HxModuleDecl.getMainClass(pm.getDecl())).length;
	}

	public static function printTypedFunctionSummary(rootTyped:TypedModule, ?output:CompilationRequestOutput):Void {
		final fns = rootTyped.getEnv().getMainClass().getFunctions();
		for (i in 0...fns.length) {
			final tf = fns[i];
			final locals = tf.getLocals();
			final localsParts = new Array<String>();
			for (l in locals)
				localsParts.push(l.getName() + ":" + l.getType().toString());
			final params = tf.getParams();
			final paramParts = new Array<String>();
			for (p in params)
				paramParts.push(p.getName() + ":" + p.getType().toString());
			CompilationRequestOutput.writeStdoutLine(output,
				"typed_fn["
				+ i
				+ "]="
				+ tf.getName()
				+ " args="
				+ paramParts.join(",")
				+ " locals="
				+ localsParts.join(",")
				+ " ret="
				+ tf.getReturnType().toString()
				+ " inferred="
				+ tf.getReturnExprType().toString());
		}
	}

	/**
		Print a privacy-safe summary of internal macro defines.

		A macro define is a name and value that the compiler gives to compile-time
		code. Some values contain source paths, user arguments, or environment data.
		Ordinary compiler output therefore reports only that those values exist.

		The small allowlist contains lifecycle flags whose complete contract is the
		exact value `1`. An unexpected value also becomes `<set>`. This function does
		not change `MacroState`, so macro execution still receives the original value.
	**/
	public static function printHxMacroDefines(prefix:String, ?output:CompilationRequestOutput):Void {
		for (name in hxhx.macro.MacroState.listDefineNames()) {
			if (StringTools.startsWith(name, "HXHX_")) {
				final value = hxhx.macro.MacroState.definedValue(name);
				CompilationRequestOutput.writeStdoutLine(output, prefix + "[" + name + "]=" + macroDefineDiagnosticValue(name, value));
			}
		}
	}

	static function macroDefineDiagnosticValue(name:String, value:String):String {
		final isStableLifecycleFlag = switch (name) {
			case "HXHX_SMOKE" | "HXHX_AFTER_TYPING" | "HXHX_ON_GENERATE" | "HXHX_EXTERNAL" | "HXHX_PLUGIN_FIXTURE" | "HXHX_PLUGIN_FIXTURE_AFTER_TYPING" |
				"HXHX_PLUGIN_FIXTURE_ON_GENERATE" | "HXHX_HAXELIB_INIT" | "HXHX_HAXELIB_INIT_AFTER_TYPING" | "HXHX_HAXELIB_INIT_ON_GENERATE" |
				"HXHX_HAXELIB_INIT_AFTER_GENERATE" | "HXHX_HXGEN":
				true;
			case _:
				false;
		};
		return isStableLifecycleFlag && value == "1" ? "1" : PRIVATE_DEFINE_MARKER;
	}

	public static function formatException(e:TyperError):String {
		final pos = e.getPos();
		final line = pos == null ? 0 : pos.getLine();
		final col = pos == null ? 0 : pos.getColumn();
		return e.getFilePath() + ":" + line + ":" + col + ": " + e.getMessage();
	}

	public static function rawTyperDiagnostic(e:TyperError):Null<String> {
		return TyperStage.extractRawDiagnostic(e.getMessage());
	}

	/**
		Why: backend and macro execution can throw values that cross Haxe's typed
		exception boundary as `Dynamic`, and diagnostics must still print a stable,
		user-facing message.
		What: converts that boundary value into a string without letting `Dynamic`
		escape into the rest of Stage3 orchestration.
		How: preserve `haxe.Exception.message` when present, then fall back to
		`Std.string` for other thrown values.
	**/
	public static function formatDynamicException(error:Dynamic):String {
		if (Std.isOfType(error, haxe.Exception)) {
			final ex:haxe.Exception = cast error;
			if (ex.message != null && ex.message.length > 0)
				return ex.message;
		}
		final reflectedMessage = try Reflect.field(error, "message") catch (_:Dynamic) null;
		if (reflectedMessage != null) {
			final message = Std.string(reflectedMessage);
			if (message.length > 0)
				return message;
		}
		return Std.string(error);
	}
}
