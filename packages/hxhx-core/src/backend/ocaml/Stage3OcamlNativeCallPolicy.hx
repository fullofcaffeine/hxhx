package backend.ocaml;

/**
	Which standard calls the builtin Stage3 OCaml emitter keeps for its native
	`HxMap` adapter, plus the identity of that builtin backend.

	Why this module is small
	- Shared driver code (`hxhx.Stage3BackendPluginSupport`) asks every builtin
	  target for its policy, including compiles for Neko, JavaScript, and other
	  targets that do not put `reflaxe.ocaml` on the classpath. Referencing
	  `OcamlStage3Backend` from here would pull in `OcamlTargetCore`,
	  `EmitterStage`, and with them `reflaxe.ocaml`, and those compiles would
	  fail with "Type not found : reflaxe.ocaml.ast.OcamlASTPrinter".
	- This module therefore depends only on the target descriptor and the typed
	  declaration. `OcamlStage3Backend` reads its ids from here, and
	  `Stage3OcamlMapCalls` reads the retained method set from here.

	What is kept
	- The `Map<K, V>` abstract's inline bodies forward to its backing value
	  through the `haxe.Constraints.IMap` interface. Expanding them would leave
	  interface calls that Stage3 binds to empty placeholders. Kept as `Map`
	  calls, they still carry the applied key and value types, so
	  `Stage3OcamlMapCalls` can render the `HxMap` table that `new Map()`
	  allocated for that key type.
**/
class Stage3OcamlNativeCallPolicy {
	public static inline final TARGET_ID = "ocaml-stage3";
	public static inline final IMPL_ID = "builtin/ocaml-stage3";

	/** Only the builtin Stage3 OCaml emitter can request its native Map operations. */
	public static function forBackend(selected:backend.TargetDescriptor):Null<TyDeclarationInfo->Bool> {
		return selected != null && selected.id == TARGET_ID && selected.implId == IMPL_ID ? retain : null;
	}

	/**
		The instance methods of `StringMap`, `IntMap`, and `ObjectMap`, which are
		also the `Map<K, V>` methods that forward to them unchanged. Each one has
		an adapter in `Stage3OcamlMapCalls`.
	**/
	public static function supportsMapMethod(method:String):Bool {
		return switch method {
			case "set" | "get" | "exists" | "remove" | "keys" | "iterator" | "keyValueIterator" | "copy" | "toString" | "clear": true;
			case _: false;
		};
	}

	/**
		Whether shared preparation must keep this `Map<K, V>` method as a call.
		Only the exact standard declaration qualifies; `arrayWrite` is the method
		that `map[key] = value` selects.
	**/
	public static function retain(declaration:TyDeclarationInfo):Bool {
		if (declaration.getOwner().getCanonicalName() != "haxe.ds.Map"
			|| declaration.getModulePath() != "haxe.ds.Map"
			|| declaration.getIsStatic())
			return false;
		final method = declaration.getSignature().getName();
		return supportsMapMethod(method) || method == "arrayWrite";
	}
}
