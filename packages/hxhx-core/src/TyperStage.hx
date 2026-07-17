private typedef TyMethodCallResolution = {
	final type:TyType;
	final declaration:Null<TyDeclarationInfo>;
};

private typedef TypedClassBuildResult = {
	final classes:Array<TypedClass>;
	final mainFunctions:Array<TyFunctionEnv>;
};

/**
	Stage 2 typer skeleton.

	Why:
	- The “typer” is the heart of the compiler and the largest bootstrapping
	  milestone.
	- Even as a stub, we keep the API shaped like the real thing: consume a parsed
	  module and return a typed module.
**/
class TyperStage {
	static inline function isStrict():Bool {
		final v = Sys.getEnv("HXHX_TYPER_STRICT");
		return v == "1" || v == "true" || v == "yes";
	}

	static function arrayElementType(t:TyType):Null<TyType> {
		if (t == null)
			return null;
		final arguments = t.getTypeArguments();
		if (arguments.length == 1) {
			final identity = t.getNominalIdentity();
			final containerName = identity == null ? t.getUnresolvedPath() : identity.getCanonicalName();
			if (containerName == "Array" || containerName == "haxe.Array")
				return arguments[0];
		}
		final d = t.getDisplay();
		if (d == null)
			return null;
		if (!StringTools.startsWith(d, "Array<"))
			return null;
		if (!StringTools.endsWith(d, ">"))
			return null;
		final inner = StringTools.trim(d.substr("Array<".length, d.length - "Array<".length - 1));
		return inner.length == 0 ? TyType.unknown() : TyType.fromHintText(inner);
	}

	static function typeFromHintInContext(hint:String, ctx:TyperContext):TyType {
		final raw = hint == null ? "" : StringTools.trim(hint);
		if (raw.length == 0)
			return TyType.unknown();
		// Keep primitive-like names stable.
		switch (raw) {
			case "Int", "Float", "Bool", "String", "Void", "Dynamic", "Null":
				return TyType.fromHintText(raw);
			case _:
		}

		// Best-effort: resolve short names against the current module context.
		return resolveTypeInContext(TyType.fromHintText(raw), ctx);
	}

	static function resolveTypeInContext(type:TyType, ctx:TyperContext):TyType {
		if (type == null)
			return TyType.unknown();
		if (type.isNullable())
			return TyType.nullable(resolveTypeInContext(type.getNullableInner(), ctx), type.getDisplay());
		if (type.isFunction()) {
			final result = type.getFunctionReturn();
			return TyType.functionType([
				for (argument in type.getFunctionArguments())
					resolveTypeInContext(argument, ctx)
			],
				result == null ? TyType.unknown() : resolveTypeInContext(result, ctx), type.getDisplay());
		}
		if (!type.isUnresolved())
			return type;
		final arguments = [for (argument in type.getTypeArguments()) resolveTypeInContext(argument, ctx)];
		final nominal = ctx == null ? null : ctx.resolveType(type.getUnresolvedPath());
		return nominal == null ? TyType.unresolved(type.getUnresolvedPath(), arguments,
			type.getDisplay()) : TyType.nominal(nominal.getIdentity(), arguments, type.getDisplay());
	}

	static function nominalInfoForType(index:TyperIndex, type:TyType):Null<TyNominalInfo> {
		if (index == null || type == null)
			return null;
		final identity = type.getNominalIdentity();
		return identity == null ? index.getByFullName(type.getDisplay()) : index.getByFullName(identity.getCanonicalName());
	}

	/**
		Resolve a member read without mistaking a declared method for a missing data
		field. Exact calls keep their declaration identity separately; until the
		overloaded method-value selection grows an exact declaration rule, a method
		value has an explicitly unknown type rather than an "unknown field" error.
	**/
	static function declaredMemberReadType(owner:TyNominalInfo, name:String, isStatic:Bool):Null<TyType> {
		if (owner == null)
			return null;
		final fieldType = owner.fieldType(name);
		if (fieldType != null)
			return fieldType;
		final method = isStatic ? owner.staticMethod(name) : owner.instanceMethod(name);
		return method == null ? null : TyType.unknown();
	}

	static function accessorPropertyForAccess(expression:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, position:HxPos):Null<TyPropertyInfo> {
		var receiver:Null<HxExpr> = null;
		var field = "";
		switch (expression) {
			case EField(exactReceiver, exactField):
				receiver = exactReceiver;
				field = exactField;
			case _:
		}
		if (receiver == null)
			return null;
		final owner = switch (receiver) {
			case EThis: ctx.currentClass();
			case _: nominalInfoForType(ctx.getIndex(), inferExprType(receiver, scope, ctx, position));
		};
		final property = owner == null ? null : owner.propertyInfo(field);
		return property != null && property.usesExplicitAccessors() ? property : null;
	}

	static function currentThisType(ctx:TyperContext):TyType {
		if (ctx == null)
			return TyType.unknown();
		final current = ctx.currentClass();
		if (current == null)
			return TyType.unknown();
		if (Std.isOfType(current, TyAbstractInfo))
			return (cast current : TyAbstractInfo).getUnderlyingType();
		return TyType.nominal(current.getIdentity(), [], current.getFullName());
	}

	static function declarePatternBindings(scope:TyFunctionEnv, pattern:HxSwitchPattern, baseTy:TyType):Void {
		switch (pattern) {
			case PBind(name):
				scope.declareLocal(name, baseTy == null || baseTy.isUnknown() ? TyType.fromHintText("Dynamic") : baseTy);
			case PEnumExtract(_name, args):
				if (args != null) {
					for (arg in args)
						declarePatternBindings(scope, arg, TyType.fromHintText("Dynamic"));
				}
			case PObject(_fieldNames, fieldPatterns):
				if (fieldPatterns != null) {
					for (fieldPattern in fieldPatterns)
						declarePatternBindings(scope, fieldPattern, TyType.fromHintText("Dynamic"));
				}
			case PCapture(name, inner):
				scope.declareLocal(name, baseTy == null || baseTy.isUnknown() ? TyType.fromHintText("Dynamic") : baseTy);
				declarePatternBindings(scope, inner, baseTy);
			case PArray(items):
				if (items != null) {
					for (item in items)
						declarePatternBindings(scope, item, TyType.fromHintText("Dynamic"));
				}
			case PExtractor(_, resultPattern):
				declarePatternBindings(scope, resultPattern, TyType.fromHintText("Dynamic"));
			case PLengthGuard(inner, _, _), PStartsWithGuard(inner, _, _), PIntEqualsGuard(inner, _, _), PIntCompareGuard(inner, _, _, _),
				PParsedIntSwitchGuard(inner, _, _, _), PUnsupportedGuard(inner):
				declarePatternBindings(scope, inner, baseTy);
			case POr(patterns):
				if (patterns != null) {
					for (p in patterns)
						declarePatternBindings(scope, p, baseTy);
				}
			case _:
		}
	}

