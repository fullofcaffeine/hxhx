package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.StringMap;
import haxe.macro.Type;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/** The source declaration that supplies the initial value for one mutable static cell. */
enum abstract OcamlStaticStorageKind(String) from String to String {
	final Variable = "variable";
	final DynamicMethod = "dynamic-method";
}

/** Where the OCaml ref cell is declared relative to generated type fragments. */
enum abstract OcamlStaticStorageDeclarationSite(String) from String to String {
	/** The owning type declares and initializes the cell in one binding. */
	final OwnerBinding = "owner-binding";

	/** The combined OCaml module declares the cell before any type's value bindings. */
	final ModulePrelude = "module-prelude";

	/** One class chunk declares the cell after its type declaration and before its value bindings. */
	final TypePrelude = "type-prelude";
}

/** Facts selected before type emission for one mutable Haxe static field. */
typedef OcamlStaticStorageSelection = {
	final moduleId:String;
	final ownerTypeName:String;
	final fieldName:String;
	final targetValueName:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final fieldType:Type;
	final carrierType:OcamlTypeExpr;
	final kind:OcamlStaticStorageKind;
	final declarationSite:OcamlStaticStorageDeclarationSite;
	final declarationTypeName:Null<String>;
	final declarationTypeOrder:Int;
	final ownerTypeOrder:Int;
	final declarationOrder:Int;
	final initializationOrder:Int;
	final hasInitializer:Bool;
	final initializerDependencyKeys:Array<String>;
	final representationId:Null<String>;
}

/** One immutable, revision-owned static storage decision. */
typedef OcamlStaticStorageEntry = {
	> OcamlStaticStorageSelection,
	final id:String;
	final key:String;
	final initializationId:String;
	final programRevision:String;
	final revision:String;
}

/** Stable inspection facts for one static cell, excluding mutable host compiler objects. */
typedef OcamlStaticStorageReportEntry = {
	final id:String;
	final key:String;
	final initializationId:String;
	final programRevision:String;
	final revision:String;
	final moduleId:String;
	final ownerTypeName:String;
	final fieldName:String;
	final targetValueName:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final kind:OcamlStaticStorageKind;
	final declarationSite:OcamlStaticStorageDeclarationSite;
	final declarationTypeName:Null<String>;
	final declarationTypeOrder:Int;
	final ownerTypeOrder:Int;
	final declarationOrder:Int;
	final initializationOrder:Int;
	final hasInitializer:Bool;
	final initializerDependencyKeys:Array<String>;
	final representationId:Null<String>;
}

/**
	Plans mutable OCaml static storage before any class fragment is generated.

	Haxe permits several types in one source module, while OCaml requires a value
	name to exist before an earlier function can reference it. This request-local
	plan gives declaration ordering one owner: the compiler inventories every
	mutable static, seals the inventory, then class lowering and combined-module
	emission only query the recorded answer. No method-body traversal can add a
	late forward declaration.
**/
class OcamlStaticStoragePlan {
	public static inline final MODEL_REVISION = "ocaml-static-storage-v5";

	var currentProgramRevision:Null<String> = null;
	var sealed:Bool = false;
	final entriesByKey:StringMap<OcamlStaticStorageEntry> = new StringMap();
	final keyByTargetSymbol:StringMap<String> = new StringMap();
	final typeOrderByKey:StringMap<Int> = new StringMap();

	public function new() {}

	/** Starts one compilation request and discards all prior storage decisions. */
	public function beginProgram(programRevision:String):Void {
		if (programRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-static-storage:missing-program-revision]: the target-selected program revision is empty";
		currentProgramRevision = programRevision;
		sealed = false;
		entriesByKey.clear();
		keyByTargetSymbol.clear();
		typeOrderByKey.clear();
	}

	/** Returns the stable source owner key used by plans, syntax, and diagnostics. */
	public static function key(moduleId:String, ownerTypeName:String, fieldName:String):String {
		return moduleId + "::" + ownerTypeName + "::" + fieldName;
	}

	/** Records the order in which one type's value bindings appear in its OCaml module. */
	public function registerTypeOrder(moduleId:String, ownerTypeName:String, order:Int):Void {
		requireProgramRevision();
		if (sealed)
			throw "reflaxe.ocaml [ocaml-static-storage:sealed]: type order cannot change after static storage planning is sealed";
		if (moduleId.length == 0 || ownerTypeName.length == 0 || order < 0)
			throw "reflaxe.ocaml [ocaml-static-storage:invalid-type-order]: module, type, and non-negative order are required";
		final typeKey = moduleId + "::" + ownerTypeName;
		final existing = typeOrderByKey.get(typeKey);
		if (existing != null && existing != order)
			throw 'reflaxe.ocaml [ocaml-static-storage:conflicting-type-order]: "$typeKey" was assigned both $existing and $order';
		typeOrderByKey.set(typeKey, order);
	}

