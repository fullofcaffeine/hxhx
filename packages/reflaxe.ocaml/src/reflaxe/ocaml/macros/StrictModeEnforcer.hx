package reflaxe.ocaml.macros;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.OcamlAtomicSemantics;
import reflaxe.ocaml.OcamlBuildContext;
import reflaxe.ocaml.OcamlProfileContract;
import reflaxe.ocaml.OcamlPortableNativeSurfacePolicy;
import reflaxe.ocaml.macros.StrictModeSourceAnnotation.hasExplicitDynamicLocal;

private typedef StrictModeSnapshot = {
	final mode:String;
	final enabled:Bool;
	final result:String;
	final strictScope:String;
	final violationCount:Int;
	final violations:Array<String>;
	final portableNativeSurfacePolicy:String;
}

typedef StrictModePerformanceSnapshot = {
	final expressionVisits:Int;
	final strictChecks:Int;
	final portableNativeSurfaceChecks:Int;
	final atomicSemanticsChecks:Int;
}

/**
	Applies request-wide OCaml source-boundary checks during a stage0 build.

	This class does not choose faster representations or enable native lowering. Portable code
	receives direct typed OCaml output whenever the target can prove that Haxe behavior is preserved.
	These checks instead control whether one complete build may use compatibility-heavy constructs:
	raw `__ocaml__` injection, `Reflect.*` or `Type.*` calls, and explicit `Dynamic` annotations.

	The metal profile enables the checks globally and fails on violations by default. Portable builds
	may request the same global checks with `-D ocaml_strict`. The separate
	`ocaml_portable_native_surface` policy reports or rejects explicit use of typed `ocaml.*` APIs.
	`-D ocaml_metal_allow_fallback` changes strict violations into warnings for an explicitly requested
	diagnostic build; it does not create source-local strictness or authorize a second lowering path.
**/
class StrictModeEnforcer {
	static inline final PERFORMANCE_PROGRESS_INTERVAL = 10000;
	static inline final NATIVE_SURFACE_OCAML = 1;
	static inline final NATIVE_SURFACE_HAXE_ATOMIC = 2;

	static var initialized = false;
	static var fallbackAllowed = false;
	static var configuredProjectRoot:Null<String> = null;
	static var configuredBuildContext:Null<OcamlBuildContext> = null;
	static var lastSnapshot:StrictModeSnapshot = {
		mode: "reflaxe_stage0_macro",
		enabled: false,
		result: "not_enabled",
		strictScope: "disabled",
		violationCount: 0,
		violations: [],
		portableNativeSurfacePolicy: OcamlPortableNativeSurfacePolicy.toDefineValue(OcamlPortableNativeSurfacePolicy.Warn)
	};
	static var lastPerformanceSnapshot:StrictModePerformanceSnapshot = {
		expressionVisits: 0,
		strictChecks: 0,
		portableNativeSurfaceChecks: 0,
		atomicSemanticsChecks: 0
	};
	static var performanceLogLine:Null<String->Void> = null;
	static var performanceExpressionVisits = 0;
	static var performanceStrictChecks = 0;
	static var performancePortableNativeSurfaceChecks = 0;
	static var performanceAtomicSemanticsChecks = 0;

	public static function init(buildContext:OcamlBuildContext):Void {
		if (initialized)
			return;
		initialized = true;

		if (!isOcamlBuild())
			return;

		fallbackAllowed = buildContext.metalFallbackAllowed;
		configuredProjectRoot = normalizePath(Sys.getCwd());
		configuredBuildContext = buildContext;
	}

	/**
		Run strict-boundary enforcement from the target compiler's existing typed-module pass.

		Why:
		- `Context.onAfterTyping` callbacks receive the full typed module graph through Haxe's macro
		  bridge. On compiler-sized stage0 bootstrap runs, each additional callback can force another
		  large typed-graph encoding pass.
		- `OcamlCompiler.filterTypes(...)` already receives the graph from Reflaxe's required callback,
		  so strict-mode policy should consume that payload instead of registering a second callback.
	**/
	public static function enforceRegisteredTypes(types:Array<ModuleType>, logLine:Null<String->Void> = null):Void {
		if (configuredProjectRoot == null || configuredBuildContext == null)
			return;
		performanceLogLine = logLine;
		enforce(types, configuredProjectRoot, configuredBuildContext);
		performanceLogLine = null;
	}

	public static function snapshot():StrictModeSnapshot {
		return {
			mode: lastSnapshot.mode,
			enabled: lastSnapshot.enabled,
			result: lastSnapshot.result,
			strictScope: lastSnapshot.strictScope,
			violationCount: lastSnapshot.violationCount,
			violations: lastSnapshot.violations.copy(),
			portableNativeSurfacePolicy: lastSnapshot.portableNativeSurfacePolicy
		};
	}