	static function buildTypedClasses(parsed:ParsedModule, index:TyperIndex, loader:ModuleLoader, modulePath:String,
			deferProgramLowering:Bool = false):TypedClassBuildResult {
		final declaration = parsed.getDecl();
		final packagePath = HxModuleDecl.getPackagePath(declaration);
		final imports = HxModuleDecl.getImports(declaration);
		final mainClass = HxModuleDecl.getMainClass(declaration);
		final typedClasses = new Array<TypedClass>();
		var mainFunctions = new Array<TyFunctionEnv>();

		for (classDeclaration in HxModuleDecl.getClasses(declaration)) {
			final className = HxClassDecl.getName(classDeclaration);
			final semanticInfo = index == null ? null : index.getForSourceClass(classDeclaration);
			final classFullName = semanticInfo == null ? ((packagePath == null || packagePath.length == 0) ? className : packagePath
				+ "."
				+ className) : semanticInfo.getFullName();
			final context = new TyperContext(index, parsed.getFilePath(), modulePath, packagePath, imports, classFullName, loader);
			final typedFunctions = new Array<TypedFunction>();
			final functionEnvironments = new Array<TyFunctionEnv>();
			final sourceFunctions = HxClassDecl.getFunctions(classDeclaration);
			for (functionIndex in 0...sourceFunctions.length) {
				final sourceFunction = sourceFunctions[functionIndex];
				final functionEnvironment = typeFunction(sourceFunction, context);
				functionEnvironments.push(functionEnvironment);
				final semanticDeclaration = semanticInfo == null ? null : semanticInfo.declarationForSource(sourceFunction);
				final typeResolver:TypedExprTypeResolver = function(expression, position, lexicalEnvironment) {
					return inferExprType(expression, lexicalEnvironment.copyForInference(), context, position);
				};
				final callResolver:TypedCallDeclarationResolver = function(callee, arguments, position, lexicalEnvironment) {
					return resolveCallDeclaration(callee, arguments, lexicalEnvironment.copyForInference(), context, position);
				};
				typedFunctions.push(TypedBodyBuilder.buildFunction(className, functionIndex, sourceFunction, semanticDeclaration, functionEnvironment,
					typeResolver, callResolver));
			}
			if (classDeclaration == mainClass)
				mainFunctions = functionEnvironments;
			typedClasses.push(new TypedClass(classDeclaration, semanticInfo, typedFunctions));
		}

		final loweredClasses = index == null
			|| deferProgramLowering ? typedClasses : TypedAbstractOperatorLowering.lowerClasses(typedClasses, index, parsed.getFilePath());
		return {classes: loweredClasses, mainFunctions: mainFunctions};
	}

	/**
		Type a parsed module into a minimal `TypedModule`.

		Why:
		- Later stages (macro expansion + backend codegen) need a stable typed
		  surface, even before we implement the full Haxe type system.
		- For `hih-compiler` acceptance, we care about determinism and basic type
		  inference for literals and simple `return` expressions.

		What:
		- Builds a `TyModuleEnv` containing:
		  - package/import summary
		  - a `TyClassEnv` with per-function environments

		How:
		- Stage 3: we build a real local scope per function (params + locals) and
		  infer return types when no explicit return hint exists.
	**/
	public static function typeModule(m:ParsedModule):TypedModule {
		final decl = m.getDecl();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final imports = HxModuleDecl.getImports(decl);
		final cls = HxModuleDecl.getMainClass(decl);
		final built = buildTypedClasses(m, null, null, "");
		final classEnv = new TyClassEnv(HxClassDecl.getName(cls), built.mainFunctions);
		final env = new TyModuleEnv(pkg, imports, classEnv);
		return new TypedModule(m, env, built.classes);
	}

	/**
		Type a resolved module using a shared program index.

		Why
		- Stage 3.3 needs cross-module knowledge (imports, class fields, statics)
		  to type `Util.ping()` and `this.x` in upstream-shaped code.
	**/
	public static function typeResolvedModule(m:ResolvedModule, index:TyperIndex, ?loader:ModuleLoader, deferProgramLowering:Bool = false):TypedModule {
		final pm = ResolvedModule.getParsed(m);
		final decl = pm.getDecl();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final imports = HxModuleDecl.getImports(decl);
		final cls = HxModuleDecl.getMainClass(decl);
		final built = buildTypedClasses(pm, index, loader, ResolvedModule.getModulePath(m), deferProgramLowering);
		final classEnv = new TyClassEnv(HxClassDecl.getName(cls), built.mainFunctions);
		final env = new TyModuleEnv(pkg, imports, classEnv);
		return new TypedModule(pm, env, built.classes);
	}

	static function typeFunction(fn:HxFunctionDecl, ctx:TyperContext):TyFunctionEnv {
		// Stage 3 local scope:
		// - parameters (type hints, if any)
		// - locals (not parsed yet; reserved for later)
		final params = new Array<TySymbol>();
		for (arg in HxFunctionDecl.getArgs(fn)) {
			final name = HxFunctionArg.getName(arg);
			final ty = typeFromHintInContext(HxFunctionArg.getTypeHint(arg), ctx);
			params.push(new TySymbol(name, ty));
		}

		final locals = new Array<TySymbol>();
		final scope = new TyFunctionEnv(HxFunctionDecl.getName(fn), params, locals, TyType.unknown(), TyType.unknown());

		final semanticBody = TypedBodyBuilder.expandStructuralStatements(HxFunctionDecl.getBody(fn));
		final returnExprTy = inferReturnType(semanticBody, scope, ctx);
		final retHintText = HxFunctionDecl.getReturnTypeHint(fn);
		final retTy = if (retHintText != null && retHintText.length > 0) {
			final hinted = typeFromHintInContext(retHintText, ctx);
			// If we couldn't infer a concrete return type (e.g. because the parser produced an
			// empty/unsupported body), keep bring-up moving by trusting the explicit hint.
			if (!returnExprTy.isUnknown()) {
				final unified = TyType.unify(hinted, returnExprTy);
				if (unified == null) {
					if (isStrict()) {
						throw new TyperError(ctx.getFilePath(), HxPos.unknown(),
							"return type hint " + hinted + " conflicts with inferred return " + returnExprTy);
					}
					// Bring-up default: trust the explicit hint and continue.
				}
			}
			hinted;
		} else {
			// No explicit hint:
			// - If we inferred a return type from `return` statements, use it.
			// - Otherwise, default to `Void` to match the common `function f() { ... }` / `static function main()` shape.
			//
			// Bring-up heuristic:
			// - The native frontend protocol can capture a "first return string literal" even when
			//   we can't parse a complex body (e.g. a `switch` with returns in cases).
			// - If present, treat the function as returning `String` instead of collapsing to `Void`.
			if (!returnExprTy.isUnknown()) {
				returnExprTy;
			} else {
				final retStr = HxFunctionDecl.getReturnStringLiteral(fn);
				(retStr != null && retStr.length > 0) ? TyType.fromHintText("String") : TyType.fromHintText("Void");
			}
		}

		return new TyFunctionEnv(HxFunctionDecl.getName(fn), params, locals, retTy, returnExprTy);
	}

