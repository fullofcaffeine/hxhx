package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureContract;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureField;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureLoadConversion;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationKind;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureStoreConversion;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/** The sealed operations needed to materialize one exact object literal. */
typedef OcamlAnonymousStructureLiteralPlan = {
	final structure:OcamlAnonymousStructureDecision;
	final create:OcamlAnonymousStructureOperationDecision;
	final initializers:Array<OcamlAnonymousStructureOperationDecision>;
}

private typedef AnonymousLiteralIndex = {
	final expression:TypedExpr;
	final structureId:String;
	final createId:String;
	final initializerIds:Array<String>;
}

private typedef AnonymousOperationIndex = {
	final expression:TypedExpr;
	final decisionId:String;
}

/**
	Immutable inventory of the bounded direct anonymous-object family.

	The plan keeps request-local typed-node indexes only so syntax can find the
	exact occurrence after final preprocessing. The decisions themselves use
	stable function paths, normalized shapes, and revision values; no process
	local macro object number becomes semantic evidence.
**/
class OcamlAnonymousStructurePlan {
	final structuresById:Map<String, OcamlAnonymousStructureDecision> = [];
	final structuresBySemanticType:Map<String, OcamlAnonymousStructureDecision> = [];
	final operationsById:Map<String, OcamlAnonymousStructureOperationDecision> = [];
	final literalByExpression:ObjectMap<TypedExpr, AnonymousLiteralIndex> = new ObjectMap();
	final operationIdByExpression:ObjectMap<TypedExpr, String> = new ObjectMap();
	final orderedStructures:Array<OcamlAnonymousStructureDecision>;
	final orderedOperations:Array<OcamlAnonymousStructureOperationDecision>;

	public final revision:String;

	public function new(structures:Array<OcamlAnonymousStructureDecision>, operations:Array<OcamlAnonymousStructureOperationDecision>,
			?literals:Array<AnonymousLiteralIndex>, ?operationOccurrences:Array<AnonymousOperationIndex>) {
		final normalizedStructures = structures.map(copyStructure);
		normalizedStructures.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (structure in normalizedStructures) {
			OcamlAnonymousStructureContract.requireStructure(structure);
			if (structuresById.exists(structure.id) || structuresBySemanticType.exists(structure.semanticTypeId))
				throw 'reflaxe.ocaml [ocaml-anonymous:duplicate-structure]: anonymous structure "${structure.id}" appears more than once';
			structuresById.set(structure.id, copyStructure(structure));
			structuresBySemanticType.set(structure.semanticTypeId, copyStructure(structure));
		}
		orderedStructures = normalizedStructures;

		final normalizedOperations = operations.map(operation -> OcamlAnonymousStructureContract.copyOperation(operation, operation.id));
		normalizedOperations.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (operation in normalizedOperations) {
			final structure = structuresById.get(operation.structureId);
			if (structure == null)
				throw 'reflaxe.ocaml [ocaml-anonymous:missing-structure]: operation "${operation.id}" refers to missing structure "${operation.structureId}"';
			OcamlAnonymousStructureContract.requireOperation(operation, structure);
			if (operationsById.exists(operation.id))
				throw 'reflaxe.ocaml [ocaml-anonymous:duplicate-operation]: anonymous operation "${operation.id}" appears more than once';
			operationsById.set(operation.id, OcamlAnonymousStructureContract.copyOperation(operation, operation.id));
		}
		orderedOperations = normalizedOperations;

		final indexedOperations:Map<String, Bool> = [];
		for (literal in literals ?? []) {
			if (literalByExpression.exists(literal.expression))
				throw "reflaxe.ocaml [ocaml-anonymous:duplicate-literal]: one typed object literal has more than one anonymous plan";
			final structure = structuresById.get(literal.structureId);
			final create = operationsById.get(literal.createId);
			if (structure == null || create == null || create.kind != OcamlAnonymousStructureOperationKind.Create)
				throw "reflaxe.ocaml [ocaml-anonymous:invalid-literal]: object literal index does not name its structure and create operation";
			if (literal.initializerIds.length != structure.fields.length)
				throw 'reflaxe.ocaml [ocaml-anonymous:invalid-literal]: object literal for "${structure.id}" has ${literal.initializerIds.length} initializers, expected ${structure.fields.length}';
			for (index in 0...literal.initializerIds.length) {
				final initializer = operationsById.get(literal.initializerIds[index]);
				if (initializer == null
					|| initializer.kind != OcamlAnonymousStructureOperationKind.InitializeField
					|| initializer.structureId != structure.id
					|| initializer.fieldSourceOrder != index) {
					throw 'reflaxe.ocaml [ocaml-anonymous:reordered-initializer]: object literal for "${structure.id}" has an invalid initializer at source order $index';
				}
				if (indexedOperations.exists(initializer.id))
					throw 'reflaxe.ocaml [ocaml-anonymous:duplicate-operation-occurrence]: initializer "${initializer.id}" is indexed more than once';
				indexedOperations.set(initializer.id, true);
			}
			if (indexedOperations.exists(create.id))
				throw 'reflaxe.ocaml [ocaml-anonymous:duplicate-operation-occurrence]: create "${create.id}" is indexed more than once';
			indexedOperations.set(create.id, true);
			literalByExpression.set(literal.expression, {
				expression: literal.expression,
				structureId: literal.structureId,
				createId: literal.createId,
				initializerIds: literal.initializerIds.copy()
			});
		}
		for (occurrence in operationOccurrences ?? []) {
			final operation = operationsById.get(occurrence.decisionId);
			if (operation == null
				|| (operation.kind != OcamlAnonymousStructureOperationKind.ReadField
					&& operation.kind != OcamlAnonymousStructureOperationKind.WriteField)) {
				throw 'reflaxe.ocaml [ocaml-anonymous:missing-operation-occurrence]: typed occurrence refers to invalid operation "${occurrence.decisionId}"';
			}
			if (operationIdByExpression.exists(occurrence.expression))
				throw "reflaxe.ocaml [ocaml-anonymous:duplicate-operation-occurrence]: one typed expression has more than one anonymous operation";
			if (indexedOperations.exists(operation.id))
				throw 'reflaxe.ocaml [ocaml-anonymous:duplicate-operation-occurrence]: operation "${operation.id}" is indexed more than once';
			operationIdByExpression.set(occurrence.expression, operation.id);
			indexedOperations.set(operation.id, true);
		}
		if (literals != null || operationOccurrences != null) {
			for (operation in normalizedOperations)
				if (!indexedOperations.exists(operation.id))
					throw 'reflaxe.ocaml [ocaml-anonymous:missing-operation-occurrence]: operation "${operation.id}" has no exact typed occurrence';
		}
		revision = "sha256:" + Sha256.encode(orderedStructures.map(structureFingerprint).concat(orderedOperations.map(operationFingerprint)).join("\n"));
	}