	/** Returns profiling counters from the most recent strict-boundary scan. */
	public static function performanceSnapshot():StrictModePerformanceSnapshot {
		return {
			expressionVisits: lastPerformanceSnapshot.expressionVisits,
			strictChecks: lastPerformanceSnapshot.strictChecks,
			portableNativeSurfaceChecks: lastPerformanceSnapshot.portableNativeSurfaceChecks,
			atomicSemanticsChecks: lastPerformanceSnapshot.atomicSemanticsChecks
		};
	}

	static function enforce(types:Array<ModuleType>, projectRoot:String, buildContext:OcamlBuildContext):Void {
		final strictGlobal = buildContext.profile == OcamlProfileContract.Metal || buildContext.strictUserBoundaries;
		final strictEnabled = strictGlobal;
		final portablePolicyEnabled = buildContext.profile == OcamlProfileContract.Portable
			&& buildContext.portableNativeSurfacePolicy != OcamlPortableNativeSurfacePolicy.Allow;
		final atomicEmulationDiagnosticsEnabled = buildContext.profile == OcamlProfileContract.Portable
			&& buildContext.atomicSemantics == OcamlAtomicSemantics.Emulated;
		final strictScope = if (buildContext.profile == OcamlProfileContract.Metal) "global_metal" else if (buildContext.strictUserBoundaries)
			"global_strict" else "disabled";
		performanceExpressionVisits = 0;
		performanceStrictChecks = 0;
		performancePortableNativeSurfaceChecks = 0;
		performanceAtomicSemanticsChecks = 0;

		final reported:Map<String, Bool> = [];
		final violationIds:Map<String, Bool> = [];
		for (moduleType in types) {
			switch (moduleType) {
				case TClassDecl(classRef):
					final classType = classRef.get();
					if (!isStrictProjectSource(classType.pos, projectRoot))
						continue;
					final strictForModule = strictGlobal;
					if (!strictForModule && !portablePolicyEnabled && !atomicEmulationDiagnosticsEnabled)
						continue;
					final strictHardError = strictForModule && !fallbackAllowed;
					final fields = classType.fields.get().concat(classType.statics.get());
					for (field in fields) {
						final expr = field.expr();
						if (expr == null)
							continue;
						scanExpr(expr, strictForModule, strictHardError, buildContext.portableNativeSurfacePolicy, atomicEmulationDiagnosticsEnabled,
							reported, violationIds);
					}
				case _:
			}
		}
		final violationList = mapKeysSorted(violationIds);
		lastSnapshot = {
			mode: "reflaxe_stage0_macro",
			enabled: strictEnabled || portablePolicyEnabled,
			result: violationList.length == 0 ? "pass" : "violations_reported",
			strictScope: strictScope,
			violationCount: violationList.length,
			violations: violationList,
			portableNativeSurfacePolicy: OcamlPortableNativeSurfacePolicy.toDefineValue(buildContext.portableNativeSurfacePolicy)
		};
		lastPerformanceSnapshot = {
			expressionVisits: performanceExpressionVisits,
			strictChecks: performanceStrictChecks,
			portableNativeSurfaceChecks: performancePortableNativeSurfaceChecks,
			atomicSemanticsChecks: performanceAtomicSemanticsChecks
		};
	}