	static function inferReturnType(statements:Array<HxStmt>, scope:TyFunctionEnv, ctx:TyperContext):TyType {
		var out:Null<TyType> = null;

		function unifyInto(t:TyType, pos:HxPos):Void {
			if (out == null) {
				out = t;
				return;
			}
			final u = TyType.unify(out, t);
			if (u == null) {
				if (isStrict()) {
					throw new TyperError(ctx.getFilePath(), pos, "incompatible return types: " + out + " vs " + t);
				}
				// Bring-up default: collapse to Dynamic to keep typing moving.
				out = TyType.fromHintText("Dynamic");
				return;
			}
			out = u;
		}

		function typeStmt(s:HxStmt):Void {
			switch (s) {
				case SBlock(stmts, _pos):
					for (ss in stmts)
						typeStmt(ss);
				case SSwitch(scrutinee, patterns, bodies, pos):
					// Bring-up: type-check the scrutinee, then each case body.
					// Binder patterns declare a best-effort local for the body.
					final scrutTy = inferExprType(scrutinee, scope, ctx, pos);
					if (patterns != null && bodies != null) {
						final count = patterns.length < bodies.length ? patterns.length : bodies.length;
						for (i in 0...count) {
							final pattern = patterns[i];
							final body = bodies[i];
							declarePatternBindings(scope, pattern, scrutTy);
							typeStmt(body);
						}
					}
				case SIf(cond, thenBranch, elseBranch, pos):
					// Best-effort: ensure the condition is at least type-checked for locals.
					inferExprType(cond, scope, ctx, pos);
					typeStmt(thenBranch);
					if (elseBranch != null)
						typeStmt(elseBranch);
				case SWhile(cond, body, pos):
					inferExprType(cond, scope, ctx, pos);
					typeStmt(body);
				case SDoWhile(body, cond, pos):
					typeStmt(body);
					inferExprType(cond, scope, ctx, pos);
				case STry(tryBody, catches, _):
					typeStmt(tryBody);
					for (c in catches) {
						scope.declareLocal(c.name, TyType.fromHintText("Dynamic"));
						typeStmt(c.body);
					}
				case SBreak(_):
				case SContinue(_):
				case SForIn(name, iterable, body, pos):
					// Bring-up: type-check the iterable expression and bind the loop variable.
					//
					// We intentionally model the loop variable as a function-local symbol for now
					// (not a nested scope) so later statements can still reference it during bring-up.
					final iterableTy = inferExprType(iterable, scope, ctx, pos);
					final loopTy = switch (iterable) {
						case ERange(_, _):
							TyType.fromHintText("Int");
						case _:
							// Best-effort: if we can see an `Array<T>` element type, propagate it
							// to the loop variable so string/number-heavy harness code can emit.
							final elem = arrayElementType(iterableTy);
							(elem != null && !elem.isUnknown()) ? elem : TyType.fromHintText("Dynamic");
					}
					scope.declareLocal(name, loopTy);
					typeStmt(body);
				case SForKeyValue(keyName, valueName, iterable, body, pos):
					inferExprType(iterable, scope, ctx, pos);
					scope.declareLocal(keyName, TyType.fromHintText("String"));
					scope.declareLocal(valueName, TyType.fromHintText("Dynamic"));
					typeStmt(body);
				case SVar(name, typeHint, init, pos):
					// Declare first so subsequent statements can reference the symbol deterministically.
					final hinted = typeFromHintInContext(typeHint, ctx);
					final sym = scope.declareLocal(name, hinted);
					if (init != null) {
						final initTy = inferExprType(init, scope, ctx, pos);
						final u = TyType.unify(sym.getType(), initTy);
						if (u == null) {
							if (isStrict()) {
								throw new TyperError(ctx.getFilePath(), pos,
									"initializer type " + initTy + " is not compatible with local " + name + ":" + sym.getType());
							}
							// A written local type remains the semantic contract in permissive
							// bring-up mode. Conversion typing is incomplete, so replacing that
							// identity with Dynamic would erase the exact abstract needed by
							// later operator binding.
							return;
						}
						sym.setType(u);
					}
				case SReturnVoid(pos):
					unifyInto(TyType.fromHintText("Void"), pos);
				case SReturn(e, pos):
					final t = inferExprType(e, scope, ctx, pos);
					// Bring-up rule: if we *see* `return <expr>` but can't infer a concrete type for
					// the expression yet, treat it as `Dynamic` instead of leaving the return type
					// as `Unknown`.
					//
					// Why
					// - A function that returns an expression is almost never intended to be `Void`.
					// - Leaving it as `Unknown` causes `typeFunction` to default to `Void`, which then
					//   makes the Stage3 bootstrap emitter produce OCaml like:
					//     `let f () : unit = <int expr>`
					//   and fail typechecking.
					unifyInto(t.isUnknown() ? TyType.fromHintText("Dynamic") : t, pos);
				case SExpr(e, pos):
					inferExprType(e, scope, ctx, pos);
				case SThrow(expr, pos):
					inferExprType(expr, scope, ctx, pos);
			}
		}

		for (s in statements)
			typeStmt(s);
		// If we saw no explicit returns, the true return type depends on surrounding typing rules.
		// For bootstrap bring-up we return `Unknown` here so `typeFunction` can:
		// - trust an explicit return type hint, or
		// - default to `Void` when no hint is provided.
		return out == null ? TyType.unknown() : out;
	}

	/**
		Best-effort: extract a dotted name from a field chain expression.

		Why
		- Stage3 must recognize fully-qualified type paths used directly in expressions, e.g.:
		  `runci.targets.Macro.run(args)` (no import for `runci.targets.Macro`).
		- The lazy ModuleLoader can load such modules on-demand, but only if we call
		  `ctx.resolveType(...)` with the dotted type path.

		What
		- Converts `EIdent("runci")`, `EField(_, "targets")`, `EField(_, "Macro")` into:
		  `"runci.targets.Macro"`.

		How
		- Conservative: only supports `EIdent` + `EField` chains.
		- Returns an empty string for non-chain expressions.
	**/
	static function dottedFieldPath(e:HxExpr):String {
		return switch (e) {
			case EIdent(name):
				name == null ? "" : name;
			case EField(obj, field):
				final base = dottedFieldPath(obj);
				base.length == 0 ? "" : (base + "." + field);
			case _:
				"";
		}
	}

	static function isUpperStartName(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		final c = name.charCodeAt(0);
		return c >= "A".code && c <= "Z".code;
	}