	/** Returns and revalidates the complete plan for one typed object literal. */
	public function requireLiteral(expression:TypedExpr, representations:OcamlRepresentationRegistry):OcamlAnonymousStructureLiteralPlan {
		final literal = literalByExpression.get(expression);
		if (literal == null)
			throw "reflaxe.ocaml [ocaml-anonymous:missing-literal]: admitted object literal reached syntax without its sealed plan";
		final structure = requireStructure(literal.structureId, representations);
		final create = requireOperation(literal.createId, structure, representations);
		final initializers = [
			for (id in literal.initializerIds)
				requireOperation(id, structure, representations)
		];
		final fields = literalFields(expression);
		if (fields == null || fields.length != initializers.length)
			throw 'reflaxe.ocaml [ocaml-anonymous:stale-literal]: object literal no longer has the ${initializers.length} planned fields';
		for (index in 0...fields.length) {
			if (initializers[index].fieldName != fields[index].name || initializers[index].fieldSourceOrder != index)
				throw 'reflaxe.ocaml [ocaml-anonymous:reordered-initializer]: object literal field "${fields[index].name}" does not match planned source order $index';
		}
		return {structure: structure, create: create, initializers: initializers};
	}

	/**
		Returns a read or write plan only when this function admitted the receiver
		shape through a direct literal.

		An anonymous parameter, structural class conversion, or another unowned
		source remains on the legacy path. A typed node that should be in this
		plan but has no exact index fails instead of being reclassified by syntax.
	**/
	public function operationFor(expression:TypedExpr, representations:OcamlRepresentationRegistry):Null<OcamlAnonymousStructureOperationDecision> {
		final id = operationIdByExpression.get(expression);
		if (id == null)
			return null;
		final expected = expectedOperation(expression);
		if (expected == null)
			throw 'reflaxe.ocaml [ocaml-anonymous:stale-operation]: planned anonymous operation "$id" no longer refers to a direct field read or write';
		final structure = structuresBySemanticType.get(expected.semanticTypeId);
		if (structure == null)
			throw 'reflaxe.ocaml [ocaml-anonymous:missing-structure]: planned anonymous operation "$id" no longer has structure "${expected.semanticTypeId}"';
		final operation = requireOperation(id, requireStructure(structure.id, representations), representations);
		if (operation.kind != expected.kind || operation.fieldName != expected.fieldName)
			throw 'reflaxe.ocaml [ocaml-anonymous:stale-operation]: operation "${operation.id}" no longer matches the typed ${expected.kind} on "${expected.fieldName}"';
		return operation;
	}