	/** Adds or reuses one complete decision before the plan is sealed. */
	public function register(selection:OcamlStaticStorageSelection):OcamlStaticStorageEntry {
		final programRevision = requireProgramRevision();
		if (sealed)
			throw "reflaxe.ocaml [ocaml-static-storage:sealed]: mutable static storage cannot change after type emission planning is sealed";
		validateSelection(selection);
		final entryKey = key(selection.moduleId, selection.ownerTypeName, selection.fieldName);
		final plannedOwnerTypeOrder = typeOrderByKey.get(selection.moduleId + "::" + selection.ownerTypeName);
		if (plannedOwnerTypeOrder == null)
			throw 'reflaxe.ocaml [ocaml-static-storage:missing-type-order]: "${selection.moduleId}::${selection.ownerTypeName}" must be ordered before its mutable fields are registered';
		if (plannedOwnerTypeOrder != selection.ownerTypeOrder)
			throw 'reflaxe.ocaml [ocaml-static-storage:type-order-mismatch]: "$entryKey" says its owner order is ${selection.ownerTypeOrder}, but the module plan selected $plannedOwnerTypeOrder';
		if (selection.declarationSite == OcamlStaticStorageDeclarationSite.TypePrelude) {
			final plannedDeclarationTypeOrder = typeOrderByKey.get(selection.moduleId + "::" + selection.declarationTypeName);
			if (plannedDeclarationTypeOrder == null || plannedDeclarationTypeOrder != selection.declarationTypeOrder)
				throw 'reflaxe.ocaml [ocaml-static-storage:type-prelude-order-mismatch]: "$entryKey" names declaration type ${selection.declarationTypeName} at ${selection.declarationTypeOrder}, but the module plan selected $plannedDeclarationTypeOrder';
		}
		final targetSymbol = selection.moduleId + "::" + selection.targetValueName;
		final existingTargetOwner = keyByTargetSymbol.get(targetSymbol);
		if (existingTargetOwner != null && existingTargetOwner != entryKey) {
			throw 'reflaxe.ocaml [ocaml-static-storage:target-name-collision]: "$targetSymbol" is selected by both "$existingTargetOwner" and "$entryKey"';
		}
		final initializerDependencyKeys = normalizeDependencyKeys(selection.initializerDependencyKeys);
		final revision = "sha256:" + Sha256.encode(selectionFingerprint(selection, initializerDependencyKeys));
		final candidate:OcamlStaticStorageEntry = {
			id: "static-storage:" + entryKey,
			key: entryKey,
			initializationId: "static-initialization:" + entryKey,
			programRevision: programRevision,
			revision: revision,
			moduleId: selection.moduleId,
			ownerTypeName: selection.ownerTypeName,
			fieldName: selection.fieldName,
			targetValueName: selection.targetValueName,
			semanticTypeId: selection.semanticTypeId,
			carrierTypeId: selection.carrierTypeId,
			fieldType: selection.fieldType,
			carrierType: cloneCarrierType(selection.carrierType),
			kind: selection.kind,
			declarationSite: selection.declarationSite,
			declarationTypeName: selection.declarationTypeName,
			declarationTypeOrder: selection.declarationTypeOrder,
			ownerTypeOrder: selection.ownerTypeOrder,
			declarationOrder: selection.declarationOrder,
			initializationOrder: selection.initializationOrder,
			hasInitializer: selection.hasInitializer,
			initializerDependencyKeys: initializerDependencyKeys,
			representationId: selection.representationId
		};
		final existing = entriesByKey.get(entryKey);
		if (existing != null) {
			if (existing.revision != candidate.revision) {
				throw 'reflaxe.ocaml [ocaml-static-storage:conflicting-decision]: "$entryKey" was planned twice with different storage facts';
			}
			return copyEntry(existing);
		}
		entriesByKey.set(entryKey, candidate);
		keyByTargetSymbol.set(targetSymbol, entryKey);
		return copyEntry(candidate);
	}

