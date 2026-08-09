package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureContract;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureFieldOperator;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureLoadConversion;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationKind;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureStoreConversion;
import reflaxe.ocaml.lowered.OcamlAnonymousStructurePlan.OcamlAnonymousStructureLiteralPlan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

/** One operation-owned subtree whose private identifiers must be reconciled. */
typedef OcamlAnonymousStructureRuntimeOperation = {
	final operationId:String;
	final expression:OcamlExpr;
}

/** The generated expression and the private-runtime subtrees inserted into it. */
typedef OcamlAnonymousStructureMaterialization = {
	final expression:OcamlExpr;
	final runtimeOperations:Array<OcamlAnonymousStructureRuntimeOperation>;
}

/**
	Constructs OCaml expressions from sealed anonymous-object operations.

	The helper receives the selected structure, exact field carriers, conversion
	steps, evaluation schedule, and permissions for the private runtime names it
	may insert. It cannot decide that an unplanned Haxe value should use `HxAnon`
	or introduce a helper that the source-bound operation did not name.
**/
class OcamlAnonymousStructureSyntax {
	/**
		Creates one object and initializes its fields in Haxe source order.

		`buildExpression` is called exactly once for each field expression. Each
		create or initialize operation has a separate runtime authority, so a field
		cannot reuse another field's permission.
	**/
	public static function buildLiteral(plan:OcamlAnonymousStructureLiteralPlan, fields:Array<{
		name:String,
		expr:TypedExpr
	}>,
			buildExpression:TypedExpr->OcamlExpr, freshName:String->String,
			runtimeAuthorityFor:OcamlAnonymousStructureOperationDecision->OcamlRuntimeUseAuthority):OcamlAnonymousStructureMaterialization {
		OcamlAnonymousStructureContract.requireStructure(plan.structure);
		OcamlAnonymousStructureContract.requireOperation(plan.create, plan.structure);
		if (fields.length != plan.initializers.length)
			throw 'reflaxe.ocaml [ocaml-anonymous:literal-syntax-field-count]: literal expected ${plan.initializers.length} fields but received ${fields.length}';
		final containerName = freshName("anonymous_value");
		final createAuthority = runtimeAuthorityFor(plan.create);
		final create = OcamlExpr.EApp(runtimeIdentifier(plan.create, createAuthority, "create-container",
			plan.create.runtimeModule + "." + plan.create.runtimeOperation),
			[OcamlExpr.EConst(OcamlConst.CUnit)]);
		final steps = new Array<OcamlExpr>();
		final runtimeOperations:Array<OcamlAnonymousStructureRuntimeOperation> = [{operationId: plan.create.id, expression: create}];
		for (index in 0...fields.length) {
			final operation = plan.initializers[index];
			OcamlAnonymousStructureContract.requireOperation(operation, plan.structure);
			if (operation.kind != OcamlAnonymousStructureOperationKind.InitializeField
				|| operation.fieldSourceOrder != index
				|| operation.fieldName != fields[index].name) {
				throw 'reflaxe.ocaml [ocaml-anonymous:literal-syntax-order]: source field "${fields[index].name}" does not match initializer ${operation.id} at order $index';
			}
			final runtimeAuthority = runtimeAuthorityFor(operation);
			final stored = storeValue(operation, buildExpression(fields[index].expr), runtimeAuthority);
			final call = OcamlExpr.EApp(runtimeIdentifier(operation, runtimeAuthority, "initialize-field",
				operation.runtimeModule + "." + operation.runtimeOperation), [
					OcamlExpr.EIdent(containerName),
					OcamlExpr.EConst(OcamlConst.CString(fields[index].name)),
					stored
				]);
			steps.push(OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [call]));
			runtimeOperations.push({operationId: operation.id, expression: call});
		}
		steps.push(OcamlExpr.EIdent(containerName));
		return {
			expression: OcamlExpr.ELet(containerName, create, OcamlExpr.ESeq(steps), false),
			runtimeOperations: runtimeOperations
		};
	}

	/** Reads one field after evaluating the receiver exactly once. */
	public static function buildRead(operation:OcamlAnonymousStructureOperationDecision, receiver:TypedExpr, buildExpression:TypedExpr->OcamlExpr,
			freshName:String->String, runtimeAuthority:OcamlRuntimeUseAuthority):OcamlAnonymousStructureMaterialization {
		if (operation.kind != OcamlAnonymousStructureOperationKind.ReadField)
			throw 'reflaxe.ocaml [ocaml-anonymous:read-syntax-kind]: operation "${operation.id}" is not a field read';
		final receiverName = freshName("anonymous_receiver");
		final loaded = OcamlExpr.EApp(runtimeIdentifier(operation, runtimeAuthority, "read-field",
			operation.runtimeModule + "." + operation.runtimeOperation), [
				OcamlExpr.EIdent(receiverName),
				OcamlExpr.EConst(OcamlConst.CString(operation.fieldName))
			]);
		final converted = loadValue(operation, loaded, runtimeAuthority);
		return {
			expression: OcamlExpr.ELet(receiverName, buildExpression(receiver), converted, false),
			runtimeOperations: [{operationId: operation.id, expression: converted}]
		};
	}

	/**
		Writes one field while preserving Haxe assignment order and result value.

		The receiver is evaluated first, then the right-hand side once. The boxed
		value is stored in the original shared container, while the assignment
		expression returns the unboxed Haxe value.
	**/
	public static function buildWrite(operation:OcamlAnonymousStructureOperationDecision, receiver:TypedExpr, value:TypedExpr,
			buildExpression:TypedExpr->OcamlExpr, freshName:String->String, runtimeAuthority:OcamlRuntimeUseAuthority):OcamlAnonymousStructureMaterialization {
		if (operation.kind != OcamlAnonymousStructureOperationKind.WriteField)
			throw 'reflaxe.ocaml [ocaml-anonymous:write-syntax-kind]: operation "${operation.id}" is not a field write';
		final receiverName = freshName("anonymous_receiver");
		final valueName = freshName("anonymous_field_value");
		final store = OcamlExpr.EApp(runtimeIdentifier(operation, runtimeAuthority, "write-field",
			operation.runtimeModule + "." + operation.runtimeOperation), [
				OcamlExpr.EIdent(receiverName),
				OcamlExpr.EConst(OcamlConst.CString(operation.fieldName)),
				storeValue(operation, OcamlExpr.EIdent(valueName), runtimeAuthority)
			]);
		final writeAndReturn = OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [store]), OcamlExpr.EIdent(valueName)]);
		return {
			expression: OcamlExpr.ELet(receiverName, buildExpression(receiver), OcamlExpr.ELet(valueName, buildExpression(value), writeAndReturn, false),
				false),
			runtimeOperations: [
				{
					operationId: operation.id,
					expression: store
				}
			]
		};
	}

	/**
		Applies a sealed `Int += Int` operation without evaluating either input twice.

		The generated sequence evaluates the object, reads and unboxes its old
		field, evaluates the right-hand side, performs Haxe's 32-bit addition,
		stores the new value, and returns that same new value.
	**/
	public static function buildCompoundWrite(operation:OcamlAnonymousStructureOperationDecision, receiver:TypedExpr, value:TypedExpr,
			buildExpression:TypedExpr->OcamlExpr, freshName:String->String, runtimeAuthority:OcamlRuntimeUseAuthority):OcamlAnonymousStructureMaterialization {
		if (operation.kind != OcamlAnonymousStructureOperationKind.CompoundWriteField)
			throw 'reflaxe.ocaml [ocaml-anonymous:compound-write-syntax-kind]: operation "${operation.id}" is not a compound field write';
		final readOperation = operation.runtimeReadOperation;
		if (readOperation == null)
			throw 'reflaxe.ocaml [ocaml-anonymous:compound-write-syntax-read]: operation "${operation.id}" has no planned field read';
		final receiverName = freshName("anonymous_receiver");
		final oldValueName = freshName("anonymous_old_field_value");
		final valueName = freshName("anonymous_field_value");
		final newValueName = freshName("anonymous_new_field_value");
		final loaded = OcamlExpr.EApp(runtimeIdentifier(operation, runtimeAuthority, "read-field", operation.runtimeModule + "." + readOperation), [
			OcamlExpr.EIdent(receiverName),
			OcamlExpr.EConst(OcamlConst.CString(operation.fieldName))
		]);
		final convertedOldValue = loadValue(operation, loaded, runtimeAuthority);
		final updated = switch (operation.fieldOperator) {
			case IntAdd:
				OcamlExpr.EApp(runtimeIdentifier(operation, runtimeAuthority, "apply-field-operator", "HxInt.add"),
					[OcamlExpr.EIdent(oldValueName), OcamlExpr.EIdent(valueName)]);
			case null:
				throw 'reflaxe.ocaml [ocaml-anonymous:compound-write-syntax-operator]: operation "${operation.id}" has no planned field operator';
		}
		final store = OcamlExpr.EApp(runtimeIdentifier(operation, runtimeAuthority, "write-field",
			operation.runtimeModule + "." + operation.runtimeOperation), [
				OcamlExpr.EIdent(receiverName),
				OcamlExpr.EConst(OcamlConst.CString(operation.fieldName)),
				storeValue(operation, OcamlExpr.EIdent(newValueName), runtimeAuthority)
			]);
		final storeAndReturn = OcamlExpr.ESeq([
			OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [store]),
			OcamlExpr.EIdent(newValueName)
		]);
		return {
			expression: OcamlExpr.ELet(receiverName, buildExpression(receiver),
				OcamlExpr.ELet(oldValueName, convertedOldValue,
					OcamlExpr.ELet(valueName, buildExpression(value), OcamlExpr.ELet(newValueName, updated, storeAndReturn, false), false), false),
				false),
			runtimeOperations: [
				{
					operationId: operation.id,
					expression: OcamlExpr.ESeq([convertedOldValue, updated, store])
				}
			]
		};
	}

	static function storeValue(operation:OcamlAnonymousStructureOperationDecision, value:OcamlExpr, runtimeAuthority:OcamlRuntimeUseAuthority):OcamlExpr {
		return switch (operation.storeConversion) {
			case ObjRepr:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [value]);
			case BoxBool:
				OcamlExpr.EApp(runtimeIdentifier(operation, runtimeAuthority, "box-field-value", "HxRuntime.box_bool"), [value]);
			case null:
				throw 'reflaxe.ocaml [ocaml-anonymous:missing-store-conversion]: operation "${operation.id}" has no field-store conversion';
		}
	}

	static function loadValue(operation:OcamlAnonymousStructureOperationDecision, value:OcamlExpr, runtimeAuthority:OcamlRuntimeUseAuthority):OcamlExpr {
		return switch (operation.loadConversion) {
			case ObjObj:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [value]);
			case UnboxBool:
				OcamlExpr.EApp(runtimeIdentifier(operation, runtimeAuthority, "unbox-field-value", "HxRuntime.unbox_bool_or_obj"), [value]);
			case null:
				throw 'reflaxe.ocaml [ocaml-anonymous:missing-load-conversion]: operation "${operation.id}" has no field-load conversion';
		}
	}

	static function runtimeIdentifier(operation:OcamlAnonymousStructureOperationDecision, authority:OcamlRuntimeUseAuthority, role:String,
			exactSymbol:String):OcamlExpr {
		if (authority == null)
			throw 'reflaxe.ocaml [ocaml-anonymous:missing-runtime-authority]: operation "${operation.id}" cannot construct private runtime identifiers';
		final matches = operation.runtimeUseOccurrences.filter(use -> use.role == role);
		if (matches.length != 1 || matches[0].exactSymbol != exactSymbol)
			throw 'reflaxe.ocaml [ocaml-anonymous:wrong-runtime-use]: operation "${operation.id}" has no exact $role/$exactSymbol occurrence';
		final use = matches[0];
		return OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol));
	}
}
#end