	/** Revalidates every structure and field carrier against this request. */
	public function requireRepresentations(representations:OcamlRepresentationRegistry):Void {
		for (structure in orderedStructures)
			requireStructure(structure.id, representations);
	}

	/** Revalidates the program, body, and target pipeline owning every operation. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (operation in orderedOperations) {
			if (operation.functionId != binding.functionId
				|| operation.programRevision != binding.programRevision
				|| operation.bodyRevision != binding.bodyRevision
				|| operation.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-anonymous:stale-operation]: operation "${operation.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
		}
		for (structure in orderedStructures)
			if (structure.programRevision != binding.programRevision)
				throw 'reflaxe.ocaml [ocaml-anonymous:stale-structure]: structure "${structure.id}" does not belong to ${binding.programRevision}';
	}

	/** Returns stable copies for reports and runtime-requirement recording. */
	public function structures():Array<OcamlAnonymousStructureDecision> {
		return orderedStructures.map(copyStructure);
	}

	/** Returns stable copies in deterministic operation-identity order. */
	public function operations():Array<OcamlAnonymousStructureOperationDecision> {
		return orderedOperations.map(operation -> OcamlAnonymousStructureContract.copyOperation(operation, operation.id));
	}

	/**
		Reports whether a typed object literal belongs to the bounded family.

		This check is used only as a fail-closed syntax guard. The planner remains
		the authority that builds the structure, field carriers, and operations.
	**/
	public static function isAdmittedLiteralCandidate(expression:TypedExpr):Bool {
		final fields = literalFields(expression);
		if (fields == null || fields.length == 0 || excludedDedicatedShape(expression.t))
			return false;
		final shapeFields = anonymousFields(expression.t);
		if (shapeFields == null || shapeFields.length != fields.length)
			return false;
		final names:Map<String, Bool> = [];
		for (field in shapeFields) {
			if (names.exists(field.name) || !isAdmittedField(field))
				return false;
			names.set(field.name, true);
		}
		for (field in fields)
			if (!names.exists(field.name))
				return false;
		return true;
	}

	function requireStructure(id:String, representations:OcamlRepresentationRegistry):OcamlAnonymousStructureDecision {
		final structure = structuresById.get(id);
		if (structure == null)
			throw 'reflaxe.ocaml [ocaml-anonymous:missing-structure]: plan refers to missing structure "$id"';
		OcamlAnonymousStructureContract.requireStructure(structure);
		final representation = representations.require(structure.representationId, structure.programRevision);
		if (representation.revision != structure.representationRevision
			|| representation.semanticTypeId != structure.semanticTypeId
			|| representation.carrierTypeId != structure.carrierTypeId
			|| representation.domain != OcamlRepresentationDomain.InternalValue) {
			throw 'reflaxe.ocaml [ocaml-anonymous:structure-representation-mismatch]: structure "${structure.id}" no longer matches ${structure.representationId}@${structure.representationRevision}';
		}
		for (field in structure.fields)
			requireFieldRepresentation(field, structure.programRevision, representations);
		return copyStructure(structure);
	}

	function requireOperation(id:String, structure:OcamlAnonymousStructureDecision,
			representations:OcamlRepresentationRegistry):OcamlAnonymousStructureOperationDecision {
		final operation = operationsById.get(id);
		if (operation == null)
			throw 'reflaxe.ocaml [ocaml-anonymous:missing-operation]: plan refers to missing operation "$id"';
		OcamlAnonymousStructureContract.requireOperation(operation, structure);
		if (operation.fieldName != null) {
			final field = structure.fields[operation.fieldCanonicalOrder];
			requireFieldRepresentation(field, structure.programRevision, representations);
		}
		return OcamlAnonymousStructureContract.copyOperation(operation, operation.id);
	}