	/** Seals and validates the complete pre-emission inventory. */
	public function seal():Void {
		requireProgramRevision();
		if (sealed)
			return;
		final declarationOwners:StringMap<String> = new StringMap();
		final initializationOwners:StringMap<String> = new StringMap();
		for (entry in entriesByKey) {
			final declarationKey = entry.moduleId + "::" + entry.declarationOrder;
			final previousDeclaration = declarationOwners.get(declarationKey);
			if (previousDeclaration != null && previousDeclaration != entry.key)
				throw 'reflaxe.ocaml [ocaml-static-storage:duplicate-declaration-order]: "$previousDeclaration" and "${entry.key}" both use ${entry.declarationOrder} in ${entry.moduleId}';
			declarationOwners.set(declarationKey, entry.key);

			final initializationKey = entry.moduleId + "::" + entry.initializationOrder;
			final previousInitialization = initializationOwners.get(initializationKey);
			if (previousInitialization != null && previousInitialization != entry.key)
				throw 'reflaxe.ocaml [ocaml-static-storage:duplicate-initialization-order]: "$previousInitialization" and "${entry.key}" both use ${entry.initializationOrder} in ${entry.moduleId}';
			initializationOwners.set(initializationKey, entry.key);
		}
		validateInitializerDependencyGraph();
		sealed = true;
	}

	/** Returns the exact decision for a mutable static or fails before OCaml emission. */
	public function require(moduleId:String, ownerTypeName:String, fieldName:String):OcamlStaticStorageEntry {
		requireSealed();
		final entryKey = key(moduleId, ownerTypeName, fieldName);
		final entry = entriesByKey.get(entryKey);
		if (entry == null)
			throw 'reflaxe.ocaml [ocaml-static-storage:missing-entry]: no pre-emission storage decision exists for "$entryKey"';
		return copyEntry(entry);
	}

	/** Reports whether a same-module reference can use a cell declared in the module prelude. */
	public function hasModulePrelude(moduleId:String, ownerTypeName:String, fieldName:String):Bool {
		requireSealed();
		final entry = entriesByKey.get(key(moduleId, ownerTypeName, fieldName));
		return entry != null && entry.declarationSite == OcamlStaticStorageDeclarationSite.ModulePrelude;
	}

	/**
		Returns whether one cell is declared before a referencing type's value bindings.

		Cross-module references are resolved through the OCaml module dependency. Inside
		one module, either the cell lives in the module prelude or its owner type must
		appear earlier than the referencing type.
	**/
	public function isVisibleFrom(moduleId:String, ownerTypeName:String, fieldName:String, currentModuleId:String, currentTypeName:String):Bool {
		final entry = require(moduleId, ownerTypeName, fieldName);
		if (moduleId != currentModuleId
			|| ownerTypeName == currentTypeName
			|| entry.declarationSite == OcamlStaticStorageDeclarationSite.ModulePrelude)
			return true;
		final currentTypeOrder = typeOrderByKey.get(currentModuleId + "::" + currentTypeName);
		if (currentTypeOrder == null)
			throw 'reflaxe.ocaml [ocaml-static-storage:missing-type-order]: no value-binding order exists for "$currentModuleId::$currentTypeName"';
		return switch (entry.declarationSite) {
			case OcamlStaticStorageDeclarationSite.TypePrelude: entry.declarationTypeOrder <= currentTypeOrder;
			case OcamlStaticStorageDeclarationSite.OwnerBinding: entry.ownerTypeOrder < currentTypeOrder;
			case OcamlStaticStorageDeclarationSite.ModulePrelude: true;
		}
	}

	/** Returns one module's decisions in deterministic declaration order. */
	public function entriesForModule(moduleId:String):Array<OcamlStaticStorageEntry> {
		requireSealed();
		final out = [for (entry in entriesByKey) if (entry.moduleId == moduleId) copyEntry(entry)];
		out.sort((left, right) -> {
			if (left.declarationOrder != right.declarationOrder)
				return left.declarationOrder - right.declarationOrder;
			return Reflect.compare(left.key, right.key);
		});
		return out;
	}

	/** Returns a deterministic digest for reports, caches, and repeated-build tests. */
	public function revision():String {
		requireSealed();
		final entries = [for (entry in entriesByKey) entry];
		entries.sort((left, right) -> Reflect.compare(left.key, right.key));
		final typeOrders = [
			for (typeKey in typeOrderByKey.keys())
				typeKey + "|" + typeOrderByKey.get(typeKey)
		];
		typeOrders.sort(Reflect.compare);
		return "sha256:" + Sha256.encode(typeOrders.concat(entries.map(entry -> entry.key + "|" + entry.revision)).join("\n"));
	}