	static function isTypeErrorProbeCallee(callee:HxExpr):Bool {
		final path = dottedFieldPath(callee);
		return path == "typeError" || path == "HelperMacros.typeError" || StringTools.endsWith(path, ".HelperMacros.typeError");
	}

	/** Type a macro diagnostic probe without making its enclosing `try` value-producing. **/
	static function typeErrorProbe(expression:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, position:HxPos):Void {
		inferExprType(expression, scope.copyForInference(), ctx, position);
	}

	public static inline var RAW_DIAGNOSTIC_PREFIX:String = "__HXHX_RAW_DIAGNOSTIC__:";

	public static function extractRawDiagnostic(message:String):Null<String> {
		if (message == null || !StringTools.startsWith(message, RAW_DIAGNOSTIC_PREFIX))
			return null;
		return message.substr(RAW_DIAGNOSTIC_PREFIX.length);
	}

	static function sourceLine(filePath:String, line:Int):String {
		if (filePath == null || filePath.length == 0 || line <= 0 || !sys.FileSystem.exists(filePath))
			return "";
		final lines = sys.io.File.getContent(filePath).split("\n");
		return line <= lines.length ? lines[line - 1] : "";
	}

	static function diagnosticFileName(filePath:String):String {
		if (filePath == null || filePath.length == 0)
			return "<unknown>";
		return haxe.io.Path.withoutDirectory(filePath);
	}