	static function requireFieldRepresentation(field:OcamlAnonymousStructureField, programRevision:String, representations:OcamlRepresentationRegistry):Void {
		final representation = representations.require(field.representationId, programRevision);
		if (representation.revision != field.representationRevision
			|| representation.semanticTypeId != field.semanticTypeId
			|| representation.carrierTypeId != field.carrierTypeId
			|| representation.domain != OcamlRepresentationDomain.InternalValue) {
			throw 'reflaxe.ocaml [ocaml-anonymous:field-representation-mismatch]: field "${field.name}" no longer matches ${field.representationId}@${field.representationRevision}';
		}
	}

	static function literalFields(expression:TypedExpr):Null<Array<{name:String, expr:TypedExpr}>> {
		return switch (expression.expr) {
			case TObjectDecl(fields): fields.map(field -> ({name: field.name, expr: field.expr}));
			case _: null;
		}
	}

	public static function anonymousFields(type:Type):Null<Array<ClassField>> {
		return switch (TypeTools.follow(type)) {
			case TAnonymous(anonymousRef): anonymousRef.get().fields;
			case _: null;
		}
	}

	static function isAdmittedField(field:ClassField):Bool {
		if (field.meta.has(":optional"))
			return false;
		return switch (field.kind) {
			case FVar(_, _):
				OcamlRepresentationRegistry.isExactInt(field.type)
				|| OcamlRepresentationRegistry.isExactBool(field.type)
				|| OcamlRepresentationRegistry.isExactString(field.type)
				|| OcamlRepresentationRegistry.isExactNullString(field.type);
			case FMethod(_):
				false;
		}
	}

	static function excludedDedicatedShape(type:Type):Bool {
		final fields = anonymousFields(type);
		if (fields == null)
			return true;
		final names:Map<String, Bool> = [];
		for (field in fields)
			names.set(field.name, true);
		if (names.exists("hasNext") && names.exists("next"))
			return true;
		if (names.exists("key") && names.exists("value"))
			return true;
		final fileStat = [
			"gid", "uid", "atime", "mtime", "ctime", "size", "dev", "ino", "nlink", "rdev", "mode"
		];
		for (name in fileStat)
			if (!names.exists(name))
				return false;
		return true;
	}

	static function copyStructure(structure:OcamlAnonymousStructureDecision):OcamlAnonymousStructureDecision {
		return {
			id: structure.id,
			semanticTypeId: structure.semanticTypeId,
			carrierTypeId: structure.carrierTypeId,
			fields: structure.fields.map(field -> ({
				name: field.name,
				canonicalOrder: field.canonicalOrder,
				semanticTypeId: field.semanticTypeId,
				carrierTypeId: field.carrierTypeId,
				representationId: field.representationId,
				representationRevision: field.representationRevision,
				storeConversion: field.storeConversion,
				loadConversion: field.loadConversion
			})),
			representationId: structure.representationId,
			representationRevision: structure.representationRevision,
			representationDomain: structure.representationDomain,
			nullPolicy: structure.nullPolicy,
			identityPolicy: structure.identityPolicy,
			aliasingPolicy: structure.aliasingPolicy,
			mutationPolicy: structure.mutationPolicy,
			proofId: structure.proofId,
			proofClaim: structure.proofClaim,
			programRevision: structure.programRevision,
			revision: structure.revision
		};
	}

	static function structureFingerprint(structure:OcamlAnonymousStructureDecision):String {
		return haxe.Json.stringify(structure);
	}

	static function operationFingerprint(operation:OcamlAnonymousStructureOperationDecision):String {
		return haxe.Json.stringify(operation);
	}

	static function expectedOperation(expression:TypedExpr):Null<{
		final kind:OcamlAnonymousStructureOperationKind;
		final semanticTypeId:String;
		final fieldName:String;
	}> {
		return switch (expression.expr) {
			case TField(receiver, FAnon(fieldRef)):
				final semanticTypeId = semanticTypeIdForType(receiver.t);
				semanticTypeId == null ? null : {
					kind: OcamlAnonymousStructureOperationKind.ReadField,
					semanticTypeId: semanticTypeId,
					fieldName: fieldRef.get().name
				};
			case TBinop(OpAssign, {expr: TField(receiver, FAnon(fieldRef))}, _):
				final semanticTypeId = semanticTypeIdForType(receiver.t);
				semanticTypeId == null ? null : {
					kind: OcamlAnonymousStructureOperationKind.WriteField,
					semanticTypeId: semanticTypeId,
					fieldName: fieldRef.get().name
				};
			case _:
				null;
		}
	}

