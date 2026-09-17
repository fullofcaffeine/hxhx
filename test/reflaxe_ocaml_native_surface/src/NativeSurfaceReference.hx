#if macro
import haxe.macro.Type;

/** Test-only copy of the pre-optimization recurrence; it owns no production path. */
class NativeSurfaceReference {
	static inline final NATIVE_SURFACE_OCAML = 1;
	static inline final NATIVE_SURFACE_HAXE_ATOMIC = 2;

	static function packageNativeSurfaceMask(pack:Array<String>):Int {
		var found = 0;
		if (pack.length > 0 && pack[0] == "ocaml")
			found |= NATIVE_SURFACE_OCAML;
		if (pack.length > 1 && pack[0] == "haxe" && pack[1] == "atomic")
			found |= NATIVE_SURFACE_HAXE_ATOMIC;
		return found;
	}

	/**
		Retains the previous walk, including lazy evaluation and monomorph reads.

		The depth limit preserves the previous fail-safe boundary for recursive aliases. Once every
		requested family is found, later branches are skipped because they cannot change policy output.
	**/
	public static function find(type:Type, maxDepth:Int, requestedMask:Int):Int {
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
				found | find(typeDef.type, maxDepth - 1, requestedMask & ~found);
			case TAbstract(abstractRef, params):
				final abstractDef = abstractRef.get();
				var found = packageNativeSurfaceMask(abstractDef.pack) & requestedMask;
				found |= typeParamsNativeSurfaceMask(params, maxDepth - 1, requestedMask & ~found);
				found | find(abstractDef.type, maxDepth - 1, requestedMask & ~found);
			case TFun(args, ret):
				var found = 0;
				for (arg in args) {
					found |= find(arg.t, maxDepth - 1, requestedMask & ~found);
					if (found == requestedMask)
						break;
				}
				found | find(ret, maxDepth - 1, requestedMask & ~found);
			case TAnonymous(anonRef):
				var found = 0;
				for (field in anonRef.get().fields) {
					found |= find(field.type, maxDepth - 1, requestedMask & ~found);
					if (found == requestedMask)
						break;
				}
				found;
			case TDynamic(inner): inner == null ? 0 : find(inner, maxDepth - 1, requestedMask);
			case TLazy(thunk):
				find(thunk(), maxDepth - 1, requestedMask);
			case TMono(ref):
				final resolved = ref.get();
				resolved == null ? 0 : find(resolved, maxDepth - 1, requestedMask);
		}
	}

	static function typeParamsNativeSurfaceMask(params:Array<Type>, maxDepth:Int, requestedMask:Int):Int {
		var found = 0;
		for (param in params) {
			found |= find(param, maxDepth, requestedMask & ~found);
			if (found == requestedMask)
				break;
		}
		return found;
	}
}
#end
