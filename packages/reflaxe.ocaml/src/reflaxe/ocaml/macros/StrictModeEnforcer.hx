package reflaxe.ocaml.macros;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.OcamlBuildContext;
import reflaxe.ocaml.OcamlProfileContract;
import reflaxe.ocaml.OcamlPortableNativeSurfacePolicy;
import reflaxe.ocaml.analyze.MetalLaneAnalyzer;

private typedef StrictModeSnapshot = {
	final mode:String;
	final enabled:Bool;
	final result:String;
	final strictScope:String;
	final violationCount:Int;
	final violations:Array<String>;
	final laneModules:Array<String>;
	final portableNativeSurfacePolicy:String;
}

/**
	Stage0 metal strict-boundary enforcement for `reflaxe.ocaml`.

	Why:
	- Metal mode must be explicit about raw target injection and reflection-heavy boundaries.
	- Stage0 should enforce the same direction as Stage3 metal policy.

	What:
	- Rejects raw `__ocaml__` injection in application sources.
	- Rejects `Reflect.*` / `Type.*` reflection calls in application sources.
	- Rejects explicit `Dynamic` annotations (var/catch/function args) in application sources.

	Policy:
	- In strict metal mode (default): violations are hard errors.
	- With `-D ocaml_metal_allow_fallback`: violations become warnings (report-only lane).
**/
class StrictModeEnforcer {
	static var initialized = false;
	static var fallbackAllowed = false;
	static var lastSnapshot:StrictModeSnapshot = {
		mode: "reflaxe_stage0_macro",
		enabled: false,
		result: "not_enabled",
		strictScope: "disabled",
		violationCount: 0,
		violations: [],
		laneModules: [],
		portableNativeSurfacePolicy: OcamlPortableNativeSurfacePolicy.toDefineValue(OcamlPortableNativeSurfacePolicy.Warn)
	};

	public static function init(buildContext:OcamlBuildContext):Void {
		if (initialized)
			return;
		initialized = true;

		if (!isOcamlBuild())
			return;

		fallbackAllowed = buildContext.metalFallbackAllowed;
		final projectRoot = normalizePath(Sys.getCwd());
		Context.onAfterTyping(types -> enforce(types, projectRoot, buildContext));
	}

	public static function snapshot():StrictModeSnapshot {
		return {
			mode: lastSnapshot.mode,
			enabled: lastSnapshot.enabled,
			result: lastSnapshot.result,
			strictScope: lastSnapshot.strictScope,
			violationCount: lastSnapshot.violationCount,
			violations: lastSnapshot.violations.copy(),
			laneModules: lastSnapshot.laneModules.copy(),
			portableNativeSurfacePolicy: lastSnapshot.portableNativeSurfacePolicy
		};
	}