	public static function semanticTypeIdForType(type:Type):Null<String> {
		if (excludedDedicatedShape(type))
			return null;
		final rawFields = anonymousFields(type);
		if (rawFields == null || rawFields.length == 0)
			return null;
		final fields = rawFields.copy();
		fields.sort((left, right) -> Reflect.compare(left.name, right.name));
		final parts = new Array<String>();
		for (field in fields) {
			final semantic = semanticFieldType(field.type);
			if (semantic == null || !isAdmittedField(field))
				return null;
			parts.push(field.name + ":" + semantic);
		}
		return "anonymous{" + parts.join(",") + "}";
	}

	static function semanticFieldType(type:Type):Null<String> {
		if (OcamlRepresentationRegistry.isExactInt(type))
			return "Int";
		if (OcamlRepresentationRegistry.isExactBool(type))
			return "Bool";
		if (OcamlRepresentationRegistry.isExactString(type) || OcamlRepresentationRegistry.isExactNullString(type))
			return "String";
		return null;
	}
}

/** Builds anonymous structure and operation decisions from one final typed root. */
class OcamlAnonymousStructurePlanner {
	final binding:OcamlFunctionPlanBinding;
	final representations:OcamlRepresentationRegistry;
	final structuresBySemanticType:Map<String, OcamlAnonymousStructureDecision> = [];

	public function new(binding:OcamlFunctionPlanBinding, representations:OcamlRepresentationRegistry) {
		this.binding = binding;
		this.representations = representations;
	}

	public function plan(root:TypedExpr):OcamlAnonymousStructurePlan {
		final literalStructures:ObjectMap<TypedExpr, OcamlAnonymousStructureDecision> = new ObjectMap();
		walk(root, (expression, _) -> {
			if (!OcamlAnonymousStructurePlan.isAdmittedLiteralCandidate(expression))
				return;
			final structure = structureFor(expression);
			if (structure != null)
				literalStructures.set(expression, structure);
		});
		final admittedLocals = findUnchangedLiteralAliases(root, literalStructures);

		final structures = [for (structure in structuresBySemanticType) structure];
		final operations = new Array<OcamlAnonymousStructureOperationDecision>();
		final literalIndexes = new Array<AnonymousLiteralIndex>();
		final operationIndexes = new Array<AnonymousOperationIndex>();
		function visit(expression:TypedExpr, path:String, suppressFieldRead:Bool):Void {
			final literalStructure = literalStructures.get(expression);
			if (literalStructure != null) {
				final fields = switch (expression.expr) {
					case TObjectDecl(values): values;
					case _: [];
				};
				final create = createOperation(expression, path, literalStructure);
				operations.push(create);
				final initializerIds = new Array<String>();
				for (index in 0...fields.length) {
					final initializer = fieldOperation(OcamlAnonymousStructureOperationKind.InitializeField, expression, path + "/field:" + index,
						literalStructure, fields[index].name, index);
					operations.push(initializer);
					initializerIds.push(initializer.id);
				}
				literalIndexes.push({
					expression: expression,
					structureId: literalStructure.id,
					createId: create.id,
					initializerIds: initializerIds
				});
			}

			switch (expression.expr) {
				case TBinop(OpAssign, lhs, rhs):
					switch (lhs.expr) {
						case TField(receiver, FAnon(fieldRef)):
							final structure = structureForAdmittedReceiver(receiver, literalStructures, admittedLocals);
							final field = structure == null ? null : Lambda.find(structure.fields, candidate -> candidate.name == fieldRef.get().name);
							if (structure != null && field != null && matchesFieldInput(rhs.t, field.semanticTypeId)) {
								final write = fieldOperation(OcamlAnonymousStructureOperationKind.WriteField, expression, path, structure, field.name, -1);
								operations.push(write);
								operationIndexes.push({expression: expression, decisionId: write.id});
							}
						case _:
					}
					visit(lhs, path + "/child:0", true);
					visit(rhs, path + "/child:1", false);
				case TField(receiver, FAnon(fieldRef)) if (!suppressFieldRead):
					final structure = structureForAdmittedReceiver(receiver, literalStructures, admittedLocals);
					if (structure != null) {
						final read = fieldOperation(OcamlAnonymousStructureOperationKind.ReadField, expression, path, structure, fieldRef.get().name, -1);
						operations.push(read);
						operationIndexes.push({expression: expression, decisionId: read.id});
					}
					var childIndex = 0;
					TypedExprTools.iter(expression, child -> {
						visit(child, path + "/child:" + childIndex, false);
						childIndex++;
					});
				case _:
					var childIndex = 0;
					TypedExprTools.iter(expression, child -> {
						visit(child, path + "/child:" + childIndex, false);
						childIndex++;
					});
			}
		}
		visit(root, "root", false);
		return new OcamlAnonymousStructurePlan(structures, operations, literalIndexes, operationIndexes);
	}

