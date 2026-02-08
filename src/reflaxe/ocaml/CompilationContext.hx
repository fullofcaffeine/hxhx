package reflaxe.ocaml;

import haxe.macro.Type;
import reflaxe.ocaml.OcamlNameTools;

/**
 * Per-compilation, instance-based state for reflaxe.ocaml.
 *
 * M2+ will expand this to track mutability, renames, and other stateful decisions
 * required for correct OCaml emission (especially around closures).
 */
class CompilationContext {
	/**
		Optional macro-time logger used for opt-in profiling.

		Why
		- Stage0 bootstrap builds (notably `packages/hxhx`) can spend a long time inside macro-time
		  passes like TypedExpr lowering, and default Haxe logs do not indicate progress.

		What
		- When non-null, internal compiler phases may call this with concise, newline-free messages.
		- The OCaml backend wires this up when `-D reflaxe_ocaml_profile` is enabled.
	**/
	public var profileLogLine:Null<String->Void> = null;

	/** Tracks renames applied to Haxe locals to avoid collisions and keep output stable. */
	public final variableRenameMap:Map<String, String> = [];

	/** Tracks variables that are assigned after initialization (mutability inference hook). */
	public final assignedVars:Map<String, Bool> = [];

	/**
	 * Set of static fields (`pack.Type.field`) that are assigned after initialization.
	 *
	 * Why
	 * - In OCaml, `let x = ...` bindings are immutable.
	 * - Haxe `static var` fields are mutable by default and can be reassigned from any module.
	 * - We currently model mutable statics by emitting them as `ref` cells and lowering:
	 *   - reads: `MyClass.x` → `!MyClass.x`
	 *   - writes: `MyClass.x = v` → `MyClass.x := v`
	 *
	 * How
	 * - Computed once after typing (see `OcamlCompiler`’s `onAfterTyping` prepass).
	 */
	public final mutableStaticFields:Map<String, Bool> = [];

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
	/** Current super class constructor signature (excluding implicit `self`). */
	public var currentSuperCtorArgs:Null<Array<{ name:String, opt:Bool, t:Type }>> = null;

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

	/**
	 * Enum constructor names by enum full name (`pack.Enum`).
	 *
	 * Why
	 * - `Type.getEnumConstructs(E)` returns the list of constructor identifiers for `E`.
	 * - OCaml variants do not carry reflection metadata; we must generate it at compile time.
	 */
	public final enumConstructsByFullName:Map<String, Array<String>> = [];

	/**
	 * Defining module id for each compiled enum full name (`pack.Enum` → `pack.Module`).
	 *
	 * Why
	 * - The runtime constructor registry (`HxType.register_enum_ctor`) needs to reference the
	 *   actual OCaml variant constructors, which live in the module that defines the enum.
	 * - `HxTypeRegistry.ml` is emitted at the end of compilation, so it can't cheaply “look
	 *   back” to the originating enum module unless we record it during enum compilation.
	 */
	public final enumModuleIdByFullName:Map<String, String> = [];

	/**
	 * Constructor signatures by enum+constructor (`pack.Enum:Ctor`).
	 *
	 * Why
	 * - `Type.createEnum(e, ctorName, params)` accepts `e : Dynamic` in portable code.
	 *   Upstream tests intentionally do `var ex:Dynamic = MyEnum; Type.createEnum(ex, ...)`
	 *   to ensure targets handle the runtime case (not just compile-time lowering).
	 * - To implement that efficiently in OCaml, we generate a runtime registry of constructor
	 *   closures that:
	 *   - validate required arity,
	 *   - pad omitted optional args with `hx_null`,
	 *   - unbox dynamic primitives (notably boxed Bool) into the expected OCaml types.
	 *
	 * How
	 * - Seeded in `OcamlCompiler.compileEnumImpl` from each enum field's typed function signature.
	 * - Consumed in `OcamlCompiler.onOutputComplete()` to emit `HxType.register_enum_ctor` entries.
	 */
	public final enumCtorArgsByFullNameAndCtor:Map<String, Array<{ name:String, opt:Bool, t:Type }>> = [];

