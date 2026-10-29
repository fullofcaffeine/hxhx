package backend.source;

/**
	Required state boundary for recursive source-target function rendering.

	A program frame supports syntax outside typed executable units. Python and
	Lua retain the exact function and program for control destinations and enum
	declarations. Java and C# also carry native local representation facts. PHP
	functions and field initializers carry their target renderer and immutable
	lexical scope. Function frames share a temporary-name supply across nested
	branches; deriving a child scope never resets it or changes the typed catalog.
**/
enum SourceFunctionRenderFrame {
	Program(target:SourceNativeTarget);
	TypedFunction(target:SourceNativeTarget, projection:TypedBackendFunctionProjection, names:SourceTemporaryNames, program:backend.GenIrProgram,
		?lua:LuaControlScope);
	NativeFunction(locals:SourceNativeFunctionLocals, names:SourceTemporaryNames);
	PhpFunction(renderer:PhpFunctionBodyRenderer, scope:PhpLexicalRenderScope, names:SourceTemporaryNames);
}

/** One rendering owns temporary names across nested branches, without changing semantic local catalogs. */
class SourceTemporaryNames {
	final reserved:String->Bool;
	var next:Int = 0;

	public function new(reserved:String->Bool) {
		this.reserved = reserved;
	}

	public function fresh():String {
		var name:String;
		do {
			name = "_hx_pattern_" + next++;
		} while (reserved(name));
		return name;
	}
}

/** Create checked function frames and reject requests for another target's facts. */
class SourceFunctionRenderFrameTools {
	public static function target(frame:SourceFunctionRenderFrame):SourceNativeTarget {
		if (frame == null)
			throw "source function rendering requires an explicit render frame";
		return switch (frame) {
			case Program(target): target;
			case TypedFunction(target, _, _, _): target;
			case NativeFunction(locals, _): locals.target;
			case PhpFunction(_, _, _): Php;
		};
	}

	public static function requirePhpRenderer(frame:SourceFunctionRenderFrame):PhpFunctionBodyRenderer {
		return switch (frame) {
			case PhpFunction(renderer, _, _): renderer;
			case Program(_) | NativeFunction(_, _) | TypedFunction(_, _, _, _):
				throw "source " + targetLabel(target(frame)) + " frame cannot answer PHP function-state queries";
		};
	}

	/** Return the request-owned program renderer shared by the exact function facts. **/
	public static function requirePhpProgramRenderer(frame:SourceFunctionRenderFrame):PhpProgramBodyRenderer
		return requirePhpRenderer(frame).getProgramRenderer();

	public static function requirePhpScope(frame:SourceFunctionRenderFrame):PhpLexicalRenderScope {
		return switch (frame) {
			case PhpFunction(_, scope, _): scope;
			case Program(_) | NativeFunction(_, _) | TypedFunction(_, _, _, _):
				throw "source " + targetLabel(target(frame)) + " frame cannot answer PHP lexical-scope queries";
		};
	}

	public static function withPhpScope(frame:SourceFunctionRenderFrame, scope:PhpLexicalRenderScope):SourceFunctionRenderFrame {
		if (scope == null)
			throw "PHP function rendering requires an explicit lexical scope";
		return switch (frame) {
			case PhpFunction(renderer, _, names): PhpFunction(renderer, scope, names);
			case Program(_) | NativeFunction(_, _) | TypedFunction(_, _, _, _):
				throw "source " + targetLabel(target(frame)) + " frame cannot derive a PHP lexical scope";
		};
	}

	/** Create the exact root frame for one request-owned PHP renderer. **/
	public static function forPhpRenderer(renderer:PhpFunctionBodyRenderer):SourceFunctionRenderFrame {
		if (renderer == null)
			throw "PHP function rendering requires a request-owned renderer";
		final plan = renderer.getPlan();
		final scope = PhpLexicalRenderScope.forFunction(plan);
		return PhpFunction(renderer, plan.usesThisValueSlot() ? scope.withThisValueSlot(true) : scope,
			new SourceTemporaryNames(name -> plan.findLocalByTargetName(name) != null));
	}

