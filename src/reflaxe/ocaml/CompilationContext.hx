package reflaxe.ocaml;

import reflaxe.ocaml.OcamlNameTools;

/**
 * Per-compilation, instance-based state for reflaxe.ocaml.
 *
 * M2+ will expand this to track mutability, renames, and other stateful decisions
 * required for correct OCaml emission (especially around closures).
 */
class CompilationContext {
	/** Tracks renames applied to Haxe locals to avoid collisions and keep output stable. */
	public final variableRenameMap:Map<String, String> = [];

	/** Tracks variables that are assigned after initialization (mutability inference hook). */
	public final assignedVars:Map<String, Bool> = [];

	/** Current module id (as seen by Reflaxe/Haxe), for debug and naming decisions. */
	public var currentModuleId:Null<String> = null;

	/** Current Haxe type name being compiled (used to disambiguate same-module references). */
	public var currentTypeName:Null<String> = null;

	/** Current Haxe type full name (`pack.Type`), when known. */
	public var currentTypeFullName:Null<String> = null;

	/** Current super class full name (`pack.Type`), when compiling a class with `extends`. */
	public var currentSuperFullName:Null<String> = null;
	/** Current super class module id (e.g. `pack.Module`). */
	public var currentSuperModuleId:Null<String> = null;
	/** Current super class type name. */
	public var currentSuperTypeName:Null<String> = null;

	/**
	 * Set of Haxe full names that participate in inheritance (either extend something, or are extended).
	 *
	 * Why:
	 * - We implement a minimal “virtual dispatch” subset for overriding (M10).
	 * - The builder needs to know when to emit `self.foo self arg` instead of static `Foo.foo self arg`.
	 */
	public final virtualTypes:Map<String, Bool> = [];
	public var virtualTypesComputed:Bool = false;

	/** Haxe full names of interfaces (non-stdlib only, for now). */
	public final interfaceTypes:Map<String, Bool> = [];

	/**
	 * Haxe full names of types that must support dynamic dispatch (inheritance and/or interfaces).
	 *
	 * This is the set the builder consults to decide whether `obj.foo()` is lowered as:
	 * - static module function call (`Foo.foo obj ...`) for monomorphic cases, or
	 * - record-stored function field call (`obj.foo obj ...`) for polymorphic dispatch.
	 */
	public final dispatchTypes:Map<String, Bool> = [];

	/**
	 * For each Haxe module id, which contained type should be treated as the “primary type”
	 * for OCaml identifier scoping purposes.
	 *
	 * Why:
	 * - Some modules intentionally define a single type whose name does *not* match the file/module name.
	 * - We want to keep historical short names (`create`, `t`, etc.) stable for those modules.
	 * - When there are multiple types in a module, we still need collision-free scoping.
	 */
	public final primaryTypeNameByModule:Map<String, String> = [];

	/** True when compiling a type that originates from Haxe's standard library sources. */
	public var currentIsHaxeStd:Bool = false;

	/**
	 * Tracks Haxe module dot-paths that were compiled in this compilation.
	 *
	 * Why:
	 * - We emit OCaml files using Reflaxe's `FilePerModule` mode.
	 * - For OCaml ergonomics, we additionally generate “package alias” modules that
	 *   provide `Haxe.Io.Path`-style dot access while keeping a collision-free flat
	 *   namespace for real module filenames (`Haxe_io_Path`).
	 */
	public final emittedHaxeModules:Map<String, Bool> = [];

	/**
	 * Non-stdlib type names that should be pre-registered for `Type.resolveClass/resolveEnum`.
	 *
	 * Why:
	 * - `Type.resolveClass(name)` accepts runtime strings, so a pure compile-time lowering
	 *   isn't sufficient for portable code.
	 * - We keep this registry intentionally conservative for now (non-stdlib only) to
	 *   avoid bloating small outputs; expand when we start running upstream suites.
	 */
	public final nonStdTypeRegistryClasses:Map<String, Bool> = [];
	public final nonStdTypeRegistryEnums:Map<String, Bool> = [];

	public function isPrimaryTypeInModule(moduleId:String, typeName:String):Bool {
		final primary = primaryTypeNameByModule.get(moduleId);
		return primary != null ? (primary == typeName) : OcamlNameTools.isPrimaryTypeInModule(moduleId, typeName);
	}

	public function scopedInstanceTypeName(moduleId:String, typeName:String):String {
		return isPrimaryTypeInModule(moduleId, typeName) ? "t" : (OcamlNameTools.typePrefix(typeName) + "_t");
	}

	public function scopedValueName(moduleId:String, typeName:String, memberName:String):String {
		return isPrimaryTypeInModule(moduleId, typeName) ? memberName : (OcamlNameTools.typePrefix(typeName) + "_" + memberName);
	}

	public function new() {}
}