	/** Returns deterministic, JSON-safe facts for the target inspection report. */
	public function reportEntries():Array<OcamlStaticStorageReportEntry> {
		requireSealed();
		final out = [
			for (entry in entriesByKey)
				{
					id: entry.id,
					key: entry.key,
					initializationId: entry.initializationId,
					programRevision: entry.programRevision,
					revision: entry.revision,
					moduleId: entry.moduleId,
					ownerTypeName: entry.ownerTypeName,
					fieldName: entry.fieldName,
					targetValueName: entry.targetValueName,
					semanticTypeId: entry.semanticTypeId,
					carrierTypeId: entry.carrierTypeId,
					kind: entry.kind,
					declarationSite: entry.declarationSite,
					declarationTypeName: entry.declarationTypeName,
					declarationTypeOrder: entry.declarationTypeOrder,
					ownerTypeOrder: entry.ownerTypeOrder,
					declarationOrder: entry.declarationOrder,
					initializationOrder: entry.initializationOrder,
					hasInitializer: entry.hasInitializer,
					initializerDependencyKeys: entry.initializerDependencyKeys.copy(),
					representationId: entry.representationId
				}
		];
		out.sort((left, right) -> Reflect.compare(left.key, right.key));
		return out;
	}

	function requireProgramRevision():String {
		if (currentProgramRevision == null)
			throw "reflaxe.ocaml [ocaml-static-storage:program-not-started]: beginProgram must run before planning static storage";
		return currentProgramRevision;
	}

	function requireSealed():Void {
		requireProgramRevision();
		if (!sealed)
			throw "reflaxe.ocaml [ocaml-static-storage:not-sealed]: the complete mutable static inventory must be sealed before it is consumed";
	}

	static function validateSelection(selection:OcamlStaticStorageSelection):Void {
		if (selection.moduleId.length == 0
			|| selection.ownerTypeName.length == 0
			|| selection.fieldName.length == 0
			|| selection.targetValueName.length == 0
			|| selection.semanticTypeId.length == 0
			|| selection.carrierTypeId.length == 0) {
			throw "reflaxe.ocaml [ocaml-static-storage:invalid-entry]: owner, target symbol, semantic type, and carrier type must be non-empty";
		}
		if (selection.declarationOrder < 0 || selection.initializationOrder < 0)
			throw "reflaxe.ocaml [ocaml-static-storage:invalid-order]: declaration and initialization order must be non-negative";
		if (selection.ownerTypeOrder < 0)
			throw "reflaxe.ocaml [ocaml-static-storage:invalid-type-order]: owner type order must be non-negative";
		if (selection.declarationSite == OcamlStaticStorageDeclarationSite.ModulePrelude && selection.representationId == null) {
			throw "reflaxe.ocaml [ocaml-static-storage:missing-representation]: a module-prelude cell needs the program representation decision that makes its early carrier safe";
		}
		if (selection.kind == OcamlStaticStorageKind.Variable
			&& ((selection.semanticTypeId == "Int" && selection.carrierTypeId == "int")
				|| (selection.semanticTypeId == "Bool" && selection.carrierTypeId == "bool")
				|| (selection.semanticTypeId == "Null<Int>" && selection.carrierTypeId == "Obj.t")
				|| (selection.semanticTypeId == "Null<Bool>" && selection.carrierTypeId == "Obj.t"))
			&& selection.representationId == null) {
			throw "reflaxe.ocaml [ocaml-static-storage:missing-exact-primitive-representation]: every admitted exact primitive or nullable-primitive static cell needs its program representation decision, regardless of declaration site";
		}
		if (selection.declarationSite == OcamlStaticStorageDeclarationSite.TypePrelude) {
			if (selection.declarationTypeName == null || selection.declarationTypeName.length == 0 || selection.declarationTypeOrder < 0)
				throw "reflaxe.ocaml [ocaml-static-storage:invalid-type-prelude]: a type-prelude cell needs the type name and order after which it is declared";
		} else if (selection.declarationTypeName != null || selection.declarationTypeOrder != -1) {
			throw "reflaxe.ocaml [ocaml-static-storage:invalid-declaration-site]: only a type-prelude cell may name a declaration type";
		}
	}