	/**
		Finds locals that are guaranteed to keep one admitted object reference.

		The first local may be initialized by a direct object literal, and later
		locals may copy that local. A local with any later assignment is excluded
		even when the replacement looks compatible, because proving assignment
		order and origin would require a broader data-flow model. This keeps a
		value received through a parameter, function call, or structural class
		conversion from being mistaken for an `HxAnon` table merely because its
		field names happen to match.
	**/
	function findUnchangedLiteralAliases(root:TypedExpr,
			literalStructures:ObjectMap<TypedExpr, OcamlAnonymousStructureDecision>):Map<Int, OcamlAnonymousStructureDecision> {
		final initializers:Map<Int, TypedExpr> = [];
		final reassigned:Map<Int, Bool> = [];
		walk(root, (expression, _) -> {
			switch (expression.expr) {
				case TVar(variable, initializer) if (initializer != null):
					initializers.set(variable.id, initializer);
				case TBinop(OpAssign, {expr: TLocal(variable)}, _):
					reassigned.set(variable.id, true);
				case _:
			}
		});

		final admitted:Map<Int, OcamlAnonymousStructureDecision> = [];
		var changed = true;
		while (changed) {
			changed = false;
			for (localId => initializer in initializers) {
				if (reassigned.exists(localId) || admitted.exists(localId))
					continue;
				final structure = structureForAdmittedValue(initializer, literalStructures, admitted);
				if (structure != null) {
					admitted.set(localId, structure);
					changed = true;
				}
			}
		}
		return admitted;
	}

	function structureFor(expression:TypedExpr):Null<OcamlAnonymousStructureDecision> {
		final semanticTypeId = OcamlAnonymousStructurePlan.semanticTypeIdForType(expression.t);
		if (semanticTypeId == null)
			return null;
		final existing = structuresBySemanticType.get(semanticTypeId);
		if (existing != null)
			return existing;
		final rawFields = OcamlAnonymousStructurePlan.anonymousFields(expression.t);
		if (rawFields == null)
			return null;
		final sorted = rawFields.copy();
		sorted.sort((left, right) -> Reflect.compare(left.name, right.name));
		final fields = new Array<OcamlAnonymousStructureField>();
		for (index in 0...sorted.length)
			fields.push(fieldDecision(sorted[index], index));
		final representation = representations.selectAnonymousStructure(semanticTypeId);
		final provisional:OcamlAnonymousStructureDecision = {
			id: OcamlAnonymousStructureContract.structureId(semanticTypeId),
			semanticTypeId: semanticTypeId,
			carrierTypeId: representation.carrierTypeId,
			fields: fields,
			representationId: representation.id,
			representationRevision: representation.revision,
			representationDomain: (representation.domain : String),
			nullPolicy: (representation.nullPolicy : String),
			identityPolicy: (representation.identityPolicy : String),
			aliasingPolicy: (representation.aliasingPolicy : String),
			mutationPolicy: (representation.valueMutationPolicy : String),
			proofId: OcamlAnonymousStructureContract.PROOF_ID,
			proofClaim: OcamlAnonymousStructureContract.PROOF_CLAIM,
			programRevision: binding.programRevision,
			revision: ""
		};
		final decision = copyStructureWithRevision(provisional, OcamlAnonymousStructureContract.structureRevision(provisional));
		OcamlAnonymousStructureContract.requireStructure(decision);
		structuresBySemanticType.set(semanticTypeId, decision);
		return decision;
	}

	function structureForAdmittedReceiver(receiver:TypedExpr, literalStructures:ObjectMap<TypedExpr, OcamlAnonymousStructureDecision>,
			admittedLocals:Map<Int, OcamlAnonymousStructureDecision>):Null<OcamlAnonymousStructureDecision> {
		final structure = structureForAdmittedValue(receiver, literalStructures, admittedLocals);
		if (structure == null)
			return null;
		final semanticTypeId = OcamlAnonymousStructurePlan.semanticTypeIdForType(receiver.t);
		return semanticTypeId == structure.semanticTypeId ? structure : null;
	}

