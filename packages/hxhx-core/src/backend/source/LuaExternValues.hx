package backend.source;

import haxe.ds.StringMap;

private final nativeMarker = "\x00hxhx.lua.extern.path";

/**
	Resolve explicitly named extern values from the exact program declarations.
	Lookups stay at each authored use, so host rebinding remains observable and
	type-only extern declarations never cause an eager host lookup. This admits
	values only; it does not invent instance predicates for host library tables.
 */
class LuaExternValues {
	final owners:StringMap<TypedBackendClassSemanticFacts> = new StringMap();
	final functions:Array<TypedBackendFunctionProjection> = [];
	final initializers:Array<TypedBackendFieldInitializerProjection> = [];

	public function new(program:backend.GenIrProgram) {
		for (module in program.getTypedModules())
			for (owner in module.getBackendProjection().getClasses()) {
				final facts = owner.requireSemanticFacts();
				if (facts.getIsExtern())
					owners.set(facts.getClassIdentity(), facts);
				for (fn in owner.getFunctions())
					functions.push(fn);
				for (field in owner.getFieldInitializers())
					initializers.push(field);
			}
	}

	/** Validate all occurrences before publication, retaining rejection for every unsupported operation. */
	public function validate():Void {
		for (fn in functions)
			for (entry in fn.getRuntimeTypeCatalog().getEntries())
				value(fn.requireRuntimeType(entry.getExpression()));
		for (field in initializers)
			for (entry in field.getRuntimeTypeCatalog().getEntries())
				value(field.requireRuntimeType(entry.getExpression()));
	}

	public function functionValue(fn:TypedBackendFunctionProjection, expression:HxExpr):HxExpr {
		if (functions.indexOf(fn) < 0)
			throw "Lua extern value requires its exact program function";
		return value(fn.requireRuntimeType(expression));
	}

	public function initializerValue(field:TypedBackendFieldInitializerProjection, expression:HxExpr):HxExpr {
		if (initializers.indexOf(field) < 0)
			throw "Lua extern value requires its exact program initializer";
		return value(field.requireRuntimeType(expression));
	}

	function value(entry:TypedBackendRuntimeTypeOccurrence):HxExpr {
		entry.assertCurrent();
		final owner = switch entry.getTarget().getKind() {
			case Nominal(identity): owners.get(identity.getCanonicalName());
			case _: null;
		};
		if (entry.getValue() != null || owner == null || owner.getNativeName() == null || owner.getNativeName().getName() == null)
			throw "Lua source target backend does not support runtime type operands: " + entry.getTarget().getSemanticKey();
		return nativePath(owner.getNativeName().getName());
	}

	/** The selected declaration owns both the host table and its optional renamed method. */
	public function staticCall(call:TypedExactStaticCallSource.TypedExactStaticCall):Null<HxExpr> {
		final callee = methodValue(call.owner, call.declaration);
		return callee == null ? null : HxExpr.ECall(callee, call.arguments);
	}

	/** Saved methods retain the same host lookup and native member name as direct calls. */
	public function methodValue(ownerIdentity:String, declarationIdentity:String):Null<HxExpr> {
		final owner = owners.get(ownerIdentity);
		if (owner == null || owner.getNativeName() == null || owner.getNativeName().getName() == null)
			return null;
		final method = owner.findMethod(declarationIdentity);
		if (method == null || !method.isStatic)
			throw "Lua extern call lost its exact static declaration";
		final name = method.nativeName.getName();
		if (name != null)
			identifier(name);
		return nativePath(owner.getNativeName().getName() + "." + (name == null ? method.name : name));
	}

	/** Metadata becomes structured field access, never raw target source. */
	static function nativePath(path:String):HxExpr {
		final parts = path.split(".");
		for (part in parts)
			identifier(part);
		return HxExpr.ECall(HxExpr.EUnsupported(nativeMarker), [HxExpr.EArrayDecl(parts.map(part -> HxExpr.EString(part)))]);
	}

	/** A closed target operation prevents ordinary Haxe field intrinsics from interpreting host names. */
	public static function decode(expression:HxExpr):Null<Array<String>> {
		return switch expression {
			case ECall(EUnsupported(marker), [EArrayDecl(parts)]) if (marker == nativeMarker):
				if (parts.length == 0)
					throw "Lua extern path lost its host root";
				[
					for (part in parts)
						switch part {
							case EString(name):
								identifier(name);
								name;
							case _:
								throw "Lua extern path requires literal identifiers";
						}
				];
			case ECall(EUnsupported(marker), _) if (marker == nativeMarker):
				throw "Lua extern path has malformed target data";
			case _: null;
		};
	}

	static function identifier(name:String):Void {
		if (!~/^[A-Za-z_][A-Za-z0-9_]*$/.match(name) || [
			"and",
			"break",
			"do",
			"else",
			"elseif",
			"end",
			"false",
			"for",
			"function",
			"goto",
			"if",
			"in",
			"local",
			"nil",
			"not",
			"or",
			"repeat",
			"return",
			"then",
			"true",
			"until",
			"while"
		].indexOf(name) >= 0)
			throw "unsupported Lua extern native identifier: " + name;
	}
}
