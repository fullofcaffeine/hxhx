package reflaxe.ocaml;

#if macro
import haxe.macro.Context;
#end
import haxe.macro.Type;
import reflaxe.ocaml.OcamlNameTools;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceReportEntry;
#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerDecision;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
#end

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
		- The OCaml backend wires this up when `-D reflaxe_ocaml_telemetry` is enabled.
	**/
	public var profileLogLine:Null<String->Void> = null;

	/** Tracks renames applied to Haxe locals to avoid collisions and keep output stable. */
	public final variableRenameMap:Map<String, String> = [];

	/** Target-level module bindings that function-local names must not shadow. */
	final reservedModuleValueNames:Map<String, Bool> = [];

	/** Target names already allocated to locals in the current class compilation. */
	final allocatedLocalValueNames:Map<String, Bool> = [];

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

	/** Current super class constructor signature (excluding implicit `self`). */
	public var currentSuperCtorArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = null;

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
	public final enumCtorArgsByFullNameAndCtor:Map<String, Array<{name:String, opt:Bool, t:Type}>> = [];

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

	/**
		Optional prefix applied to emitted Haxe compilation units.

		Why
		- Plugin packaging may need multiple generated backends to coexist without OCaml unit-name
		  collisions.
		- The stable place to enforce that is the module/file id boundary, not downstream patching.

		How
		- `-D ocaml_module_prefix=<Prefix_>` is normalized once per compilation.
		- The prefix is applied to emitted Haxe module units only.
		- Runtime/host-provided units are not renamed here because they are copied/emitted separately.
	**/
	public final modulePrefix:Null<String> = resolveModulePrefix();

	static function sanitizeModulePrefix(raw:String):String {
		final out = new StringBuf();
		for (i in 0...raw.length) {
			final c = raw.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
			out.add((isAlphaNum || c == 95) ? String.fromCharCode(c) : "_");
		}
		return StringTools.trim(out.toString());
	}

	static function resolveModulePrefix():Null<String> {
		#if macro
		final raw = Context.definedValue("ocaml_module_prefix");
		if (raw == null)
			return null;
		final sanitized = sanitizeModulePrefix(raw);
		return sanitized.length == 0 ? null : sanitized;
		#else
		return null;
		#end
	}

	public function fileIdForModuleId(moduleId:String):String {
		if (moduleId == null || moduleId.length == 0)
			return "Main";
		final existing = fileIdOverrideByModuleId.get(moduleId);
		if (existing != null)
			return existing;

		// Mirror Reflaxe's default `BaseType.moduleId()` behavior for non-overridden modules.
		final base = StringTools.replace(moduleId, ".", "_");
		final raw = modulePrefix != null ? (modulePrefix + base) : base;

		// Conservative safety margin below common filesystem limits for a single path component.
		final maxLen = 180;
		if (raw.length <= maxLen)
			return raw;

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
		if (fileId == null || fileId.length == 0)
			return "Main";
		final first = fileId.charCodeAt(0);
		final isLower = first >= 97 && first <= 122;
		return isLower ? (String.fromCharCode(first - 32) + fileId.substr(1)) : fileId;
	}

	/**
		Returns the OCaml units owned by the current generated Haxe program.

		Runtime planning uses this list to distinguish a normal program reference such as
		`HxClassDecl.getName` from a reference to reflaxe.ocaml's compatibility runtime.
	**/
	public function emittedOcamlModuleNamesSorted():Array<String> {
		final moduleIds:Array<String> = [];
		for (moduleId => _ in emittedHaxeModules)
			moduleIds.push(moduleId);
		moduleIds.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));

		final names:Map<String, Bool> = [];
		for (moduleId in moduleIds)
			names.set(ocamlModuleNameForModuleId(moduleId), true);
		final out:Array<String> = [];
		for (name in names.keys())
			out.push(name);
		out.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
		return out;
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
	public final ctorArgsByFullName:Map<String, Array<{name:String, opt:Bool, t:Type}>> = [];

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

	/**
		Runtime module names observed while constructing or scanning generated OCaml syntax.

		This remains a migration-time consistency signal and selection fallback. New
		semantic lowering code records complete explanations in `runtimeRequirements`
		instead of treating a generated module name as proof of why it is needed.
	**/
	public final runtimeModuleUsage:Map<String, Bool> = [];

	#if (macro || reflaxe_runtime || eval)
	/** Source-rooted explanations recorded where OCaml compatibility support is chosen. **/
	public final runtimeRequirements = new OcamlRuntimeRequirementLedger();
	#end

	/** Sealed semantic place decisions retained for deterministic inspection. */
	final loweredPlaceReportById:Map<String, OcamlLoweredPlaceReportEntry> = [];

	/** Records one lowered place node and rejects contradictory duplicate identities. */
	public function recordLoweredPlaceReport(entry:OcamlLoweredPlaceReportEntry):Void {
		final existing = loweredPlaceReportById.get(entry.id);
		if (existing != null) {
			if (haxe.Json.stringify(existing) != haxe.Json.stringify(entry))
				throw "reflaxe.ocaml internal lowering invariant: place identity reused with different facts: " + entry.id;
			return;
		}
		loweredPlaceReportById.set(entry.id, entry);
	}

	/** Returns lowered place reports in stable identity order. */
	public function loweredPlaceReportsSorted():Array<OcamlLoweredPlaceReportEntry> {
		final reports:Array<OcamlLoweredPlaceReportEntry> = [];
		for (entry in loweredPlaceReportById)
			reports.push(entry);
		reports.sort((left, right) -> left.id < right.id ? -1 : (left.id > right.id ? 1 : 0));
		return reports;
	}

	public function markRuntimeModule(moduleName:String):Void {
		if (moduleName == null || moduleName.length == 0)
			return;
		runtimeModuleUsage.set(moduleName, true);
	}

	public function runtimeModulesSorted():Array<String> {
		final out:Array<String> = [];
		for (moduleName => _ in runtimeModuleUsage)
			out.push(moduleName);
		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	#if (macro || reflaxe_runtime || eval)
	/** Starts a fresh runtime-requirement ledger for one normalized program revision. **/
	public function beginRuntimeRequirementProgram(programRevision:String):Void {
		runtimeRequirements.beginProgram(programRevision);
	}

	/** Records the runtime capabilities already sealed into one place-lowering plan. **/
	public function recordPlaceRuntimeRequirements(decisionId:String, originId:String, source:OcamlLoweredSourceSpan, semanticTypeId:String,
			requirementIds:Array<String>):Void {
		runtimeRequirements.recordPlacePlan(decisionId, originId, source, semanticTypeId, requirementIds);
	}

	/** Records runtime support selected by one sealed non-null Bytes producer. **/
	public function recordBytesProducerRuntimeRequirements(decision:OcamlBytesProducerDecision):Void {
		runtimeRequirements.recordBytesProducer(decision);
	}

	/** Records runtime support selected by one sealed read-only Bytes operation. **/
	public function recordBytesReadRuntimeRequirements(decision:OcamlBytesReadDecision):Void {
		runtimeRequirements.recordBytesRead(decision);
	}

	/** Records runtime support selected by one sealed program representation. **/
	public function recordRepresentationRuntimeRequirements(decision:OcamlRepresentationDecision):Void {
		runtimeRequirements.recordRepresentationDecision(decision);
	}

	/** Records one runtime helper required by compiler-generated output or policy. **/
	public function recordRuntimeInfrastructure(capability:String):Void {
		runtimeRequirements.recordCompilerInfrastructure(capability);
	}

	/** Records a runtime need declared by one emitted typed native extern. **/
	public function recordNativeRuntimeBoundary(capability:String, boundaryId:String, source:OcamlLoweredSourceSpan, nativeSymbol:String):Void {
		runtimeRequirements.recordNativeBoundary(capability, boundaryId, source, nativeSymbol);
	}

	/** Returns decision-point runtime explanations in stable identity order. **/
	public function runtimeRequirementsSorted():Array<OcamlRuntimeRequirement> {
		return runtimeRequirements.requirementsSorted();
	}

	/** Returns roots from recorded runtime requirements, before dependency closure. **/
	public function runtimeRequirementRootsSorted():Array<String> {
		return runtimeRequirements.rootModulesSorted();
	}

	/** Returns a deterministic digest of the current runtime requirement ledger. **/
	public function runtimeRequirementRevision():String {
		return runtimeRequirements.revision();
	}
	#end

	public function isPrimaryTypeInModule(moduleId:String, typeName:String):Bool {
		final primary = primaryTypeNameByModule.get(moduleId);
		return primary != null ? (primary == typeName) : OcamlNameTools.isPrimaryTypeInModule(moduleId, typeName);
	}

	public function scopedInstanceTypeName(moduleId:String, typeName:String):String {
		return isPrimaryTypeInModule(moduleId, typeName) ? "t" : (OcamlNameTools.typePrefix(typeName) + "_t");
	}

	public function scopedValueName(moduleId:String, typeName:String, memberName:String):String {
		final base = isPrimaryTypeInModule(moduleId, typeName) ? memberName : (OcamlNameTools.typePrefix(typeName) + "_" + memberName);
		return OcamlNameTools.normalizeValueIdentifier(base);
	}

	static inline function moduleValueNameKey(moduleId:String, valueName:String):String {
		return moduleId + "::" + valueName;
	}

	/** Records one emitted module-level value so local allocation cannot hide it. */
	public function reserveModuleValueName(moduleId:String, valueName:String):Void {
		reservedModuleValueNames.set(moduleValueNameKey(moduleId, valueName), true);
	}

	/** Starts deterministic local-name allocation for one class compilation. */
	public function resetLocalValueNames():Void {
		variableRenameMap.clear();
		allocatedLocalValueNames.clear();
	}

	/**
		Returns a stable OCaml local name without shadowing a module-level value.

		OCaml local bindings remain in scope for the rest of a nested expression. A
		Haxe temporary named like a static method can therefore hide later calls to
		that method unless target allocation treats module bindings as reserved.
	**/
	public function localValueName(sourceName:String):String {
		final existing = variableRenameMap.get(sourceName);
		if (existing != null)
			return existing;

		final base = sourceName == "_" ? "_hx" : OcamlNameTools.normalizeValueIdentifier(sourceName);
		var candidate = base;
		var suffix = 1;
		while (reservedModuleValueNames.exists(moduleValueNameKey(currentModuleId ?? "", candidate))
			|| allocatedLocalValueNames.exists(candidate)) {
			candidate = base + "__local" + (suffix == 1 ? "" : Std.string(suffix));
			suffix += 1;
		}

		variableRenameMap.set(sourceName, candidate);
		allocatedLocalValueNames.set(candidate, true);
		return candidate;
	}

	/**
		Normalizes OCaml record labels used for emitted class instance fields.

		Why:
		- Haxe class fields can use identifiers that are OCaml keywords (for example, `method`).
		- Our class representation uses OCaml records; labels must therefore be valid OCaml value identifiers.
		- We keep a single normalization policy so type declarations, record literals, and field access
		  callsites all agree on the same label spelling.
	**/
	public function ocamlRecordLabel(fieldName:String):String {
		return OcamlNameTools.normalizeValueIdentifier(fieldName);
	}

	public function new() {}
}
