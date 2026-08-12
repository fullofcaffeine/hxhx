package reflaxe.ocaml;

#if macro
import haxe.macro.Context;
#end
import haxe.macro.Type;
import reflaxe.ocaml.OcamlNameTools;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceReportEntry;
#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
#if macro
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallRuntimeUseModel.OcamlCallRuntimeUsePlan;
#end
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationDecision;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessDecision;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerDecision;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadDecision;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.lowered.OcamlArrayReadModel.OcamlArrayReadDecision;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan.OcamlArrayIteratorDecision;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicEqualityDecision;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan.OcamlDynamicStringDecision;
import reflaxe.ocaml.lowered.OcamlDynamicBracketReadModel.OcamlDynamicBracketReadDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationDecision;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldDecision;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan.OcamlContainerElementDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopTarget;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchChainDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceConversionDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapStorageAliasDecision;
import reflaxe.ocaml.lowered.OcamlStandardContainerCarrierModel.OcamlStandardContainerCarrierContract;
import reflaxe.ocaml.lowered.OcamlStandardContainerCarrierModel.OcamlStandardContainerCarrierDecision;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierContract;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
#if macro
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectCompareDecision;
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan.OcamlReflectRuntimeUseDecision;
import reflaxe.ocaml.lowered.OcamlStdIsOfTypePlan.OcamlStdIsOfTypeDecision;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryDecision;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan.OcamlStringFromCharCodeDecision;
#end
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlAnonymousStructureRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlStructuralFieldRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlBytesRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlCallRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlEnumRuntimeRequirementRecorder;
#if (macro || reflaxe_runtime)
import reflaxe.ocaml.runtimegen.OcamlReflectCompareRuntimeRequirementRecorder;
#end
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;
import reflaxe.ocaml.ast.OcamlTypeExpr;
#end