	static function enforce(types:Array<ModuleType>, projectRoot:String, buildContext:OcamlBuildContext):Void {
		final laneModuleSet = MetalLaneAnalyzer.collectModuleSet(types);
		final laneModules = mapKeysSorted(laneModuleSet);
		final strictGlobal = buildContext.profile == OcamlProfileContract.Metal || buildContext.strictUserBoundaries;
		final strictEnabled = strictGlobal || laneModules.length > 0;
		final portablePolicyEnabled = buildContext.profile == OcamlProfileContract.Portable
			&& buildContext.portableNativeSurfacePolicy != OcamlPortableNativeSurfacePolicy.Allow;
		final strictScope = if (strictGlobal) "global_metal" else if (laneModules.length > 0) "portable_haxeMetal_lanes" else "disabled";

		final reported:Map<String, Bool> = [];
		final violationIds:Map<String, Bool> = [];
		for (moduleType in types) {
			switch (moduleType) {
				case TClassDecl(classRef):
					final classType = classRef.get();
					if (!isStrictProjectSource(classType.pos, projectRoot))
						continue;
					final moduleName = normalizeModuleLabel(classType.module);
					final strictForModule = strictGlobal || laneModuleSet.exists(moduleName);
					if (!strictForModule && !portablePolicyEnabled)
						continue;
					final strictHardError = strictForModule && !fallbackAllowed;
					final fields = classType.fields.get().concat(classType.statics.get());
					for (field in fields) {
						final expr = field.expr();
						if (expr == null)
							continue;
						scanExpr(expr, strictForModule, strictHardError, buildContext.portableNativeSurfacePolicy, reported, violationIds);
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
			laneModules: laneModules,
			portableNativeSurfacePolicy: OcamlPortableNativeSurfacePolicy.toDefineValue(buildContext.portableNativeSurfacePolicy)
		};
	}

	static function scanExpr(expr:TypedExpr, strictForModule:Bool, strictHardError:Bool, portableNativeSurfacePolicy:OcamlPortableNativeSurfacePolicy,
			reported:Map<String, Bool>, violationIds:Map<String, Bool>):Void {
		if (strictForModule)
			scanExprStrict(expr, strictHardError, reported, violationIds);
		if (portableNativeSurfacePolicy != OcamlPortableNativeSurfacePolicy.Allow)
			scanExprPortableNativeSurface(expr, portableNativeSurfacePolicy, reported, violationIds);
		TypedExprTools.iter(expr, e -> scanExpr(e, strictForModule, strictHardError, portableNativeSurfacePolicy, reported, violationIds));
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
				if (isDynamicType(variable.t)) {
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
		if (!containsOcamlNativeSurface(expr))
			return;
		final policyLabel = OcamlPortableNativeSurfacePolicy.toDefineValue(policy);
		final msg = "portable profile detected `ocaml.*` usage (non-portable target-native surface); policy="
			+ policyLabel
			+ " (`-D ocaml_portable_native_surface=warn|allow|error`).";
		emitPortableNativeSurfaceViolation("portable_native_surface", msg, expr.pos, policy, reported, violationIds);
	}

	static function containsOcamlNativeSurface(expr:TypedExpr):Bool {
		if (hasOcamlNativeType(expr.t, 16))
			return true;
		return switch (expr.expr) {
			case TTypeExpr(moduleType):
				moduleTypeStartsWithOcaml(moduleType);
			case TVar(variable, _):
				hasOcamlNativeType(variable.t, 16);
			case TFunction(fn):
				var has = false;
				for (arg in fn.args) {
					if (hasOcamlNativeType(arg.v.t, 16)) {
						has = true;
						break;
					}
				}
				has;
			case _:
				false;
		}
	}

	static function moduleTypeStartsWithOcaml(moduleType:ModuleType):Bool {
		return switch (moduleType) {
			case TClassDecl(classRef): final cls = classRef.get(); cls.pack.length > 0 && cls.pack[0] == "ocaml";
			case TEnumDecl(enumRef): final en = enumRef.get(); en.pack.length > 0 && en.pack[0] == "ocaml";
			case TTypeDecl(typeRef): final td = typeRef.get(); td.pack.length > 0 && td.pack[0] == "ocaml";
			case TAbstract(abstractRef): final ab = abstractRef.get(); ab.pack.length > 0 && ab.pack[0] == "ocaml";
		}
	}

	static function hasOcamlNativeType(type:Type, maxDepth:Int):Bool {
		if (maxDepth <= 0)
			return false;
		return switch (type) {
			case TInst(classRef, params): final cls = classRef.get(); (cls.pack.length > 0 && cls.pack[0] == "ocaml") || typeParamsContainOcaml(params,
					maxDepth - 1);
			case TEnum(enumRef, params): final en = enumRef.get(); (en.pack.length > 0 && en.pack[0] == "ocaml") || typeParamsContainOcaml(params,
					maxDepth - 1);
			case TType(typeRef, params): final td = typeRef.get(); (td.pack.length > 0 && td.pack[0] == "ocaml") || typeParamsContainOcaml(params,
					maxDepth - 1) || hasOcamlNativeType(td.type, maxDepth - 1);
			case TAbstract(abstractRef, params): final ab = abstractRef.get(); (ab.pack.length > 0 && ab.pack[0] == "ocaml") || typeParamsContainOcaml(params,
					maxDepth
					- 1) || hasOcamlNativeType(ab.type, maxDepth - 1);
			case TFun(args, ret): var has = false; for (arg in args) {
					if (hasOcamlNativeType(arg.t, maxDepth - 1)) {
						has = true;
						break;
					}
				} has || hasOcamlNativeType(ret, maxDepth - 1);
			case TAnonymous(anonRef):
				var has = false;
				for (field in anonRef.get().fields) {
					if (hasOcamlNativeType(field.type, maxDepth - 1)) {
						has = true;
						break;
					}
				}
				has;
			case TDynamic(inner): inner != null && hasOcamlNativeType(inner, maxDepth - 1);
			case TLazy(thunk):
				hasOcamlNativeType(thunk(), maxDepth - 1);
			case TMono(ref): final resolved = ref.get(); resolved != null && hasOcamlNativeType(resolved, maxDepth - 1);
		}
	}

	static function typeParamsContainOcaml(params:Array<Type>, maxDepth:Int):Bool {
		for (param in params) {
			if (hasOcamlNativeType(param, maxDepth))
				return true;
		}
		return false;
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

	static function normalizeModuleLabel(moduleName:Null<String>):String {
		if (moduleName != null && moduleName.length > 0)
			return moduleName;
		return "<unknown>";
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