	static function scanExpr(expr:TypedExpr, strictForModule:Bool, strictHardError:Bool, portableNativeSurfacePolicy:OcamlPortableNativeSurfacePolicy,
			atomicEmulationDiagnosticsEnabled:Bool, reported:Map<String, Bool>, violationIds:Map<String, Bool>):Void {
		if (performanceLogLine != null) {
			performanceExpressionVisits++;
			if (strictForModule)
				performanceStrictChecks++;
			if (portableNativeSurfacePolicy != OcamlPortableNativeSurfacePolicy.Allow)
				performancePortableNativeSurfaceChecks++;
			if (atomicEmulationDiagnosticsEnabled)
				performanceAtomicSemanticsChecks++;
			if (performanceExpressionVisits % PERFORMANCE_PROGRESS_INTERVAL == 0) {
				performanceLogLine("reflaxe.ocaml: strict_mode_progress visits=" + Std.string(performanceExpressionVisits) + " strict_checks="
					+ Std.string(performanceStrictChecks) + " portable_native_surface_checks=" + Std.string(performancePortableNativeSurfaceChecks)
					+ " atomic_semantics_checks=" + Std.string(performanceAtomicSemanticsChecks));
			}
		}
		if (strictForModule)
			scanExprStrict(expr, strictHardError, reported, violationIds);
		var requestedNativeSurfaces = 0;
		if (portableNativeSurfacePolicy != OcamlPortableNativeSurfacePolicy.Allow)
			requestedNativeSurfaces |= NATIVE_SURFACE_OCAML;
		if (atomicEmulationDiagnosticsEnabled)
			requestedNativeSurfaces |= NATIVE_SURFACE_HAXE_ATOMIC;
		final nativeSurfaces = requestedNativeSurfaces == 0 ? 0 : expressionNativeSurfaceMask(expr, requestedNativeSurfaces);
		if ((nativeSurfaces & NATIVE_SURFACE_OCAML) != 0)
			scanExprPortableNativeSurface(expr, portableNativeSurfacePolicy, reported, violationIds);
		if ((nativeSurfaces & NATIVE_SURFACE_HAXE_ATOMIC) != 0)
			scanExprAtomicSemantics(expr, reported, violationIds);
		TypedExprTools.iter(expr,
			e -> scanExpr(e, strictForModule, strictHardError, portableNativeSurfacePolicy, atomicEmulationDiagnosticsEnabled, reported, violationIds));
	}

	static function scanExprStrict(expr:TypedExpr, strictHardError:Bool, reported:Map<String, Bool>, violationIds:Map<String, Bool>):Void {
		switch (expr.expr) {
			case TCall(callTarget, _):
				if (isOcamlInjectionCall(callTarget)) {
					emitStrictViolation("raw_ocaml_injection", "ocaml metal strict mode forbids `__ocaml__` injection in application code.", expr.pos,
						strictHardError, reported, violationIds);
				}
				final reflectionCall = reflectionCallLabel(callTarget);
				if (reflectionCall != null) {
					emitStrictViolation("reflection_call_"
						+ reflectionCall,
						"ocaml metal strict mode forbids reflection call `"
						+ reflectionCall
						+ "` in application code.", expr.pos, strictHardError, reported,
						violationIds);
				}
			case TVar(variable, _):
				if (isDynamicType(variable.t) && hasExplicitDynamicLocal(variable.name, expr.pos)) {
					emitStrictViolation("dynamic_var", "ocaml metal strict mode forbids explicit `Dynamic` variable annotations in application code.",
						expr.pos, strictHardError, reported, violationIds);
				}
			case TFunction(fn):
				for (arg in fn.args) {
					if (isDynamicType(arg.v.t)) {
						emitStrictViolation("dynamic_arg", "ocaml metal strict mode forbids explicit `Dynamic` argument annotations in application code.",
							expr.pos, strictHardError, reported, violationIds);
					}
				}
			case TTry(_, catches):
				for (catchEntry in catches) {
					if (isDynamicType(catchEntry.v.t)) {
						emitStrictViolation("dynamic_catch", "ocaml metal strict mode forbids `Dynamic` catch bindings in application code.",
							catchEntry.expr.pos, strictHardError, reported, violationIds);
					}
				}
			case _:
		}
	}

	static function scanExprPortableNativeSurface(expr:TypedExpr, policy:OcamlPortableNativeSurfacePolicy, reported:Map<String, Bool>,
			violationIds:Map<String, Bool>):Void {
		final policyLabel = OcamlPortableNativeSurfacePolicy.toDefineValue(policy);
		final msg = "portable profile detected `ocaml.*` usage (non-portable target-native surface); policy="
			+ policyLabel
			+ " (`-D ocaml_portable_native_surface=warn|allow|error`).";
		emitPortableNativeSurfaceViolation("portable_native_surface", msg, expr.pos, policy, reported, violationIds);
	}

	static function scanExprAtomicSemantics(expr:TypedExpr, reported:Map<String, Bool>, violationIds:Map<String, Bool>):Void {
		emitAtomicSemanticsDiagnostic("portable_atomic_emulated",
			"portable profile uses emulated `haxe.atomic.*` semantics (single-thread API parity only; not hardware/thread-level atomicity).", expr.pos,
			reported, violationIds);
	}