	/**
		Returns the object representation only for a direct literal or proven alias.

		Parentheses and metadata wrappers do not create a new value, so the helper
		may look through them. Casts and calls are deliberately not unwrapped:
		they can introduce a same-shaped value with a different runtime
		representation.
	**/
	function structureForAdmittedValue(value:TypedExpr, literalStructures:ObjectMap<TypedExpr, OcamlAnonymousStructureDecision>,
			admittedLocals:Map<Int, OcamlAnonymousStructureDecision>):Null<OcamlAnonymousStructureDecision> {
		final direct = literalStructures.get(value);
		if (direct != null)
			return direct;
		return switch (value.expr) {
			case TLocal(variable):
				admittedLocals.get(variable.id);
			case TParenthesis(inner), TMeta(_, inner):
				structureForAdmittedValue(inner, literalStructures, admittedLocals);
			case _:
				null;
		}
	}

	function fieldDecision(field:ClassField, canonicalOrder:Int):OcamlAnonymousStructureField {
		final representation = fieldRepresentation(field.type);
		final boolCarrier = representation.semanticTypeId == "Bool";
		return {
			name: field.name,
			canonicalOrder: canonicalOrder,
			semanticTypeId: representation.semanticTypeId,
			carrierTypeId: representation.carrierTypeId,
			representationId: representation.id,
			representationRevision: representation.revision,
			storeConversion: boolCarrier ? OcamlAnonymousStructureStoreConversion.BoxBool : OcamlAnonymousStructureStoreConversion.ObjRepr,
			loadConversion: boolCarrier ? OcamlAnonymousStructureLoadConversion.UnboxBool : OcamlAnonymousStructureLoadConversion.ObjObj
		};
	}

	function fieldRepresentation(type:Type):OcamlRepresentationDecision {
		if (OcamlRepresentationRegistry.isExactInt(type))
			return representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
		if (OcamlRepresentationRegistry.isExactBool(type))
			return representations.selectExactBool(OcamlRepresentationDomain.InternalValue);
		if (OcamlRepresentationRegistry.isExactString(type) || OcamlRepresentationRegistry.isExactNullString(type))
			return representations.selectExactString(OcamlRepresentationDomain.InternalValue);
		throw 'reflaxe.ocaml [ocaml-anonymous:unsupported-field]: field type "${TypeTools.toString(type)}" has no admitted anonymous carrier';
	}

	static function matchesFieldInput(type:Type, semanticTypeId:String):Bool {
		return switch (semanticTypeId) {
			case "Int": OcamlRepresentationRegistry.isExactInt(type);
			case "Bool": OcamlRepresentationRegistry.isExactBool(type);
			case "String": OcamlRepresentationRegistry.isExactString(type) || OcamlRepresentationRegistry.isExactNullString(type);
			case _: false;
		}
	}

	function createOperation(expression:TypedExpr, path:String, structure:OcamlAnonymousStructureDecision):OcamlAnonymousStructureOperationDecision {
		return sealOperation({
			id: "",
			occurrenceId: occurrenceId(path + "/create"),
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			kind: OcamlAnonymousStructureOperationKind.Create,
			structureId: structure.id,
			structureRevision: structure.revision,
			structureRepresentationId: structure.representationId,
			structureRepresentationRevision: structure.representationRevision,
			fieldName: null,
			fieldCanonicalOrder: -1,
			fieldSourceOrder: -1,
			fieldSemanticTypeId: "",
			fieldCarrierTypeId: "",
			fieldRepresentationId: "",
			fieldRepresentationRevision: "",
			storeConversion: null,
			loadConversion: null,
			evaluationSchedule: ["create-container", "result-container"],
			resultSemanticTypeId: structure.semanticTypeId,
			resultCarrierTypeId: structure.carrierTypeId,
			resultRepresentationId: structure.representationId,
			resultRepresentationRevision: structure.representationRevision,
			runtimeModule: OcamlAnonymousStructureContract.RUNTIME_MODULE,
			runtimeOperation: "create",
			runtimeRequirementIds: [],
			proofId: OcamlAnonymousStructureContract.PROOF_ID,
			proofClaim: OcamlAnonymousStructureContract.PROOF_CLAIM,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		}, structure);
	}