	/** Each function render starts a fresh name supply and retains its exact return destination. */
	public static function forTypedFunction(target:SourceNativeTarget, projection:TypedBackendFunctionProjection, program:backend.GenIrProgram,
			?luaPlan:LuaClassPlan):SourceFunctionRenderFrame {
		if (target != Python && target != Lua)
			throw "typed source function frame requires Python or Lua";
		projection.requireCaptureCatalog().assertCurrent();
		var found = false;
		for (module in program.getTypedModules())
			for (owner in module.getBackendProjection().getClasses())
				for (body in owner.getFunctions())
					if (body == projection) {
						if (luaPlan != null)
							luaPlan.requireProjection(owner);
						found = true;
					}
		if (!found)
			throw "typed source frame requires the exact program function projection";
		return TypedFunction(target, projection, new SourceTemporaryNames(name -> projection.getLocalCatalog().findByProjectedName(name) != null), program,
			target == Lua ? new LuaControlScope(luaPlan == null ? new LuaClassPlan(program) : luaPlan) : null);
	}

	/** Lua protected calls derive a scope without changing the exact executable or name supply. */
	public static function withLuaControl(frame:SourceFunctionRenderFrame, scope:LuaControlScope):SourceFunctionRenderFrame
		return switch frame {
			case TypedFunction(Lua, projection, names, program, previous) if (previous != null && previous.classPlan == scope.classPlan):
				TypedFunction(Lua, projection, names, program, scope);
			case _: throw "Lua control requires its exact function frame";
		};

	public static function requireLuaControl(frame:SourceFunctionRenderFrame):LuaControlScope
		return switch frame {
			case TypedFunction(Lua, _, _, _, scope) if (scope != null): scope;
			case _: throw "Lua control requires its current protected-call scope";
		};

	/** Target spelling comes from the selected declaration, never from the case label. */
	public static function requireEnumName(frame:SourceFunctionRenderFrame, owner:TyNominalTypeId):String
		return switch frame {
			case TypedFunction(target, _, _, program): SourceEnumPatternOwner.requireName(program, owner, target);
			case NativeFunction(locals, _): locals.requireEnumName(owner);
			case _: throw "source enum requires its exact non-PHP function frame";
		};

	public static function forNativeFunction(locals:SourceNativeFunctionLocals):SourceFunctionRenderFrame
		return NativeFunction(locals, new SourceTemporaryNames(locals.hasLocal));

	/** Reuse the enclosing method identity when adapting shared statement regions. */
	public static function requireRootControlIdentity(frame:SourceFunctionRenderFrame):String
		return switch frame {
			case TypedFunction(_, projection, _, _): projection.requireRootControlIdentity();
			case NativeFunction(locals, _): locals.requireRootControlIdentity();
			case PhpFunction(renderer, _, _): renderer.getPlan().requireRootControlIdentity();
			case Program(_): throw "shared source control requires its exact function owner";
		};

	public static function freshPatternName(frame:SourceFunctionRenderFrame):String
		return switch frame {
			case TypedFunction(_, _, names, _) | NativeFunction(_, names) | PhpFunction(_, _, names): names.fresh();
			case Program(_): throw "guarded source control requires function-owned temporary names";
		};

	/** Equal-looking patterns cannot borrow another function's selected constructor. */
	public static function findNamedPattern(frame:SourceFunctionRenderFrame, pattern:HxSwitchPattern):Null<TypedNamedPattern>
		return switch frame {
			case TypedFunction(_, projection, _, _): projection.findNamedPattern(pattern);
			case NativeFunction(locals, _): locals.findNamedPattern(pattern);
			case PhpFunction(renderer, _, _): renderer.getPlan().findNamedPattern(pattern);
			case Program(_): throw "named guarded pattern requires its exact function owner";
		};

	static function targetLabel(target:SourceNativeTarget):String
		return switch (target) {
			case Python: "Python";
			case Java: "Java";
			case Cs: "C#";
			case Php: "PHP";
			case Lua: "Lua";
		};
}