	/**
		Finds the requested target-native type families for one expression.

		The returned bit mask lets portable-surface and atomic policy share one recursive type walk.
		Additional expression-owned types are checked only for families that the expression result type
		did not already prove.
	**/
	static function expressionNativeSurfaceMask(expr:TypedExpr, requestedMask:Int):Int {
		var found = typeNativeSurfaceMask(expr.t, 16, requestedMask);
		var remaining = requestedMask & ~found;
		if (remaining == 0)
			return found;
		found |= switch (expr.expr) {
			case TTypeExpr(moduleType):
				moduleTypeNativeSurfaceMask(moduleType) & remaining;
			case TVar(variable, _):
				typeNativeSurfaceMask(variable.t, 16, remaining);
			case TFunction(fn):
				var argumentSurfaces = 0;
				for (arg in fn.args) {
					argumentSurfaces |= typeNativeSurfaceMask(arg.v.t, 16, remaining & ~argumentSurfaces);
					if (argumentSurfaces == remaining)
						break;
				}
				argumentSurfaces;
			case _:
				0;
		}
		return found;
	}

	static function moduleTypeNativeSurfaceMask(moduleType:ModuleType):Int {
		return switch (moduleType) {
			case TClassDecl(classRef): packageNativeSurfaceMask(classRef.get().pack);
			case TEnumDecl(enumRef): packageNativeSurfaceMask(enumRef.get().pack);
			case TTypeDecl(typeRef): packageNativeSurfaceMask(typeRef.get().pack);
			case TAbstract(abstractRef): packageNativeSurfaceMask(abstractRef.get().pack);
		}
	}

	static function packageNativeSurfaceMask(pack:Array<String>):Int {
		var found = 0;
		if (pack.length > 0 && pack[0] == "ocaml")
			found |= NATIVE_SURFACE_OCAML;
		if (pack.length > 1 && pack[0] == "haxe" && pack[1] == "atomic")
			found |= NATIVE_SURFACE_HAXE_ATOMIC;
		return found;
	}

	/**
		Finds requested target-native families in a Haxe macro type without changing or resolving it.

		The depth limit preserves the previous fail-safe boundary for recursive aliases. Once every
		requested family is found, later branches are skipped because they cannot change policy output.
	**/
	static function typeNativeSurfaceMask(type:Type, maxDepth:Int, requestedMask:Int):Int {
		if (maxDepth <= 0 || requestedMask == 0)
			return 0;
		return switch (type) {
			case TInst(classRef, params):
				final own = packageNativeSurfaceMask(classRef.get().pack) & requestedMask;
				own | typeParamsNativeSurfaceMask(params, maxDepth - 1, requestedMask & ~own);
			case TEnum(enumRef, params):
				final own = packageNativeSurfaceMask(enumRef.get().pack) & requestedMask;
				own | typeParamsNativeSurfaceMask(params, maxDepth - 1, requestedMask & ~own);
			case TType(typeRef, params):
				final typeDef = typeRef.get();
				var found = packageNativeSurfaceMask(typeDef.pack) & requestedMask;
				found |= typeParamsNativeSurfaceMask(params, maxDepth - 1, requestedMask & ~found);
				found | typeNativeSurfaceMask(typeDef.type, maxDepth - 1, requestedMask & ~found);
			case TAbstract(abstractRef, params):
				final abstractDef = abstractRef.get();
				var found = packageNativeSurfaceMask(abstractDef.pack) & requestedMask;
				found |= typeParamsNativeSurfaceMask(params, maxDepth - 1, requestedMask & ~found);
				found | typeNativeSurfaceMask(abstractDef.type, maxDepth - 1, requestedMask & ~found);
			case TFun(args, ret):
				var found = 0;
				for (arg in args) {
					found |= typeNativeSurfaceMask(arg.t, maxDepth - 1, requestedMask & ~found);
					if (found == requestedMask)
						break;
				}
				found | typeNativeSurfaceMask(ret, maxDepth - 1, requestedMask & ~found);
			case TAnonymous(anonRef):
				var found = 0;
				for (field in anonRef.get().fields) {
					found |= typeNativeSurfaceMask(field.type, maxDepth - 1, requestedMask & ~found);
					if (found == requestedMask)
						break;
				}
				found;
			case TDynamic(inner): inner == null ? 0 : typeNativeSurfaceMask(inner, maxDepth - 1, requestedMask);
			case TLazy(thunk):
				typeNativeSurfaceMask(thunk(), maxDepth - 1, requestedMask);
			case TMono(ref):
				final resolved = ref.get();
				resolved == null ? 0 : typeNativeSurfaceMask(resolved, maxDepth - 1, requestedMask);
		}
	}

	static function typeParamsNativeSurfaceMask(params:Array<Type>, maxDepth:Int, requestedMask:Int):Int {
		var found = 0;
		for (param in params) {
			found |= typeNativeSurfaceMask(param, maxDepth, requestedMask & ~found);
			if (found == requestedMask)
				break;
		}
		return found;
	}