	function fieldOperation(kind:OcamlAnonymousStructureOperationKind, expression:TypedExpr, path:String, structure:OcamlAnonymousStructureDecision,
			fieldName:String, sourceOrder:Int):OcamlAnonymousStructureOperationDecision {
		final field = Lambda.find(structure.fields, candidate -> candidate.name == fieldName);
		if (field == null)
			throw 'reflaxe.ocaml [ocaml-anonymous:wrong-field]: typed operation names "$fieldName", which is absent from "${structure.semanticTypeId}"';
		final reads = kind == OcamlAnonymousStructureOperationKind.ReadField;
		final writes = kind == OcamlAnonymousStructureOperationKind.WriteField;
		final initializer = kind == OcamlAnonymousStructureOperationKind.InitializeField;
		final provisional:OcamlAnonymousStructureOperationDecision = {
			id: "",
			occurrenceId: occurrenceId(path + "/" + (kind : String) + ":" + field.canonicalOrder),
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			kind: kind,
			structureId: structure.id,
			structureRevision: structure.revision,
			structureRepresentationId: structure.representationId,
			structureRepresentationRevision: structure.representationRevision,
			fieldName: field.name,
			fieldCanonicalOrder: field.canonicalOrder,
			fieldSourceOrder: sourceOrder,
			fieldSemanticTypeId: field.semanticTypeId,
			fieldCarrierTypeId: field.carrierTypeId,
			fieldRepresentationId: field.representationId,
			fieldRepresentationRevision: field.representationRevision,
			storeConversion: reads ? null : field.storeConversion,
			loadConversion: reads ? field.loadConversion : null,
			evaluationSchedule: initializer ? ["field-value", "box-field-value", "store-field"] : (reads ? ["receiver", "lookup-field", "unbox-field-value", "result-value"] : ["receiver", "field-value", "box-field-value", "store-field", "result-value"]),
			resultSemanticTypeId: initializer ? "Void" : field.semanticTypeId,
			resultCarrierTypeId: initializer ? "" : field.carrierTypeId,
			resultRepresentationId: initializer ? "" : field.representationId,
			resultRepresentationRevision: initializer ? "" : field.representationRevision,
			runtimeModule: OcamlAnonymousStructureContract.RUNTIME_MODULE,
			runtimeOperation: reads ? "get" : "set",
			runtimeRequirementIds: [],
			proofId: OcamlAnonymousStructureContract.PROOF_ID,
			proofClaim: OcamlAnonymousStructureContract.PROOF_CLAIM,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
		return sealOperation(provisional, structure);
	}

	function sealOperation(provisional:OcamlAnonymousStructureOperationDecision,
			structure:OcamlAnonymousStructureDecision):OcamlAnonymousStructureOperationDecision {
		final id = OcamlAnonymousStructureContract.operationId(provisional);
		final sealed = OcamlAnonymousStructureContract.copyOperation(provisional, id);
		OcamlAnonymousStructureContract.requireOperation(sealed, structure);
		return sealed;
	}

	function occurrenceId(path:String):String {
		return OcamlAnonymousStructureContract.OCCURRENCE_PREFIX + Sha256.encode(binding.functionId + "|" + path).substr(0, 24);
	}

	static function copyStructureWithRevision(structure:OcamlAnonymousStructureDecision, revision:String):OcamlAnonymousStructureDecision {
		return {
			id: structure.id,
			semanticTypeId: structure.semanticTypeId,
			carrierTypeId: structure.carrierTypeId,
			fields: structure.fields,
			representationId: structure.representationId,
			representationRevision: structure.representationRevision,
			representationDomain: structure.representationDomain,
			nullPolicy: structure.nullPolicy,
			identityPolicy: structure.identityPolicy,
			aliasingPolicy: structure.aliasingPolicy,
			mutationPolicy: structure.mutationPolicy,
			proofId: structure.proofId,
			proofClaim: structure.proofClaim,
			programRevision: structure.programRevision,
			revision: revision
		};
	}

	static function walk(root:TypedExpr, visit:(TypedExpr, String) -> Void):Void {
		function loop(expression:TypedExpr, path:String):Void {
			visit(expression, path);
			var childIndex = 0;
			TypedExprTools.iter(expression, child -> {
				loop(child, path + "/child:" + childIndex);
				childIndex++;
			});
		}
		loop(root, "root");
	}
}
#end