	static function selectionFingerprint(selection:OcamlStaticStorageSelection, initializerDependencyKeys:Array<String>):String {
		return [
			MODEL_REVISION,
			selection.moduleId,
			selection.ownerTypeName,
			selection.fieldName,
			selection.targetValueName,
			selection.semanticTypeId,
			selection.carrierTypeId,
			(selection.kind : String),
			(selection.declarationSite : String),
			selection.declarationTypeName == null ? "" : selection.declarationTypeName,
			Std.string(selection.declarationTypeOrder),
			Std.string(selection.ownerTypeOrder),
			Std.string(selection.declarationOrder),
			Std.string(selection.initializationOrder),
			Std.string(selection.hasInitializer),
			initializerDependencyKeys.join(","),
			selection.representationId == null ? "" : selection.representationId
		].join("|");
	}

	static function copyEntry(entry:OcamlStaticStorageEntry):OcamlStaticStorageEntry {
		return {
			id: entry.id,
			key: entry.key,
			initializationId: entry.initializationId,
			programRevision: entry.programRevision,
			revision: entry.revision,
			moduleId: entry.moduleId,
			ownerTypeName: entry.ownerTypeName,
			fieldName: entry.fieldName,
			targetValueName: entry.targetValueName,
			semanticTypeId: entry.semanticTypeId,
			carrierTypeId: entry.carrierTypeId,
			fieldType: entry.fieldType,
			carrierType: cloneCarrierType(entry.carrierType),
			kind: entry.kind,
			declarationSite: entry.declarationSite,
			declarationTypeName: entry.declarationTypeName,
			declarationTypeOrder: entry.declarationTypeOrder,
			ownerTypeOrder: entry.ownerTypeOrder,
			declarationOrder: entry.declarationOrder,
			initializationOrder: entry.initializationOrder,
			hasInitializer: entry.hasInitializer,
			initializerDependencyKeys: entry.initializerDependencyKeys.copy(),
			representationId: entry.representationId
		};
	}

	static function normalizeDependencyKeys(keys:Array<String>):Array<String> {
		final unique:StringMap<Bool> = new StringMap();
		for (key in keys) {
			if (key.length == 0)
				throw "reflaxe.ocaml [ocaml-static-storage:invalid-initializer-dependency]: initializer dependency keys must be non-empty";
			unique.set(key, true);
		}
		final normalized = [for (key in unique.keys()) key];
		normalized.sort(Reflect.compare);
		return normalized;
	}

	/** Rejects cycles whose runtime result differs between Haxe target platforms. */
	function validateInitializerDependencyGraph():Void {
		final states:StringMap<Int> = new StringMap();
		final stack:Array<String> = [];
		var visit:String->Void = null;
		visit = entryKey -> {
			states.set(entryKey, 1);
			stack.push(entryKey);
			final entry = entriesByKey.get(entryKey);
			if (entry == null)
				throw 'reflaxe.ocaml [ocaml-static-storage:missing-entry]: dependency traversal lost "$entryKey"';
			final dependencies = entry.initializerDependencyKeys.filter(entriesByKey.exists);
			dependencies.sort(Reflect.compare);
			for (dependencyKey in dependencies) {
				final state = states.get(dependencyKey);
				if (state == 1) {
					final cycleStart = stack.indexOf(dependencyKey);
					final cycle = stack.slice(cycleStart).concat([dependencyKey]);
					throw 'reflaxe.ocaml [ocaml-static-storage:initializer-cycle]: mutable static initializers form a dependency cycle: ${cycle.join(" -> ")}';
				}
				if (state == null)
					visit(dependencyKey);
			}
			stack.pop();
			states.set(entryKey, 2);
		};

		final keys = [for (entryKey in entriesByKey.keys()) entryKey];
		keys.sort(Reflect.compare);
		for (entryKey in keys) {
			if (!states.exists(entryKey))
				visit(entryKey);
		}
	}

	static function cloneCarrierType(type:OcamlTypeExpr):OcamlTypeExpr {
		return switch (type) {
			case TIdent(name): TIdent(name);
			case TApp(name, parameters): TApp(name, parameters.map(cloneCarrierType));
			case TArrow(from, to): TArrow(cloneCarrierType(from), cloneCarrierType(to));
			case TTuple(items): TTuple(items.map(cloneCarrierType));
			case TVar(name): TVar(name);
			case TRecord(fields): TRecord(fields.map(field -> {
					name: field.name,
					typ: cloneCarrierType(field.typ),
					isMutable: field.isMutable
				}));
		};
	}
}
#end