	static function isRangeIdentCode(code:Int):Bool {
		return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57) || code == 95;
	}

	static function callRange(filePath:String, pos:HxPos):{start:Int, end:Int} {
		final start = pos == null || pos.getColumn() <= 0 ? 0 : pos.getColumn() - 1;
		final line = sourceLine(filePath, pos == null ? 0 : pos.getLine());
		if (line.length == 0)
			return {start: start, end: start};
		var startIndex = start > 0 ? start : 0;
		if (startIndex > 0
			&& startIndex < line.length
			&& isRangeIdentCode(line.charCodeAt(startIndex - 1))
			&& isRangeIdentCode(line.charCodeAt(startIndex))) {
			startIndex -= 1;
		}
		final rest = startIndex < line.length ? line.substr(startIndex) : "";
		var end = line.length;
		final semicolon = rest.indexOf(";");
		if (semicolon >= 0)
			end = start + semicolon;
		return {start: start, end: end};
	}

	static function declarationLineRange(filePath:String, pos:HxPos):{start:Int, end:Int} {
		final start = pos == null || pos.getColumn() <= 0 ? 1 : pos.getColumn();
		final line = sourceLine(filePath, pos == null ? 0 : pos.getLine());
		if (line.length == 0)
			return {start: start, end: start};
		final end = line.length < start ? start : line.length;
		return {start: start, end: end};
	}

	static function functionNameRange(filePath:String, name:String, pos:HxPos):{start:Int, end:Int} {
		final line = sourceLine(filePath, pos == null ? 0 : pos.getLine());
		final idx = line.indexOf(name);
		final start = idx >= 0 ? idx + 1 : (pos == null || pos.getColumn() <= 0 ? 1 : pos.getColumn());
		return {start: start, end: start + name.length};
	}

	static function renderArgType(sig:TyFunSig, index:Int):String {
		final args = sig.getArgs();
		final optional = sig.getArgOptional();
		final raw = index < args.length ? args[index].getDisplay() : "Dynamic";
		if (index < optional.length && optional[index] && !StringTools.startsWith(raw, "Null<"))
			return "Null<" + raw + ">";
		return raw;
	}

	static function renderOverloadCandidate(filePath:String, sig:TyFunSig):String {
		final pos = sig.getPos();
		final range = functionNameRange(filePath, sig.getName(), pos);
		final names = sig.getArgNames();
		final optional = sig.getArgOptional();
		final args = sig.getArgs();
		final parts = new Array<String>();
		for (i in 0...args.length) {
			final argName = i < names.length ? names[i] : ("arg" + i);
			final prefix = (i < optional.length && optional[i]) ? "?" : "";
			parts.push(prefix + argName + " : " + renderArgType(sig, i));
		}
		return diagnosticFileName(filePath) + ":" + (pos == null ? 0 : pos.getLine()) + ": characters " + range.start + "-" + range.end + " : ... ("
			+ parts.join(", ") + ") -> " + sig.getReturnType().getDisplay();
	}

	static function normalizeOverloadTypeName(ty:TyType):String {
		if (ty == null)
			return "Unknown";
		var s = StringTools.trim(ty.getDisplay());
		while (StringTools.startsWith(s, "Null<") && StringTools.endsWith(s, ">"))
			s = StringTools.trim(s.substr(5, s.length - 6));
		return s;
	}

	static function normalizeFunctionTypeSegment(s:String):String {
		var out = StringTools.trim(s);
		while (StringTools.startsWith(out, "(") && StringTools.endsWith(out, ")"))
			out = StringTools.trim(out.substr(1, out.length - 2));
		return out;
	}

	static function functionTypeSegments(display:String):Array<String> {
		final trimmed = StringTools.trim(display);
		if (trimmed.indexOf("->") < 0)
			return [];
		final out = new Array<String>();
		for (part in trimmed.split("->")) {
			final segment = normalizeFunctionTypeSegment(part);
			if (segment.length == 0)
				return [];
			out.push(segment);
		}
		return out.length < 2 ? [] : out;
	}

	static function flatOverloadTypeScore(exp:String, act:String):Int {
		if (exp == act)
			return 4;
		if (exp == "Unknown" || act == "Unknown" || exp == "Dynamic" || act == "Dynamic")
			return 0;
		if ((exp == "Float" && act == "Int") || (exp == "Int" && act == "Float"))
			return 1;
		return -1;
	}

	static function functionOverloadTypeScore(exp:String, act:String):Int {
		final expParts = functionTypeSegments(exp);
		final actParts = functionTypeSegments(act);
		if (expParts.length == 0 && actParts.length == 0)
			return flatOverloadTypeScore(exp, act);
		if (expParts.length == 0 || actParts.length == 0 || expParts.length != actParts.length)
			return -1;
		var score = 0;
		for (i in 0...expParts.length) {
			final partScore = flatOverloadTypeScore(expParts[i], actParts[i]);
			if (partScore < 0)
				return -1;
			score += partScore;
		}
		return score;
	}

	static function overloadArgScore(expected:TyType, actual:TyType):Int {
		if (expected != null && actual != null && expected.getSemanticKey() == actual.getSemanticKey())
			return 4;
		if (expected.isFunction() || actual.isFunction()) {
			if (!expected.isFunction() || !actual.isFunction())
				return -1;
			final expectedArguments = expected.getFunctionArguments();
			final actualArguments = actual.getFunctionArguments();
			if (expectedArguments.length != actualArguments.length)
				return -1;
			var score = 0;
			for (index in 0...expectedArguments.length) {
				final argumentScore = overloadArgScore(expectedArguments[index], actualArguments[index]);
				if (argumentScore < 0)
					return -1;
				score += argumentScore;
			}
			final expectedReturn = expected.getFunctionReturn();
			final actualReturn = actual.getFunctionReturn();
			if (expectedReturn == null || actualReturn == null)
				return -1;
			final returnScore = overloadArgScore(expectedReturn, actualReturn);
			return returnScore < 0 ? -1 : score + returnScore;
		}
		final exp = normalizeOverloadTypeName(expected);
		final act = normalizeOverloadTypeName(actual);
		return functionOverloadTypeScore(exp, act);
	}

	static function overloadCandidateScore(sig:TyFunSig, argTypes:Array<TyType>, suppliedArity:Int):Int {
		if (!sig.acceptsArity(suppliedArity))
			return -1;
		final expected = sig.getArgs();
		var score = 0;
		for (i in 0...suppliedArity) {
			final argScore = overloadArgScore(i < expected.length ? expected[i] : TyType.fromHintText("Dynamic"),
				i < argTypes.length ? argTypes[i] : TyType.unknown());
			if (argScore < 0)
				return -1;
			score += argScore;
		}
		return score;
	}

	static function resolveMethodCall(c:TyNominalInfo, field:String, isStatic:Bool, args:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext,
			pos:HxPos):TyMethodCallResolution {
		final argTypes = new Array<TyType>();
		for (a in args)
			argTypes.push(inferExprType(a, scope, ctx, pos));

		final candidates = isStatic ? c.staticMethodCandidates(field) : c.instanceMethodCandidates(field);
		if (candidates.length == 0)
			return {type: TyType.unknown(), declaration: null};

		final arityMatches = new Array<TyFunSig>();
		var bestScore = -1;
		final bestMatches = new Array<TyFunSig>();
		for (candidate in candidates) {
			final score = overloadCandidateScore(candidate, argTypes, args.length);
			if (score >= 0) {
				arityMatches.push(candidate);
				if (score > bestScore) {
					bestScore = score;
					bestMatches.resize(0);
					bestMatches.push(candidate);
				} else if (score == bestScore) {
					bestMatches.push(candidate);
				}
			}
		}
		if (bestMatches.length == 1 && bestScore > 0) {
			final selected = bestMatches[0];
			return {type: selected.getReturnType(), declaration: c.declarationForSignature(selected)};
		}
		if (bestMatches.length == 1 && arityMatches.length == 1) {
			final selected = bestMatches[0];
			return {type: selected.getReturnType(), declaration: c.declarationForSignature(selected)};
		}
		if (arityMatches.length > 1) {
			final range = callRange(ctx.getFilePath(), pos);
			final lines = [diagnosticFileName(ctx.getFilePath())
				+ ":"
				+ (pos == null ? 0 : pos.getLine())
				+ ": characters "
				+ range.start
				+ "-"
				+ range.end
				+ " : Ambiguous overload, candidates follow"];
			for (candidate in arityMatches)
				lines.push(renderOverloadCandidate(ctx.getFilePath(), candidate));
			throw new TyperError(ctx.getFilePath(), pos, RAW_DIAGNOSTIC_PREFIX + lines.join("\n"));
		}
		if (arityMatches.length == 1) {
			final selected = arityMatches[0];
			return {type: selected.getReturnType(), declaration: c.declarationForSignature(selected)};
		}

		return {type: TyType.unknown(), declaration: null};
	}

	/** Best-effort exact declaration selection for ordinary call nodes. **/
	static function resolveCallDeclaration(callee:HxExpr, args:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):Null<TyDeclarationInfo> {
		switch (callee) {
			case EIdent(name):
				if (scope.resolveSymbol(name) != null)
					return null;
				final owner = ctx.currentClass();
				return owner == null ? null : resolveMethodCall(owner, name, true, args, scope, ctx, pos).declaration;
			case EField(object, field):
				switch (object) {
					case EIdent(typeOrValue):
						final staticOwner = isUpperStartName(typeOrValue) ? ctx.resolveType(typeOrValue) : null;
						if (staticOwner != null) return resolveMethodCall(staticOwner, field, true, args, scope, ctx, pos).declaration;
					case EThis:
						final owner = ctx.currentClass();
						return owner == null ? null : resolveMethodCall(owner, field, false, args, scope, ctx, pos).declaration;
					case _:
						final dotted = dottedFieldPath(object);
						if (dotted.length > 0) {
							final parts = dotted.split(".");
							final last = parts.length == 0 ? "" : parts[parts.length - 1];
							if (isUpperStartName(last)) {
								final staticOwner = ctx.resolveType(dotted);
								if (staticOwner != null)
									return resolveMethodCall(staticOwner, field, true, args, scope, ctx, pos).declaration;
							}
						}
				}

				final receiverType = inferExprType(object, scope, ctx, pos);
				final index = ctx.getIndex();
				final owner = nominalInfoForType(index, receiverType);
				return owner == null ? null : resolveMethodCall(owner, field, false, args, scope, ctx, pos).declaration;
			case _:
		}
		return null;
	}

	static function functionReferenceType(sig:TyFunSig):TyType {
		final parts = new Array<String>();
		for (arg in sig.getArgs())
			parts.push(normalizeOverloadTypeName(arg));
		if (parts.length == 0)
			parts.push("()");
		parts.push(normalizeOverloadTypeName(sig.getReturnType()));
		return TyType.functionType(sig.getArgs(), sig.getReturnType(), parts.join("->"));
	}

	/** Infer a call through a local function value without inventing a declaration identity. **/
	static function inferFunctionValueCall(callee:HxExpr, args:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):TyType {
		final calleeType = inferExprType(callee, scope, ctx, pos);
		for (argument in args)
			inferExprType(argument, scope, ctx, pos);
		if (!calleeType.isFunction())
			return TyType.unknown();
		final result = calleeType.getFunctionReturn();
		return result == null ? TyType.unknown() : result;
	}

	static function inferNullCoalesceType(left:TyType, right:TyType):TyType {
		if (right != null && !right.isUnknown())
			return right;
		if (left != null && !left.isUnknown())
			return left.isNullWrapped() ? left.unwrapNull() : left;
		return TyType.unknown();
	}

	static function currentStaticMethodReferenceType(name:String, ctx:TyperContext):Null<TyType> {
		final c = ctx.currentClass();
		if (c == null)
			return null;
		final candidates = c.staticMethodCandidates(name);
		if (candidates.length != 1)
			return null;
		return functionReferenceType(candidates[0]);
	}

	/** Resolve a bare field in the current class before treating an uppercase name as a type. **/
	static function currentFieldReferenceType(name:String, ctx:TyperContext):Null<TyType> {
		final current = ctx.currentClass();
		return current == null ? null : current.fieldType(name);
	}

	static function inferExprType(expr:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):TyType {
		return switch (expr) {
			case ENull:
				TyType.fromHintText("Null");
			case EBool(_):
				TyType.fromHintText("Bool");
			case EString(_):
				TyType.fromHintText("String");
			case EInt(_):
				TyType.fromHintText("Int");
			case EFloat(_):
				TyType.fromHintText("Float");
			case EEnumValue(_):
				// Bring-up: model enum-like tags as strings so switch dispatch can work
				// without a real enum/abstract runtime.
				TyType.fromHintText("String");
			case EThis:
				currentThisType(ctx);
			case ESuper:
				// Stage 3: `super` typing requires class hierarchy (future stage).
				TyType.unknown();
			case EIdent(name):
				final sym = scope.resolveSymbol(name);
				if (sym != null) {
					sym.getType();
				} else {
					final fieldType = currentFieldReferenceType(name, ctx);
					// Only upper-start simple identifiers can be unqualified Haxe type names in this
					// Stage3 bootstrap model. Treating every lower-case value name as a potential type
					// makes lazy loading probe parent/root packages for ordinary locals and receivers.
					final methodRef = fieldType == null && !isUpperStartName(name) ? currentStaticMethodReferenceType(name, ctx) : null;
					if (fieldType != null) {
						fieldType;
					} else if (methodRef != null) {
						methodRef;
					} else {
						final t = isUpperStartName(name) ? ctx.resolveType(name) : null;
						t != null ? TyType.nominal(t.getIdentity(), [], t.getFullName()) : TyType.unknown();
					}
				}
			case EField(obj, _field):
				// Stage 3 bring-up: type a tiny set of `Math` constants used in upstream unit tests.
				//
				// Why
				// - Upstream `unit/TestNaN.hx` uses `Math.NaN` as a `Float` value and then compares it
				//   against numeric literals in `if` conditions.
				// - Without recognizing `Math.NaN` as `Float`, our function return inference widens to
				//   `Void`, and the bootstrap emitter produces OCaml like:
				//     `let a : unit = foo () in if a > 0 then ...`
				//   which fails typechecking.
				//
				// Scope
				// - This is intentionally narrow (bring-up only). A real typer should derive these
				//   from the standard library model.
				switch ({
					obj:obj, field:_field
				}) {
					case {obj: EIdent("Math"), field: "NaN" | "POSITIVE_INFINITY" | "NEGATIVE_INFINITY" | "PI"}:
						return TyType.fromHintText("Float");
					case _:
				}

				// Static field access through a (possibly fully-qualified) type path.
				//
				// Why
				// - Upstream suites access module-local helper values via fully-qualified paths, e.g.:
				//     `unit.MyAbstract.FakeEnumAbstract.NotFound`
				// - If we don't recognize `unit.MyAbstract.FakeEnumAbstract` as a type path here, the
				//   lazy ModuleLoader never gets a chance to load the defining module, and Stage3
				//   emission can fail later with OCaml errors like:
				//     `Error: Unbound module Unit_MyAbstract_FakeEnumAbstract`.
				//
				// How
				// - When `obj` is a dotted field chain whose last segment looks like a type name
				//   (UpperStart), ask the context to resolve it as a type.
				// - This triggers ModuleLoader-based on-demand loading.
				final dotted = dottedFieldPath(obj);
				if (dotted.length > 0) {
					final parts = dotted.split(".");
					final last = parts.length == 0 ? "" : parts[parts.length - 1];
					if (isUpperStartName(last)) {
						final c = ctx.resolveType(dotted);
						if (c != null) {
							final memberType = declaredMemberReadType(c, _field, true);
							if (memberType != null)
								return memberType;
							// Bring-up default: static fields without hints are treated as dynamic.
							return TyType.fromHintText("Dynamic");
						}
					}
				}
				switch (obj) {
					case EThis:
						final c = ctx.currentClass();
						if (c != null) {
							final memberType = declaredMemberReadType(c, _field, false);
							if (memberType != null) {
								memberType;
							} else {
								if (isStrict()) {
									throw new TyperError(ctx.getFilePath(), pos, "Unknown field this." + _field);
								}
								TyType.unknown();
							}
						} else {
							TyType.unknown();
						}
					case _:
						// Best-effort: infer child for locals; actual field typing depends on the index.
						final objTy = inferExprType(obj, scope, ctx, pos);
						final idx = ctx.getIndex();
						final c = nominalInfoForType(idx, objTy);
						if (c != null) {
							final memberType = declaredMemberReadType(c, _field, false);
							if (memberType != null) {
								memberType;
							} else {
								if (isStrict()) {
									throw new TyperError(ctx.getFilePath(), pos, "Unknown field " + _field + " on " + objTy.getDisplay());
								}
								TyType.unknown();
							}
						} else {
							TyType.unknown();
						}
				}
			case ECall(callee, args):
				if (args.length == 1 && isTypeErrorProbeCallee(callee)) {
					try {
						typeErrorProbe(args[0], scope, ctx, pos);
					} catch (_:TyperError) {}
					return TyType.fromHintText("Bool");
				}
				switch (callee) {
					case EIdent("__hxhx_parenthesized") if (args.length == 1):
						return inferExprType(args[0], scope, ctx, pos);
					case _:
				}

				// Stage 3 bring-up: type a small set of `Sys.*` primitives explicitly.
				//
				// Why
				// - Gate2/Stage3 emit-runner harnesses rely on `Sys.command` for spawning sub-invocations.
				// - Without recognizing these return types, simple code like:
				//     `var code = Sys.command("haxe", ["-version"]); trace(code);`
				//   loses the `Int` type for `code` and degrades into `<unsupported>` printing.
				//
				// What
				// - This is *not* a complete stdlib typing story.
				// - It is a targeted bring-up bridge so the bootstrap emitter can produce runnable OCaml.
				switch (callee) {
					case EField(EIdent("Sys"), "command"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("Int");
					case EField(EIdent("Sys"), "getEnv"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("String");
					case EField(EIdent("Sys"), "putEnv"), EField(EIdent("Sys"), "setCwd"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("Void");
					case EField(EIdent("Sys"), "getCwd"), EField(EIdent("Sys"), "systemName"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("String");
					case EField(EIdent("Sys"), "programPath"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("String");
					case EField(EIdent("Sys"), "args"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("Array<String>");
					case EField(EIdent("Timer"), "stamp"):
						// Gate2 bring-up: RunCi uses `Timer.stamp()` for timing logs.
						// We map it to a float so `Math.round(Timer.stamp() - t)` can type.
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("Float");
					case EField(EIdent("Math"), "round"):
						// Gate2 bring-up: RunCi computes `final dt = Math.round(Timer.stamp() - t);`.
						// If this stays unknown, string interpolation of `${dt}s` degrades to `<unsupported>`.
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("Int");
					case _:
				}

				// Best-effort: type children for local inference, and use the index when we can.
				switch (callee) {
					case EIdent(name):
						// A bare call inside a class can name one of that class's static
						// methods. Keep local function values authoritative, then use the
						// same declaration lookup as the structural typed-call builder so
						// the expression result retains its nominal semantic type.
						final owner = scope.resolveSymbol(name) == null ? ctx.currentClass() : null;
						if (owner != null) {
							resolveMethodCall(owner, name, true, args, scope, ctx, pos).type;
						} else {
							inferFunctionValueCall(callee, args, scope, ctx, pos);
						}
					case EField(obj, field):
						// Static call through a type name (imported or same-package): `Util.ping()`.
						switch (obj) {
							case EIdent(typeName):
								final c = isUpperStartName(typeName) ? ctx.resolveType(typeName) : null;
								if (c != null) {
									resolveMethodCall(c, field, true, args, scope, ctx, pos).type;
								} else {
									// `obj` is a value identifier (local/param), not a type name.
									final objTy = inferExprType(obj, scope, ctx, pos);
									for (a in args)
										inferExprType(a, scope, ctx, pos);
									final idx = ctx.getIndex();
									final c2 = nominalInfoForType(idx, objTy);
									if (c2 != null) {
										resolveMethodCall(c2, field, false, args, scope, ctx, pos).type;
									} else {
										TyType.unknown();
									}
								}
							case EThis:
								final c = ctx.currentClass();
								if (c != null) {
									resolveMethodCall(c, field, false, args, scope, ctx, pos).type;
								} else {
									for (a in args)
										inferExprType(a, scope, ctx, pos);
									TyType.unknown();
								}
							case _:
								// Fully-qualified static call: `pack.sub.Type.method(...)`.
								//
								// The upstream RunCi harness uses this shape heavily without imports,
								// so we must resolve the type path and let the ModuleLoader pull it in.
								final dotted = dottedFieldPath(obj);
								if (dotted.length > 0) {
									final parts = dotted.split(".");
									final last = parts.length == 0 ? "" : parts[parts.length - 1];
									if (isUpperStartName(last)) {
										final c = ctx.resolveType(dotted);
										if (c != null) {
											return resolveMethodCall(c, field, true, args, scope, ctx, pos).type;
										}
									}
								}

								// `obj` is a value identifier (local/param), not a type name.
								final objTy = inferExprType(obj, scope, ctx, pos);
								for (a in args)
									inferExprType(a, scope, ctx, pos);
								final idx = ctx.getIndex();
								final c2 = nominalInfoForType(idx, objTy);
								if (c2 != null) {
									resolveMethodCall(c2, field, false, args, scope, ctx, pos).type;
								} else {
									TyType.unknown();
								}
						}
					case _:
						inferFunctionValueCall(callee, args, scope, ctx, pos);
				}
			case ELambda(argNames, body):
				// Stage 3 bring-up: type the body in a nested scope that:
				// - introduces lambda args (shadowing outer locals/params),
				// - but preserves visibility of outer locals/params for capture.
				//
				final lambdaArgs = new Array<TySymbol>();
				for (n in argNames)
					lambdaArgs.push(new TySymbol(n, TyType.fromHintText("Dynamic")));
				final combinedParams = lambdaArgs.concat(scope.getParams().copy());
				final combinedLocals = scope.getLocals().copy();
				final nested = new TyFunctionEnv("<lambda>", combinedParams, combinedLocals, TyType.unknown(), TyType.unknown());
				final result = inferExprType(body, nested, ctx, pos);
				TyType.functionType([for (_ in argNames) TyType.fromHintText("Dynamic")], result);
			case EMacroExpr(inner, _wrappers):
				inferExprType(inner, scope, ctx, pos);
				TyType.fromHintText("haxe.macro.Expr");
			case EMacroType(_typeText):
				TyType.fromHintText("haxe.macro.ComplexType");
			case ETryCatchRaw(_raw):
				// Stage 3 bring-up: we only preserve the shape of `try/catch` in the expression tree.
				// Correct semantics are Stage 4+ work, so we type it as `Dynamic` here.
				TyType.fromHintText("Dynamic");
			case ESwitchRaw(_raw):
				// Stage 3 bring-up: we only preserve the shape of `switch` expressions so parsing/typing
				// can proceed deterministically through upstream-shaped code (notably runci).
				// Correct semantics (pattern matching + guards + value typing) are Stage 4+ work.
				TyType.fromHintText("Dynamic");
			case ESwitch(scrutinee, patterns, exprs):
				// Bring-up: type the scrutinee and unify case-expression types best-effort.
				// This is intentionally permissive; if unification fails we widen to Dynamic.
				final scrutTy = inferExprType(scrutinee, scope, ctx, pos);
				var out:TyType = TyType.unknown();
				if (patterns != null && exprs != null) {
					final count = patterns.length < exprs.length ? patterns.length : exprs.length;
					for (i in 0...count) {
						final pattern = patterns[i];
						final branchExpr = exprs[i];
						var branchTy:TyType = TyType.unknown();
						// Bring-up: we do not model nested scopes yet; declare pattern binders as
						// best-effort locals so case bodies can type their references.
						declarePatternBindings(scope, pattern, scrutTy);
						branchTy = inferExprType(branchExpr, scope, ctx, pos);

						if (out.isUnknown())
							out = branchTy;
						else {
							final u = TyType.unify(out, branchTy);
							if (u != null)
								out = u;
							else if (!isStrict())
								out = TyType.fromHintText("Dynamic");
						}
					}
				}
				out.isUnknown() ? TyType.fromHintText("Dynamic") : out;
			case ENew(_typePath, args):
				for (a in args)
					inferExprType(a, scope, ctx, pos);
				final c = ctx.resolveType(_typePath);
				c != null ? TyType.nominal(c.getIdentity(), [], c.getFullName()) : TyType.fromHintText(_typePath);
			case EUnop(_op, _fixity, e):
				final inner = inferExprType(e, scope, ctx, pos);
				final semanticIndex = ctx.getIndex();
				final isPropertyUpdate = (_op == Increment || _op == Decrement)
					&& semanticIndex != null
					&& inner.getNominalIdentity() != null
					&& semanticIndex.getAbstractByFullName(inner.getNominalIdentity().getCanonicalName()) != null
					&& accessorPropertyForAccess(e, scope, ctx, pos) != null;
				// Haxe 4.3.7 updates explicit properties through their getter/setter
				// contract; it does not select the abstract value's increment helper.
				final bound = isPropertyUpdate ? null : TyAbstractUnaryBinding.select(semanticIndex, inner, _op, _fixity, ctx.getFilePath(), pos);
				if (bound != null) {
					bound.getResultType();
				} else {
					switch (_op) {
						case LogicalNot: TyType.fromHintText("Bool");
						case Negate: inner.isNumeric() ? inner : TyType.unknown();
						case Increment | Decrement | BitwiseNot: inner;
					}
				}
			case EBinop(op, a, b):
				switch (op) {
					case "??":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						inferNullCoalesceType(ta, tb);
					case "=":
						// Assignment as expression.
						final rhs = inferExprType(b, scope, ctx, pos);
						switch (a) {
							case EIdent(name):
								final sym = scope.resolveSymbol(name);
								if (sym != null) {
									final u = TyType.unify(sym.getType(), rhs);
									if (u == null) {
										// Bootstrap: don't fail hard on complex types (generics, abstracts, etc.).
										// Keep typing moving by widening to Dynamic.
										sym.setType(TyType.fromHintText("Dynamic"));
										rhs;
									} else {
										sym.setType(u);
										rhs;
									}
								} else {
									rhs;
								}
							case _:
								// Field assignment typing needs class env (future stage).
								inferExprType(a, scope, ctx, pos);
								rhs;
						}
					case _ if (HxBinaryOperatorTools.isCompoundAssignment(op)):
						final leftType = inferExprType(a, scope, ctx, pos);
						final rightType = inferExprType(b, scope, ctx, pos);
						final bound = TyAbstractBinaryBinding.select(ctx.getIndex(), leftType, rightType, op, ctx.getFilePath(), pos);
						if (bound != null) {
							bound.getRequiresWriteback() ? leftType : bound.getOperatorInfo().getResultType();
						} else {
							switch (a) {
								case EIdent(name):
									final symbol = scope.resolveSymbol(name);
									if (symbol != null) {
										final unified = TyType.unify(symbol.getType(), rightType);
										if (unified != null)
											symbol.setType(unified);
									}
								case _:
							}
							leftType;
						}
					case "==" | "!=" | "<" | "<=" | ">" | ">=":
						final leftType = inferExprType(a, scope, ctx, pos);
						final rightType = inferExprType(b, scope, ctx, pos);
						final bound = TyAbstractBinaryBinding.select(ctx.getIndex(), leftType, rightType, op, ctx.getFilePath(), pos);
						bound == null ? TyType.fromHintText("Bool") : bound.getOperatorInfo().getResultType();
					case "&&" | "||":
						inferExprType(a, scope, ctx, pos);
						inferExprType(b, scope, ctx, pos);
						TyType.fromHintText("Bool");
					case "&" | "|" | "^" | "<<" | ">>" | ">>>":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						final bound = TyAbstractBinaryBinding.select(ctx.getIndex(), ta, tb, op, ctx.getFilePath(), pos);
						if (bound != null) bound.getOperatorInfo()
							.getResultType(); else // Best-effort: treat as Bool if both operands are Bool; otherwise Int.
							(ta.getDisplay() == "Bool" && tb.getDisplay() == "Bool") ? TyType.fromHintText("Bool") : TyType.fromHintText("Int");
					case "+":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						final bound = TyAbstractBinaryBinding.select(ctx.getIndex(), ta, tb, op, ctx.getFilePath(), pos);
						if (bound != null) {
							bound.getOperatorInfo().getResultType();
						} else if (ta.getDisplay() == "String" || tb.getDisplay() == "String") {
							TyType.fromHintText("String");
						} else {
							final u = TyType.unify(ta, tb);
							u != null
							&& u.isNumeric() ? u : TyType.unknown();
						}
					case "-" | "*" | "/" | "%":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						final bound = TyAbstractBinaryBinding.select(ctx.getIndex(), ta, tb, op, ctx.getFilePath(), pos);
						if (bound != null) bound.getOperatorInfo().getResultType(); else {
							final unified = TyType.unify(ta, tb);
							unified != null
							&& unified.isNumeric() ? unified : TyType.unknown();
						}
					case _:
						inferExprType(a, scope, ctx, pos);
						inferExprType(b, scope, ctx, pos);
						TyType.unknown();
				}
			case ETernary(cond, thenExpr, elseExpr):
				inferExprType(cond, scope, ctx, pos);
				final t1 = inferExprType(thenExpr, scope, ctx, pos);
				final t2 = inferExprType(elseExpr, scope, ctx, pos);
				final u = TyType.unify(t1, t2);
				u == null ? TyType.fromHintText("Dynamic") : u;
			case EAnon(_names, values):
				for (v in values)
					inferExprType(v, scope, ctx, pos);
				TyType.fromHintText("Dynamic");
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				// Bring-up: type the iterable and bind the loop variable for the yield expression.
				final itTy = inferExprType(iterable, scope, ctx, pos);
				final elemTy = arrayElementType(itTy);
				scope.declareLocal(name, (elemTy != null && !elemTy.isUnknown()) ? elemTy : TyType.fromHintText("Dynamic"));
				if (guardExpr != null)
					inferExprType(guardExpr, scope, ctx, pos);
				inferExprType(yieldExpr, scope, ctx, pos);
				TyType.fromHintText("Array<Dynamic>");
			case EArrayDecl(values):
				var elem:TyType = TyType.unknown();
				var saw = false;
				for (v in values) {
					final vt = inferExprType(v, scope, ctx, pos);
					if (!saw) {
						saw = true;
						elem = vt;
						continue;
					}
					final u = TyType.unify(elem, vt);
					if (u == null) {
						elem = TyType.fromHintText("Dynamic");
						break;
					}
					elem = u;
				}
				if (!saw)
					elem = TyType.fromHintText("Dynamic");
				// Resolve inferred element identities as eagerly as written local
				// hints. Keeping `Array<Ticket>`'s argument as a display-only name
				// would erase the abstract identity at `values[index]` and make an
				// otherwise exact operator look like an ordinary carrier update.
				resolveTypeInContext(TyType.fromHintText("Array<" + elem.getDisplay() + ">"), ctx);
			case EArrayAccess(array, index):
				final arrayType = inferExprType(array, scope, ctx, pos);
				inferExprType(index, scope, ctx, pos);
				final elementType = arrayElementType(arrayType);
				// Other indexed containers remain explicit Dynamic until their access
				// contracts are represented in the shared semantic model.
				elementType == null ? TyType.fromHintText("Dynamic") : elementType;
			case ERange(start, end):
				inferExprType(start, scope, ctx, pos);
				inferExprType(end, scope, ctx, pos);
				// Bring-up: `start...end` is primarily used as a loop iterable; model it as Dynamic.
				TyType.fromHintText("Dynamic");
			case ECast(expr, typeHint):
				final inner = inferExprType(expr, scope, ctx, pos);
				final hinted = typeFromHintInContext(typeHint, ctx);
				hinted.isUnknown() ? inner : hinted;
			case EUntyped(expr):
				inferExprType(expr, scope, ctx, pos);
				TyType.fromHintText("Dynamic");
			case EUnsupported(_):
				TyType.unknown();
		}
	}
}
