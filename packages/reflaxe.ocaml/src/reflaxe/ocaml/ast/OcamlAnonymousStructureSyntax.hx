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

/**
	Constructs OCaml expressions from sealed anonymous-object operations.

	The helper receives the selected structure, exact field carriers, conversion
	steps, and evaluation schedule. It can call `HxAnon.create`, `get`, or `set`,
	but it cannot decide that an unplanned Haxe value should use `HxAnon`.
**/
class OcamlAnonymousStructureSyntax {
	/**
		Creates one object and initializes its fields in Haxe source order.

		`buildExpression` is called exactly once for each field expression. The
		container is allocated before the first field value, matching the schedule
		validated by the plan.
	**/
	public static function buildLiteral(plan:OcamlAnonymousStructureLiteralPlan, fields:Array<{
		name:String,
		expr:TypedExpr
	}>, buildExpression:TypedExpr->OcamlExpr, freshName:String->String):OcamlExpr {
		OcamlAnonymousStructureContract.requireStructure(plan.structure);
		OcamlAnonymousStructureContract.requireOperation(plan.create, plan.structure);
		if (fields.length != plan.initializers.length)
			throw 'reflaxe.ocaml [ocaml-anonymous:literal-syntax-field-count]: literal expected ${plan.initializers.length} fields but received ${fields.length}';
		final containerName = freshName("anonymous_value");
		final create = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(plan.create.runtimeModule), plan.create.runtimeOperation),
			[OcamlExpr.EConst(OcamlConst.CUnit)]);
		final steps = new Array<OcamlExpr>();
		for (index in 0...fields.length) {
			final operation = plan.initializers[index];
			OcamlAnonymousStructureContract.requireOperation(operation, plan.structure);
			if (operation.kind != OcamlAnonymousStructureOperationKind.InitializeField
				|| operation.fieldSourceOrder != index
				|| operation.fieldName != fields[index].name) {
				throw 'reflaxe.ocaml [ocaml-anonymous:literal-syntax-order]: source field "${fields[index].name}" does not match initializer ${operation.id} at order $index';
			}
			final stored = storeValue(operation, buildExpression(fields[index].expr));
			final call = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(operation.runtimeModule), operation.runtimeOperation), [
				OcamlExpr.EIdent(containerName),
				OcamlExpr.EConst(OcamlConst.CString(fields[index].name)),
				stored
			]);
			steps.push(OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [call]));
		}
		steps.push(OcamlExpr.EIdent(containerName));
		return OcamlExpr.ELet(containerName, create, OcamlExpr.ESeq(steps), false);
	}

	/** Reads one field after evaluating the receiver exactly once. */
	public static function buildRead(operation:OcamlAnonymousStructureOperationDecision, receiver:TypedExpr, buildExpression:TypedExpr->OcamlExpr,
			freshName:String->String):OcamlExpr {
		if (operation.kind != OcamlAnonymousStructureOperationKind.ReadField)
			throw 'reflaxe.ocaml [ocaml-anonymous:read-syntax-kind]: operation "${operation.id}" is not a field read';
		final receiverName = freshName("anonymous_receiver");
		final loaded = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(operation.runtimeModule), operation.runtimeOperation), [
			OcamlExpr.EIdent(receiverName),
			OcamlExpr.EConst(OcamlConst.CString(operation.fieldName))
		]);
		return OcamlExpr.ELet(receiverName, buildExpression(receiver), loadValue(operation, loaded), false);
	}

	/**
		Writes one field while preserving Haxe assignment order and result value.

		The receiver is evaluated first, then the right-hand side once. The boxed
		value is stored in the original shared container, while the assignment
		expression returns the unboxed Haxe value.
	**/
	public static function buildWrite(operation:OcamlAnonymousStructureOperationDecision, receiver:TypedExpr, value:TypedExpr,
			buildExpression:TypedExpr->OcamlExpr, freshName:String->String):OcamlExpr {
		if (operation.kind != OcamlAnonymousStructureOperationKind.WriteField)
			throw 'reflaxe.ocaml [ocaml-anonymous:write-syntax-kind]: operation "${operation.id}" is not a field write';
		final receiverName = freshName("anonymous_receiver");
		final valueName = freshName("anonymous_field_value");
		final store = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(operation.runtimeModule), operation.runtimeOperation), [
			OcamlExpr.EIdent(receiverName),
			OcamlExpr.EConst(OcamlConst.CString(operation.fieldName)),
			storeValue(operation, OcamlExpr.EIdent(valueName))
		]);
		final writeAndReturn = OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [store]), OcamlExpr.EIdent(valueName)]);
		return OcamlExpr.ELet(receiverName, buildExpression(receiver), OcamlExpr.ELet(valueName, buildExpression(value), writeAndReturn, false), false);
	}

	/**
		Applies a sealed `Int += Int` operation without evaluating either input twice.

		The generated sequence evaluates the object, reads and unboxes its old
		field, evaluates the right-hand side, performs Haxe's 32-bit addition,
		stores the new value, and returns that same new value. The plan has already
		selected every step; this helper only translates them into OCaml syntax.
	**/
	public static function buildCompoundWrite(operation:OcamlAnonymousStructureOperationDecision, receiver:TypedExpr, value:TypedExpr,
			buildExpression:TypedExpr->OcamlExpr, freshName:String->String):OcamlExpr {
		if (operation.kind != OcamlAnonymousStructureOperationKind.CompoundWriteField)
			throw 'reflaxe.ocaml [ocaml-anonymous:compound-write-syntax-kind]: operation "${operation.id}" is not a compound field write';
		final readOperation = operation.runtimeReadOperation;
		if (readOperation == null)
			throw 'reflaxe.ocaml [ocaml-anonymous:compound-write-syntax-read]: operation "${operation.id}" has no planned field read';
		final receiverName = freshName("anonymous_receiver");
		final oldValueName = freshName("anonymous_old_field_value");
		final valueName = freshName("anonymous_field_value");
		final newValueName = freshName("anonymous_new_field_value");
		final loaded = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(operation.runtimeModule), readOperation), [
			OcamlExpr.EIdent(receiverName),
			OcamlExpr.EConst(OcamlConst.CString(operation.fieldName))
		]);
		final updated = switch (operation.fieldOperator) {
			case IntAdd:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"), [OcamlExpr.EIdent(oldValueName), OcamlExpr.EIdent(valueName)]);
			case null:
				throw 'reflaxe.ocaml [ocaml-anonymous:compound-write-syntax-operator]: operation "${operation.id}" has no planned field operator';
		}
		final store = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(operation.runtimeModule), operation.runtimeOperation), [
			OcamlExpr.EIdent(receiverName),
			OcamlExpr.EConst(OcamlConst.CString(operation.fieldName)),
			storeValue(operation, OcamlExpr.EIdent(newValueName))
		]);
		final storeAndReturn = OcamlExpr.ESeq([
			OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [store]),
			OcamlExpr.EIdent(newValueName)
		]);
		return OcamlExpr.ELet(receiverName, buildExpression(receiver),
			OcamlExpr.ELet(oldValueName, loadValue(operation, loaded),
				OcamlExpr.ELet(valueName, buildExpression(value), OcamlExpr.ELet(newValueName, updated, storeAndReturn, false), false), false),
			false);
	}

	static function storeValue(operation:OcamlAnonymousStructureOperationDecision, value:OcamlExpr):OcamlExpr {
		return switch (operation.storeConversion) {
			case ObjRepr:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [value]);
			case BoxBool:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [value]);
			case null:
				throw 'reflaxe.ocaml [ocaml-anonymous:missing-store-conversion]: operation "${operation.id}" has no field-store conversion';
		}
	}

	static function loadValue(operation:OcamlAnonymousStructureOperationDecision, value:OcamlExpr):OcamlExpr {
		return switch (operation.loadConversion) {
			case ObjObj:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [value]);
			case UnboxBool:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [value]);
			case null:
				throw 'reflaxe.ocaml [ocaml-anonymous:missing-load-conversion]: operation "${operation.id}" has no field-load conversion';
		}
	}
}
#end