	static function isOcamlInjectionCall(callTarget:TypedExpr):Bool {
		return switch (callTarget.expr) {
			case TIdent(name):
				name == "__ocaml__";
			case TLocal(variable):
				variable.name == "__ocaml__";
			case TField(_, fieldAccess):
				switch (fieldAccess) {
					case FInstance(_, _, classField) | FStatic(_, classField) | FAnon(classField) | FClosure(_, classField):
						classField.get().name == "__ocaml__";
					case FEnum(_, enumField):
						enumField.name == "__ocaml__";
					case FDynamic(name):
						name == "__ocaml__";
				}
			case _:
				false;
		}
	}

	static function reflectionCallLabel(callTarget:TypedExpr):Null<String> {
		return switch (callTarget.expr) {
			case TField(_, fieldAccess):
				switch (fieldAccess) {
					case FStatic(classRef, classField):
						final classType = classRef.get();
						if (classType.pack.length == 0 && (classType.name == "Reflect" || classType.name == "Type")) {
							classType.name + "." + classField.get().name;
						} else {
							null;
						}
					case _:
						null;
				}
			case _:
				null;
		}
	}

	static function isDynamicType(type:Type):Bool {
		return switch (type) {
			case TDynamic(_):
				true;
			case _:
				false;
		}
	}

	static function emitStrictViolation(id:String, message:String, pos:haxe.macro.Expr.Position, strictHardError:Bool, reported:Map<String, Bool>,
			violationIds:Map<String, Bool>):Void {
		final posInfo = Context.getPosInfos(pos);
		final key = id + ":" + posInfo.file + ":" + Std.string(posInfo.min) + ":" + Std.string(posInfo.max);
		if (reported.exists(key))
			return;
		reported.set(key, true);
		violationIds.set(id, true);

		final fallbackSuffix = " Allowed because -D ocaml_metal_allow_fallback is set.";
		if (strictHardError) {
			Context.error(message, pos);
		} else {
			Context.warning(message + fallbackSuffix, pos);
		}
	}

	static function emitPortableNativeSurfaceViolation(id:String, message:String, pos:haxe.macro.Expr.Position, policy:OcamlPortableNativeSurfacePolicy,
			reported:Map<String, Bool>, violationIds:Map<String, Bool>):Void {
		final posInfo = Context.getPosInfos(pos);
		final key = id + ":" + posInfo.file + ":" + Std.string(posInfo.min) + ":" + Std.string(posInfo.max);
		if (reported.exists(key))
			return;
		reported.set(key, true);
		violationIds.set(id, true);

		switch (policy) {
			case Error:
				Context.error(message, pos);
			case Warn:
				Context.warning(message, pos);
			case Allow:
		}
	}

	static function emitAtomicSemanticsDiagnostic(id:String, message:String, pos:haxe.macro.Expr.Position, reported:Map<String, Bool>,
			violationIds:Map<String, Bool>):Void {
		final posInfo = Context.getPosInfos(pos);
		final key = id + ":" + posInfo.file;
		if (reported.exists(key))
			return;
		reported.set(key, true);
		violationIds.set(id, true);
		Context.warning(message + " Configure via -D ocaml_atomic_semantics=emulated.", pos);
	}

	static function isStrictProjectSource(pos:haxe.macro.Expr.Position, projectRoot:String):Bool {
		final root = ensureTrailingSlash(projectRoot);
		var file = normalizePath(Context.getPosInfos(pos).file);
		if (file == null || file.length == 0)
			return false;
		if (!Path.isAbsolute(file)) {
			file = normalizePath(Path.join([root, file]));
		}
		if (!StringTools.startsWith(file, root))
			return false;
		if (file.indexOf("/packages/reflaxe.ocaml/src/") != -1 || file.indexOf("/packages/reflaxe.ocaml/std/") != -1)
			return false;
		if (file.indexOf("/src/reflaxe/") != -1 || file.indexOf("/std/") != -1)
			return false;
		return true;
	}

	static function ensureTrailingSlash(path:String):String {
		final normalized = normalizePath(path);
		return StringTools.endsWith(normalized, "/") ? normalized : normalized + "/";
	}

	static function mapKeysSorted(values:Map<String, Bool>):Array<String> {
		final out = new Array<String>();
		for (value in values.keys())
			out.push(value);
		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	static function normalizePath(path:String):String {
		return Path.normalize(path).split("\\").join("/");
	}

	static function isOcamlBuild():Bool {
		final targetName = Context.definedValue("target.name");
		return targetName == "ocaml" || Context.defined("ocaml_output");
	}
}
#end