	/**
	 * Output file id overrides for Haxe modules.
	 *
	 * Why
	 * - Reflaxe derives the output filename (compilation unit) from `BaseType.moduleId()`, which
	 *   flattens module ids by replacing `.` with `_`.
	 * - Haxe `@:generic` specialization can produce *extremely long* module ids that embed the
	 *   fully-qualified type parameters (see upstream `Issue3090`), which can exceed OS filename
	 *   limits (e.g. 255 bytes on macOS) and crash codegen mid-run.
	 *
	 * How
	 * - For “normal” module ids we keep the default file id.
	 * - When the flattened file id would exceed our safe threshold, we generate a stable,
	 *   hash-suffixed short id and use it consistently:
	 *   - as the output filename override (via `BaseCompiler.setOutputFileName`)
	 *   - as the OCaml module name used at cross-module reference sites.
	 */
	public final fileIdOverrideByModuleId:Map<String, String> = [];

	public function fileIdForModuleId(moduleId:String):String {
		if (moduleId == null || moduleId.length == 0) return "Main";
		final existing = fileIdOverrideByModuleId.get(moduleId);
		if (existing != null) return existing;

		// Mirror Reflaxe's default `BaseType.moduleId()` behavior for non-overridden modules.
		final raw = StringTools.replace(moduleId, ".", "_");

		// Conservative safety margin below common filesystem limits for a single path component.
		final maxLen = 180;
		if (raw.length <= maxLen) return raw;

		final hash = haxe.crypto.Md5.encode(raw).substr(0, 12);
		final keep = 64;
		final prefix = raw.substr(0, keep);
		var shortId = prefix + "__" + hash;

		// Ensure we never exceed the safety margin (worst-case: prefix contains multi-byte chars).
		if (shortId.length > maxLen) {
			shortId = raw.substr(0, 32) + "__" + hash;
		}

		fileIdOverrideByModuleId.set(moduleId, shortId);
		return shortId;
	}

	public function ocamlModuleNameForModuleId(moduleId:String):String {
		final fileId = fileIdForModuleId(moduleId);
		if (fileId == null || fileId.length == 0) return "Main";
		final first = fileId.charCodeAt(0);
		final isLower = first >= 97 && first <= 122;
		return isLower ? (String.fromCharCode(first - 32) + fileId.substr(1)) : fileId;
	}

	/**
	 * Constructor signatures by class full name (`pack.Type`).
	 *
	 * Why
	 * - `Type.createInstance(C, args)` needs to call `C`'s constructor at runtime.
	 * - Our compiled constructors are regular OCaml functions with a fixed arity.
	 * - Reflection passes arguments as `Array<Dynamic>`, so we need constructor metadata to:
	 *   - validate required args
	 *   - pad omitted optional args with `hx_null` (to avoid partial application)
	 *   - unbox dynamic primitives (notably boxed Bool) into the expected OCaml types.
	 *
	 * How
	 * - Seeded in `OcamlCompiler.compileClassImpl` from the typed constructor signature.
	 * - Consumed in `OcamlCompiler.onOutputComplete()` to generate `HxTypeRegistry` ctor registrations.
	 */
	public final ctorArgsByFullName:Map<String, Array<{ name:String, opt:Bool, t:Type }>> = [];
	/**
	 * Whether a class has a constructor available after typing/DCE.
	 *
	 * Why
	 * - Some “static-only” utility classes have their implicit default constructor
	 *   removed by DCE when no `new`/reflection path can reach it.
	 * - `HxTypeRegistry` should only register `Type.createInstance` constructors for
	 *   classes that actually have a `create`/constructor surface emitted.
	 */
	public final ctorPresentByFullName:Map<String, Bool> = [];