/**
	Records how one Haxe enum constructor is represented by native OCaml.

	Haxe assigns one index in declaration order. OCaml instead assigns separate
	numeric sequences to constructors without payloads and constructors with
	payloads. Generated runtime metadata keeps both numbers so reflection can
	report Haxe behavior without treating an OCaml tag as a Haxe index.
**/
typedef OcamlEnumConstructorLayout = {
	final name:String;
	final haxeIndex:Int;
	final carriesPayload:Bool;
	final ocamlTag:Int;
}

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
	 * Haxe constructor order and native OCaml representation by enum full name.
	 *
	 * Dynamic-backed `Type.getEnumConstructs`, `Type.enumConstructor`,
	 * `Type.enumIndex`, and `Type.createEnumIndex` consume this generated
	 * layout. Direct typed calls compile from the same `EnumField.index` values.
	 * Keeping both paths rooted in that typed declaration order prevents drift
	 * when payload and constant constructors are interleaved.
	 */
	public final enumConstructorLayoutsByFullName:Map<String, Array<OcamlEnumConstructorLayout>> = [];

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
	 * Generated zero-argument class `toString` adapters available to Dynamic.
	 *
	 * The final type registry uses this exact emitted method identity to register
	 * runtime dispatch. `HxDynamic` never guesses record layouts or method names.
	 */
	public final dynamicStringifierByFullName:Map<String, {
		moduleId:String,
		sourceTypeName:String,
		targetMethodName:String
	}> = [];

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

	/**
		Counts authorized private-runtime uses in the complete target output.

		Local lowerers prove why one helper is allowed. This request-owned ledger
		then proves that assembly printed each allowed occurrence exactly once.
	**/
	public final finalRuntimeUses = new OcamlFinalRuntimeUseAuthority();

	/**
		Map carrier choices that can become final target types in this request.

		The general type mapper also creates temporary comparison types. Staging keeps
		their checked Haxe origin without claiming runtime support until a hidden use
		ID reaches the final structured output.
	**/
	final pendingStandardMapCarrierByUseId:Map<String, OcamlStandardMapCarrierDecision> = [];

	/** Hidden Map use identities that already activated their final-output plan. */
	final activeStandardMapCarrierUseIds:Map<String, Bool> = [];

	/** Checked Array and Bytes type choices waiting for final structured output. */
	final pendingStandardContainerCarrierByUseId:Map<String, OcamlStandardContainerCarrierDecision> = [];

	/** Hidden Array and Bytes use identities already counted in final output. */
	final activeStandardContainerCarrierUseIds:Map<String, Bool> = [];

	/** Target profile bound to the current runtime-requirement request. */
	var activeRuntimeRequirementProfile:Null<String>;

	/** Program revision bound to the current runtime-requirement request. */
	var activeRuntimeRequirementProgramRevision:Null<String>;
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
	public function beginRuntimeRequirementProgram(programRevision:String, activeProfile:String):Void {
		runtimeRequirements.beginProgram(programRevision);
		finalRuntimeUses.beginProgram(programRevision, activeProfile);
		pendingStandardMapCarrierByUseId.clear();
		activeStandardMapCarrierUseIds.clear();
		pendingStandardContainerCarrierByUseId.clear();
		activeStandardContainerCarrierUseIds.clear();
		activeRuntimeRequirementProfile = activeProfile;
		activeRuntimeRequirementProgramRevision = programRevision;
	}

	/** Records the runtime capabilities already sealed into one place-lowering plan. **/
	public function recordPlaceRuntimeRequirements(decisionId:String, originId:String, source:OcamlLoweredSourceSpan, semanticTypeId:String,
			requirementIds:Array<String>):Void {
		runtimeRequirements.recordPlacePlan(decisionId, originId, source, semanticTypeId, requirementIds);
	}

	/**
		Stages one checked Map carrier until final output uses its hidden identity.

		An unused stage records no runtime requirement. This prevents a temporary type
		candidate from making `HxMap` appear necessary in the published source bundle.
	**/
	public function stageStandardMapCarrierRuntimeUse(decision:OcamlStandardMapCarrierDecision):Void {
		final staged = OcamlStandardMapCarrierContract.copyDecision(decision);
		if (staged.programRevision != activeRuntimeRequirementProgramRevision)
			throw 'Standard Map carrier ${staged.id} uses program revision ${staged.programRevision}; expected $activeRuntimeRequirementProgramRevision.';
		final occurrence = staged.runtimeUseOccurrences[0];
		final existing = pendingStandardMapCarrierByUseId.get(occurrence.id);
		if (existing != null) {
			if (existing.revision != staged.revision || haxe.Json.stringify(existing) != haxe.Json.stringify(staged))
				throw 'Standard Map carrier runtime use ${occurrence.id} was staged with conflicting facts.';
			return;
		}
		pendingStandardMapCarrierByUseId.set(occurrence.id, staged);
	}

	/**
		Activates a staged Map carrier when final structured output contains its ID.

		Activation records the direct `HxMap` requirement and registers one expected
		final use. A plain generated name has no hidden ID, so it cannot call this path.
	**/
	public function activateStandardMapCarrierRuntimeUse(reference:OcamlRuntimeReference):Void {
		final decision = pendingStandardMapCarrierByUseId.get(reference.id);
		if (decision == null)
			return;
		OcamlStandardMapCarrierContract.requireDecision(decision);
		if (decision.programRevision != activeRuntimeRequirementProgramRevision)
			throw 'Standard Map carrier ${decision.id} no longer matches active program revision $activeRuntimeRequirementProgramRevision.';
		final occurrence = decision.runtimeUseOccurrences[0];
		if (reference.planRevision != occurrence.planRevision
			|| reference.ownerId != occurrence.ownerId
			|| reference.domain != occurrence.domain
			|| reference.exactSymbol != occurrence.exactSymbol)
			throw 'Standard Map carrier runtime use ${reference.id} no longer matches its staged facts.';
		if (activeStandardMapCarrierUseIds.exists(reference.id))
			return;
		final activeProfile = activeRuntimeRequirementProfile;
		if (activeProfile == null)
			throw "Standard Map carrier runtime activation requires an active compiler request.";
		runtimeRequirements.recordStandardMapCarrier(decision);
		final authority = new OcamlRuntimeUseAuthority(decision.revision, activeProfile,
			runtimeRequirements.requirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, finalRuntimeUses);
		final checkedReference = authority.typeIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		authority.reconcileType(OcamlTypeExpr.TRuntimeIdent(checkedReference));
		activeStandardMapCarrierUseIds.set(reference.id, true);
	}

	/**
		Stages one checked Array or Bytes carrier until final output uses its ID.

		The type mapper also builds temporary comparison types. An unused temporary
		type must not make its runtime module part of the published source bundle.
	**/
	public function stageStandardContainerCarrierRuntimeUse(decision:OcamlStandardContainerCarrierDecision):Void {
		final staged = OcamlStandardContainerCarrierContract.copyDecision(decision);
		if (staged.programRevision != activeRuntimeRequirementProgramRevision)
			throw 'Standard container carrier ${staged.id} uses program revision ${staged.programRevision}; expected $activeRuntimeRequirementProgramRevision.';
		final occurrence = staged.runtimeUseOccurrences[0];
		final existing = pendingStandardContainerCarrierByUseId.get(occurrence.id);
		if (existing != null) {
			if (existing.revision != staged.revision || haxe.Json.stringify(existing) != haxe.Json.stringify(staged))
				throw 'Standard container carrier runtime use ${occurrence.id} was staged with conflicting facts.';
			return;
		}
		pendingStandardContainerCarrierByUseId.set(occurrence.id, staged);
	}

	/**
		Activates a staged Array or Bytes carrier found in final structured output.

		Activation records the direct runtime dependency and one expected final use.
		A plain generated type name has no hidden ID and cannot enter this path.
	**/
	public function activateStandardContainerCarrierRuntimeUse(reference:OcamlRuntimeReference):Void {
		final decision = pendingStandardContainerCarrierByUseId.get(reference.id);
		if (decision == null)
			return;
		OcamlStandardContainerCarrierContract.requireDecision(decision);
		if (decision.programRevision != activeRuntimeRequirementProgramRevision)
			throw 'Standard container carrier ${decision.id} no longer matches active program revision $activeRuntimeRequirementProgramRevision.';
		final occurrence = decision.runtimeUseOccurrences[0];
		if (reference.planRevision != occurrence.planRevision
			|| reference.ownerId != occurrence.ownerId
			|| reference.domain != occurrence.domain
			|| reference.exactSymbol != occurrence.exactSymbol)
			throw 'Standard container carrier runtime use ${reference.id} no longer matches its staged facts.';
		if (activeStandardContainerCarrierUseIds.exists(reference.id))
			return;
		final activeProfile = activeRuntimeRequirementProfile;
		if (activeProfile == null)
			throw "Standard container carrier runtime activation requires an active compiler request.";
		runtimeRequirements.recordStandardContainerCarrier(decision);
		final authority = new OcamlRuntimeUseAuthority(decision.revision, activeProfile,
			runtimeRequirements.requirementsByIds(decision.runtimeRequirementIds), decision.runtimeUseOccurrences, finalRuntimeUses);
		final checkedReference = authority.typeIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		authority.reconcileType(OcamlTypeExpr.TRuntimeIdent(checkedReference));
		activeStandardContainerCarrierUseIds.set(reference.id, true);
	}

	/**
		Checks every staged private container type against one final output reference.

		Map, Array, and Bytes keep separate typed decision models. This small dispatcher
		lets the final-output observer use one callback without merging their semantics.
	**/
	public function activateStagedTypeRuntimeUse(reference:OcamlRuntimeReference):Void {
		activateStandardMapCarrierRuntimeUse(reference);
		activateStandardContainerCarrierRuntimeUse(reference);
	}

	#if macro
	/** Records runtime support selected by one sealed standard `IMap` call. */
	public function recordStandardIMapRuntimeRequirements(call:OcamlCallDecision):Void {
		if (call.standardIMapTarget == null)
			throw 'Standard IMap call "${call.id}" has no sealed runtime target.';
		runtimeRequirements.recordStandardIMapCall(call.id, call.source, call.profileEligibility, call.standardIMapTarget);
	}

	/** Records runtime support selected by one concrete-to-`IMap` adapter. */
	public function recordIMapInterfaceRuntimeRequirements(decision:OcamlIMapInterfaceConversionDecision):Void {
		runtimeRequirements.recordIMapInterfaceConversion(decision);
	}

	/** Records runtime support selected by one nullable standard-Map storage alias. */
	public function recordIMapStorageAliasRuntimeRequirements(decision:OcamlIMapStorageAliasDecision):Void {
		runtimeRequirements.recordIMapStorageAlias(decision);
	}

	/** Records runtime support selected by one exceptional typed `Reflect.compare`. */
	public function recordReflectCompareRuntimeRequirements(decision:OcamlReflectCompareDecision):Void {
		OcamlReflectCompareRuntimeRequirementRecorder.record(runtimeRequirements, decision);
	}

	/** Records the private helper selected by one direct standard Reflect call. */
	public function recordReflectRuntimeUseRequirement(decision:OcamlReflectRuntimeUseDecision):Void {
		runtimeRequirements.recordReflectRuntimeUse(decision);
	}

	/** Records the runtime helpers selected before one standard Haxe type check reaches syntax. */
	public function recordStdIsOfTypeRuntimeRequirement(decision:OcamlStdIsOfTypeDecision):Void {
		runtimeRequirements.recordStdIsOfType(decision);
	}

	/** Records runtime support selected before one integer unary expression reaches syntax. */
	public function recordIntUnaryRuntimeRequirement(decision:OcamlIntUnaryDecision):Void {
		runtimeRequirements.recordIntUnary(decision);
	}

	/** Records the helpers selected for one direct call or stored `String.fromCharCode` value. */
	public function recordStringFromCharCodeRuntimeRequirement(decision:OcamlStringFromCharCodeDecision):Void {
		runtimeRequirements.recordStringFromCharCode(decision);
	}

	/** Records runtime support selected by one direct structural Iterator call. */
	public function recordStructuralIteratorRuntimeRequirements(call:OcamlCallDecision):Void {
		if (call.structuralIteratorTarget == null)
			throw 'Structural Iterator call "${call.id}" has no sealed runtime target.';
		runtimeRequirements.recordStructuralIteratorCall(call.id, call.source, call.profileEligibility, call.structuralIteratorTarget);
	}

	/** Records the runtime helper owned by one sealed Boolean call argument. */
	public function recordCallRuntimeRequirements(call:OcamlCallDecision, plan:OcamlCallRuntimeUsePlan):Void {
		OcamlCallRuntimeRequirementRecorder.record(runtimeRequirements, call, plan);
	}
	#end

	/** Records runtime support selected by one sealed non-null Bytes producer. **/
	public function recordBytesProducerRuntimeRequirements(decision:OcamlBytesProducerDecision):Void {
		OcamlBytesRuntimeRequirementRecorder.recordProducer(runtimeRequirements, decision);
	}

	/** Records runtime support selected by one sealed Bytes mutation. **/
	public function recordBytesMutationRuntimeRequirements(decision:OcamlBytesMutationDecision):Void {
		OcamlBytesRuntimeRequirementRecorder.recordMutation(runtimeRequirements, decision);
	}

	/** Records runtime support selected by one sealed Bytes access. **/
	public function recordBytesAccessRuntimeRequirements(decision:OcamlBytesAccessDecision):Void {
		OcamlBytesRuntimeRequirementRecorder.recordAccess(runtimeRequirements, decision);
	}

	/** Records runtime support selected by one sealed read-only Bytes operation. **/
	public function recordBytesReadRuntimeRequirements(decision:OcamlBytesReadDecision):Void {
		OcamlBytesRuntimeRequirementRecorder.recordRead(runtimeRequirements, decision);
	}

	/**
		Records why one sealed direct array literal needs `HxArray`.

		The producer has already fixed allocation and one ordered store per source
		element. This method copies that decision into runtime packaging; it does not
		inspect the generated target expression.
	**/
	public function recordArrayLiteralRuntimeRequirements(decision:OcamlArrayLiteralProducerDecision):Void {
		runtimeRequirements.recordArrayLiteralProducer(decision);
	}

	/** Records the exact HxArray dependency owned by one sealed bracket read. */
	public function recordArrayReadRuntimeRequirements(decision:OcamlArrayReadDecision):Void {
		runtimeRequirements.recordArrayRead(decision);
	}

	/** Records a private `HxIterator` dependency when the sealed Array occurrence needs one. */
	public function recordArrayIteratorRuntimeRequirements(decision:OcamlArrayIteratorDecision):Void {
		runtimeRequirements.recordArrayIterator(decision);
	}

	/** Records the private Haxe equality helper selected for one typed occurrence. */
	public function recordDynamicEqualityRuntimeRequirement(decision:OcamlDynamicEqualityDecision):Void {
		runtimeRequirements.recordDynamicEquality(decision);
	}

	/** Records the private Haxe string helper selected for one typed occurrence. */
	public function recordDynamicStringRuntimeRequirement(decision:OcamlDynamicStringDecision):Void {
		runtimeRequirements.recordDynamicString(decision);
	}

	/** Records the exact HxArray dependency owned by one non-Array bracket read. */
	public function recordDynamicBracketReadRuntimeRequirements(decision:OcamlDynamicBracketReadDecision):Void {
		runtimeRequirements.recordDynamicBracketRead(decision);
	}

	/**
		Records why one sealed catch chain needs the private Haxe exception signal.

		The control planner has already selected both exception input channels and
		unmatched behavior. This request-local handoff makes runtime packaging follow
		that decision instead of scanning the generated pattern and rethrow call.
	**/
	public function recordCatchChainRuntimeRequirements(chain:OcamlCatchChainDecision):Void {
		runtimeRequirements.recordCatchChain(chain);
	}

	/**
		Records why one sealed early return needs its private HxRuntime signal.

		The control plan already fixed the owning function and optional result
		carrier. This handoff records that exact source decision before syntax creates
		the signal identifier; it does not infer a dependency from generated OCaml.
	**/
	public function recordReturnRuntimeRequirement(decision:OcamlControlDecision):Void {
		runtimeRequirements.recordReturnDecision(decision);
	}

	/**
		Records why one sealed Haxe throw needs the private HxType signal call.

		The control plan has already fixed the payload conversion and runtime tags.
		This handoff gives packaging that typed reason before syntax prints a name.
	**/
	public function recordThrowRuntimeRequirement(decision:OcamlControlDecision):Void {
		runtimeRequirements.recordThrowDecision(decision);
	}

	/** Records the exact private patterns and raises owned by one lexical loop. */
	public function recordLoopRuntimeRequirements(target:OcamlControlLoopTarget, decisions:Array<OcamlControlDecision>):Void {
		runtimeRequirements.recordLoopTarget(target, decisions);
	}

	/**
		Records why one sealed anonymous-object operation needs `HxAnon`.

		The operation was already selected from the final typed function. This
		method only transfers that decision into the request's runtime inventory;
		it does not infer a dependency from generated OCaml text.
	**/
	public function recordAnonymousStructureRuntimeRequirement(decision:OcamlAnonymousStructureOperationDecision):Void {
		OcamlAnonymousStructureRuntimeRequirementRecorder.record(runtimeRequirements, decision);
	}

	/**
		Records runtime support chosen for one overlapping structural field.

		The sealed decision distinguishes an ordinary stored field, a captured
		Iterator method, and a proven Map-pair projection before generated OCaml
		exists. Map-pair projections use OCaml Stdlib and add no repository runtime
		module. This method preserves the typed explanation instead of guessing from
		a field name or scanning generated text.
	**/
	public function recordStructuralFieldRuntimeRequirement(decision:OcamlStructuralFieldDecision):Void {
		OcamlStructuralFieldRuntimeRequirementRecorder.record(runtimeRequirements, decision);
	}

	/**
		Records why one sealed enum-to-`Dynamic` initializer needs `HxEnum`.

		The conversion already names the exact source expression and enum carrier.
		This method transfers that answer to the request's runtime inventory; it
		does not rediscover the dependency from generated OCaml.
	**/
	public function recordEnumDynamicLocalRuntimeRequirement(decision:OcamlLocalConversionDecision):Void {
		OcamlEnumRuntimeRequirementRecorder.record(runtimeRequirements, decision);
	}

	/**
		Records why one sealed enum array element needs `HxEnum`.

		The container plan already owns the exact array slot, enum identity, and
		boxing operation. Packaging receives that typed reason without inspecting
		the generated `HxArray.push` expression.
	**/
	public function recordEnumDynamicContainerRuntimeRequirement(decision:OcamlContainerElementDecision):Void {
		OcamlEnumRuntimeRequirementRecorder.recordContainerElement(runtimeRequirements, decision);
	}

	/**
		Records why one directly thrown enum constructor needs `HxEnum`.

		The control plan has already fixed the source occurrence, enum name,
		carrier, boxing operation, and runtime tags. This request-local handoff
		makes packaging follow that decision instead of scanning printed OCaml.
	**/
	public function recordEnumThrowRuntimeRequirement(decision:OcamlControlDecision):Void {
		OcamlEnumRuntimeRequirementRecorder.recordThrow(runtimeRequirements, decision);
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

	/** Returns the exact recorded requirements named by one sealed lowering plan. **/
	public function runtimeRequirementsByIds(ids:Array<String>):Array<OcamlRuntimeRequirement> {
		return runtimeRequirements.requirementsByIds(ids);
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