	/**
	 * The defining module id for each compiled class full name (`pack.Type` → `pack.Module`).
	 *
	 * Why
	 * - Our OCaml value names are scoped by module and "primary type", so registry code
	 *   needs the module id to reference `Type.create` correctly.
	 */
	public final classModuleIdByFullName:Map<String, String> = [];

	/**
	 * For each compiled class full name, the full set of runtime "type tags" that should
	 * be considered a match for typed catches.
	 *
	 * Why:
	 * - `throw` sites may only know a *static* type (e.g. `Base`) even when the runtime
	 *   value is a subclass (`Child`), or the throw expression may be `Dynamic`.
	 * - We keep typed catches fast by matching on tags (strings) rather than doing deep
	 *   OCaml runtime shape inspection.
	 *
	 * This is consumed by `HxTypeRegistry.init()` which registers per-class tag sets for
	 * runtime merging at throw time. (bd: haxe.ocaml-3ta)
	 */
	public final classTagsByFullName:Map<String, Array<String>> = [];

	/**
	 * Direct instance field names declared on each compiled class (`Type.getInstanceFields` support).
	 *
	 * Note: `Type.getInstanceFields` includes inherited fields, but the runtime registry stores the
	 * precomputed transitive closure. We keep direct fields here so `HxTypeRegistry` generation can
	 * build the inherited set deterministically at the end of compilation.
	 */
	public final directInstanceFieldsByFullName:Map<String, Array<String>> = [];

	/**
	 * Direct static field names declared on each compiled class (`Type.getClassFields` support).
	 *
	 * Semantics: Haxe does not include inherited static fields in `Type.getClassFields`, so we keep
	 * this as the direct (non-inherited) set.
	 */
	public final directStaticFieldsByFullName:Map<String, Array<String>> = [];

	/**
	 * Immediate superclass full name for each compiled class, when one exists.
	 *
	 * Used to compute inherited instance fields at registry generation time.
	 */
	public final superByFullName:Map<String, String> = [];

	/**
	 * Whether the output needs OCaml-native functor instantiations (Map/Set modules).
	 *
	 * Why:
	 * - OCaml's `Map`/`Set` are functorized (`Map.Make`, `Set.Make`).
	 * - We provide a Haxe-typed OCaml-native surface (e.g. `ocaml.StringMap`) that maps to
	 *   pre-instantiated modules like `OcamlNativeStringMap`.
	 * - Those modules must exist as real `.ml` files so dune can compile/link the output.
	 *
	 * This flag is set opportunistically during codegen when we encounter `@:native("OcamlNative*")`
	 * extern references, and is consumed by `OcamlCompiler.onOutputComplete()` to emit the `.ml` files.
	 */
	public var needsOcamlNativeMapSet:Bool = false;

	public function isPrimaryTypeInModule(moduleId:String, typeName:String):Bool {
		final primary = primaryTypeNameByModule.get(moduleId);
		return primary != null ? (primary == typeName) : OcamlNameTools.isPrimaryTypeInModule(moduleId, typeName);
	}

	public function scopedInstanceTypeName(moduleId:String, typeName:String):String {
		return isPrimaryTypeInModule(moduleId, typeName) ? "t" : (OcamlNameTools.typePrefix(typeName) + "_t");
	}

	public function scopedValueName(moduleId:String, typeName:String, memberName:String):String {
		final base = isPrimaryTypeInModule(moduleId, typeName) ? memberName : (OcamlNameTools.typePrefix(typeName) + "_" + memberName);
		// OCaml reserves many identifiers (keywords) which are perfectly valid Haxe member names
		// (e.g. `EReg.match`). If we emit them verbatim as `let match = ...`, dune builds fail with
		// syntax errors. Keep emission deterministic by prefixing those cases with `hx_`.
		return OcamlNameTools.isOcamlReservedValueName(base) ? ("hx_" + base) : base;
	}

	public function new() {}
}
