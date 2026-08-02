package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceCallDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceContract;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceSourceKind;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan.OcamlIMapInterfaceConversionMaterialization;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan.OcamlIMapInterfaceMethodMaterialization;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapOperation;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapStringifier;

/**
	Target-syntax operations supplied by the request-local OCaml builder.

	The syntax helper needs to render nested Haxe expressions and resolve the
	already-selected user method to its generated OCaml name. These callbacks do
	not decide which interface method or runtime implementation is used; those
	choices are fixed in the sealed `IMap` plan before this helper runs.
**/
typedef OcamlIMapInterfaceSyntaxServices = {
	final buildExpression:TypedExpr->OcamlExpr;
	final freshName:String->String;
	final typeExpression:Type->OcamlTypeExpr;
	final coerceToObjectCarrier:(Type, OcamlExpr) -> OcamlExpr;
	final userMethodTarget:OcamlIMapInterfaceMethodMaterialization->OcamlExpr;
}

/**
	Renders the sealed OCaml representation of Haxe `IMap` conversions and calls.

	A concrete standard Map and a user-defined `IMap` class have different runtime
	shapes. Planning converts either source into one checked dispatch record whose
	fields implement the `IMap` methods retained by Haxe dead-code elimination.
	This module only builds
	OCaml expressions from that record: it never infers the receiver implementation
	from a key type, class name, or generated text.
**/
class OcamlIMapInterfaceSyntax {
	/** Evaluates the receiver and arguments once, then invokes the sealed dispatch field. */
	public static function buildCall(decision:OcamlIMapInterfaceCallDecision, callee:TypedExpr, arguments:Array<TypedExpr>,
			services:OcamlIMapInterfaceSyntaxServices):OcamlExpr {
		OcamlIMapInterfacePlan.requireCallDecision(decision);
		final receiver = switch (callee.expr) {
			case TField(receiverExpression, FInstance(classRef, parameters, fieldRef))
				if (OcamlStandardIMapCallContract.isIMapClass(classRef.get()) && parameters.length == 2):
				final operation = OcamlStandardIMapCallContract.operationFor(fieldRef.get().name, arguments.length);
				if (operation == null || operation != decision.operation)
					throw 'IMap interface call "${decision.id}" no longer matches its sealed method';
				receiverExpression;
			case _:
				throw 'IMap interface call "${decision.id}" no longer has its typed interface receiver';
		};
		if (arguments.length != decision.argumentSemanticTypeIds.length)
			throw 'IMap interface call "${decision.id}" has a different argument count from its sealed decision';

		final receiverName = services.freshName("imap_interface_receiver");
		final receiverValue = OcamlExpr.EIdent(receiverName);
		final materialized:Array<{name:String, value:OcamlExpr}> = [{name: receiverName, value: services.buildExpression(receiver)}];
		final invocationArguments:Array<OcamlExpr> = [receiverValue];
		for (index in 0...arguments.length) {
			final argumentName = services.freshName("imap_interface_arg_" + index);
			materialized.push({name: argumentName, value: services.buildExpression(arguments[index])});
			invocationArguments.push(services.coerceToObjectCarrier(arguments[index].t, OcamlExpr.EIdent(argumentName)));
		}
		if (arguments.length == 0)
			invocationArguments.push(OcamlExpr.EConst(OcamlConst.CUnit));

		final record = OcamlExpr.EAnnot(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [receiverValue]),
			OcamlTypeExpr.TIdent("Haxe_Constraints.imap_t"));
		final field = OcamlExpr.EField(record, OcamlStandardIMapCallContract.sourceFieldName(decision.operation));
		final resultType = switch (TypeTools.follow(callee.t)) {
			case TFun(_, result): services.typeExpression(result);
			case _: throw 'IMap interface call "${decision.id}" lost its typed result';
		};
		var out = adaptCallResult(decision.operation, resultType, OcamlExpr.EApp(field, invocationArguments));
		for (offset in 0...materialized.length) {
			final binding = materialized[materialized.length - 1 - offset];
			out = OcamlExpr.ELet(binding.name, binding.value, out, false);
		}
		return out;
	}

	/** Builds one concrete-to-interface adapter selected from the final typed body. */
	public static function buildConversion(materialization:OcamlIMapInterfaceConversionMaterialization, value:TypedExpr,
			services:OcamlIMapInterfaceSyntaxServices):OcamlExpr {
		OcamlIMapInterfacePlan.requireConversionDecision(materialization.decision);
		return switch (materialization.decision.sourceKind) {
			case UserImplementation:
				buildUserAdapter(materialization, value, services);
			case StandardStringMap, StandardIntMap, StandardObjectMap:
				buildStandardAdapter(materialization, value, services);
			case _:
				throw 'IMap conversion "${materialization.decision.id}" has an unsupported source kind';
		};
	}

	/** Converts an erased dispatch result to the carrier fixed by the typed call. */
	static function adaptCallResult(operation:OcamlStandardIMapOperation, resultType:OcamlTypeExpr, result:OcamlExpr):OcamlExpr {
		return switch (operation) {
			case Set, Exists, Remove, ToString, Clear:
				result;
			case Get, Copy:
				isObjectCarrierType(resultType) ? result : OcamlExpr.EAnnot(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [result]),
					resultType);
			case Keys, Values, Pairs:
				// Iterator interfaces are opaque in the generated declaration. Leaving
				// `Obj.obj` polymorphic lets the typed consumer fix the HxIterator carrier.
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [result]);
			case _:
				throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-result]: unsupported operation "$operation"';
		};
	}

	/** Builds a record whose closures invoke the original user class methods. */
	static function buildUserAdapter(materialization:OcamlIMapInterfaceConversionMaterialization, value:TypedExpr,
			services:OcamlIMapInterfaceSyntaxServices):OcamlExpr {
		final receiverName = services.freshName("imap_user_receiver");
		final receiver = OcamlExpr.EIdent(receiverName);
		final fields:Array<{name:String, value:OcamlExpr}> = [typeMarkerField()];
		for (method in materialization.methods) {
			final parameterNames = [for (index in 0...method.argumentTypes.length) "a" + index];
			final parameters:Array<OcamlPat> = [OcamlPat.PAny];
			if (parameterNames.length == 0) {
				parameters.push(OcamlPat.PConst(OcamlConst.CUnit));
			} else {
				for (name in parameterNames)
					parameters.push(OcamlPat.PVar(name));
			}
			final callArguments:Array<OcamlExpr> = [receiver];
			for (index in 0...parameterNames.length)
				callArguments.push(decodeArgument(method.argumentTypes[index], OcamlExpr.EIdent(parameterNames[index]), services));
			if (parameterNames.length == 0)
				callArguments.push(OcamlExpr.EConst(OcamlConst.CUnit));
			final call = OcamlExpr.EApp(services.userMethodTarget(method), callArguments);
			fields.push({
				name: OcamlStandardIMapCallContract.sourceFieldName(method.operation),
				value: OcamlExpr.EFun(parameters, adaptConcreteMethodResult(method.operation, method.resultType, call, services))
			});
		}
		final record = OcamlExpr.EAnnot(OcamlExpr.ERecord(fields), OcamlTypeExpr.TIdent("Haxe_Constraints.imap_t"));
		return OcamlExpr.ELet(receiverName, services.buildExpression(value), OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [record]),
			false);
	}

	/** Builds the same dispatch surface around one proven standard Map carrier. */
	static function buildStandardAdapter(materialization:OcamlIMapInterfaceConversionMaterialization, value:TypedExpr,
			services:OcamlIMapInterfaceSyntaxServices):OcamlExpr {
		final keyKind = materialization.decision.standardKeyKind;
		if (keyKind == null)
			throw 'standard IMap conversion "${materialization.decision.id}" has no sealed key carrier';
		final adapterName = services.freshName("adapt_standard_imap");
		final receiverName = services.freshName("standard_imap_receiver");
		final receiver = OcamlExpr.EIdent(receiverName);
		final fields:Array<{name:String, value:OcamlExpr}> = [typeMarkerField()];
		for (operation in materialization.operations) {
			final argumentTypes = argumentTypes(operation, materialization.keyType, materialization.valueType);
			final parameterNames = [for (index in 0...argumentTypes.length) "a" + index];
			final parameters:Array<OcamlPat> = [OcamlPat.PAny];
			if (parameterNames.length == 0) {
				parameters.push(OcamlPat.PConst(OcamlConst.CUnit));
			} else {
				for (name in parameterNames)
					parameters.push(OcamlPat.PVar(name));
			}
			final runtimeArguments:Array<OcamlExpr> = [receiver];
			for (index in 0...argumentTypes.length)
				runtimeArguments.push(decodeArgument(argumentTypes[index], OcamlExpr.EIdent(parameterNames[index]), services));
			final runtimeCall = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxMap"), OcamlStandardIMapCallContract.runtimeFunction(operation, keyKind)),
				runtimeArguments);
			final methodBody = switch (operation) {
				case Get:
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [runtimeCall]);
				case Keys, Values, Pairs:
					OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [
						OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxIterator"), "of_array"), [runtimeCall])
					]);
				case Copy:
					OcamlExpr.EApp(OcamlExpr.EIdent(adapterName), [runtimeCall]);
				case ToString:
					final keyStringifier = materialization.decision.keyStringifier;
					final valueStringifier = materialization.decision.valueStringifier;
					if (keyStringifier == null || valueStringifier == null)
						throw 'standard IMap conversion "${materialization.decision.id}" has no sealed text conversion';
					formatStandardEntries(runtimeCall, keyStringifier, valueStringifier, services.freshName);
				case Set, Exists, Remove, Clear:
					runtimeCall;
				case _:
					throw 'standard IMap conversion "${materialization.decision.id}" selected an unsupported operation';
			};
			fields.push({
				name: OcamlStandardIMapCallContract.sourceFieldName(operation),
				value: OcamlExpr.EFun(parameters, methodBody)
			});
		}
		final record = OcamlExpr.EAnnot(OcamlExpr.ERecord(fields), OcamlTypeExpr.TIdent("Haxe_Constraints.imap_t"));
		final adapter = OcamlExpr.EFun([OcamlPat.PVar(receiverName)], OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [record]));
		final recursive = materialization.operations.indexOf(OcamlStandardIMapOperation.Copy) >= 0;
		return OcamlExpr.ELet(adapterName, adapter, OcamlExpr.EApp(OcamlExpr.EIdent(adapterName), [services.buildExpression(value)]), recursive);
	}

	/** Returns the typed source arguments for one already-admitted operation. */
	static function argumentTypes(operation:OcamlStandardIMapOperation, keyType:Type, valueType:Type):Array<Type> {
		return switch (operation) {
			case Set: [keyType, valueType];
			case Get, Exists, Remove: [keyType];
			case Keys, Values, Pairs, Copy, ToString, Clear: [];
			case _: throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-operation]: unsupported operation "$operation"';
		};
	}

	/** Produces the runtime type marker shared by every dispatch record. */
	static function typeMarkerField():{name:String, value:OcamlExpr} {
		return {
			name: "__hx_type",
			value: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "class_"), [OcamlExpr.EConst(OcamlConst.CString("haxe.IMap"))])
		};
	}

	/** Converts one erased interface argument to its already-selected OCaml carrier. */
	static function decodeArgument(type:Type, value:OcamlExpr, services:OcamlIMapInterfaceSyntaxServices):OcamlExpr {
		final carrier = services.typeExpression(type);
		if (isObjectCarrierType(carrier))
			return value;
		if (OcamlRepresentationRegistry.isExactBool(type))
			return OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [value]);
		return OcamlExpr.EAnnot(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [value]), carrier);
	}

	/** Converts one concrete user-method result to the erased interface field. */
	static function adaptConcreteMethodResult(operation:OcamlStandardIMapOperation, resultType:Type, result:OcamlExpr,
			services:OcamlIMapInterfaceSyntaxServices):OcamlExpr {
		return switch (operation) {
			case Get, Keys, Values, Pairs, Copy:
				services.coerceToObjectCarrier(resultType, result);
			case Set, Exists, Remove, ToString, Clear:
				result;
			case _:
				throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-user-result]: unsupported operation "$operation"';
		};
	}

	/** Returns whether a target type is the opaque carrier used by interface values. */
	static function isObjectCarrierType(type:OcamlTypeExpr):Bool {
		return switch (type) {
			case TIdent("Obj.t"): true;
			case TApp("Obj", [TIdent("t")]): true;
			case _: false;
		};
	}

	/** Formats standard Map entries with the value-to-text choices saved by planning. */
	static function formatStandardEntries(pairs:OcamlExpr, keyStringifier:OcamlStandardIMapStringifier, valueStringifier:OcamlStandardIMapStringifier,
			freshName:String->String):OcamlExpr {
		final iteratorName = freshName("imap_pairs");
		final entriesName = freshName("imap_entries");
		final entryName = freshName("imap_entry");
		final itemName = freshName("imap_text");
		final iterator = OcamlExpr.EIdent(iteratorName);
		final entries = OcamlExpr.EIdent(entriesName);
		final entry = OcamlExpr.EIdent(entryName);
		final nextEntry = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxIterator"), "next"), [iterator]);
		final key = OcamlExpr.EApp(OcamlExpr.EIdent("fst"), [entry]);
		final value = OcamlExpr.EApp(OcamlExpr.EIdent("snd"), [entry]);
		final text = OcamlExpr.EBinop(OcamlBinop.Concat, stringify(keyStringifier, key),
			OcamlExpr.EBinop(OcamlBinop.Concat, OcamlExpr.EConst(OcamlConst.CString(" => ")), stringify(valueStringifier, value)));
		final push = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [
			OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "push"), [entries, text])
		]);
		final loop = OcamlExpr.EWhile(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxIterator"), "hasNext"), [iterator]),
			OcamlExpr.ELet(entryName, nextEntry, push, false));
		final joined = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "join"), [
			entries,
			OcamlExpr.EConst(OcamlConst.CString(", ")),
			OcamlExpr.EFun([OcamlPat.PVar(itemName)], OcamlExpr.EIdent(itemName))
		]);
		final formatted = OcamlExpr.EBinop(OcamlBinop.Concat, OcamlExpr.EConst(OcamlConst.CString("[")),
			OcamlExpr.EBinop(OcamlBinop.Concat, joined, OcamlExpr.EConst(OcamlConst.CString("]"))));
		return OcamlExpr.ELet(iteratorName, OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxIterator"), "of_array"), [pairs]),
			OcamlExpr.ELet(entriesName, OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"), [OcamlExpr.EConst(OcamlConst.CUnit)]),
				OcamlExpr.ESeq([loop, formatted]), false),
			false);
	}

	/** Applies one sealed Haxe value-to-text family. */
	static function stringify(stringifier:OcamlStandardIMapStringifier, value:OcamlExpr):OcamlExpr {
		return switch (stringifier) {
			case ExactString:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "toStdString"), [value]);
			case ExactInt:
				OcamlExpr.EApp(OcamlExpr.EIdent("string_of_int"), [value]);
			case ExactFloat:
				OcamlExpr.EApp(OcamlExpr.EIdent("string_of_float"), [value]);
			case ExactBool:
				OcamlExpr.EApp(OcamlExpr.EIdent("string_of_bool"), [value]);
			case DynamicObject:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxDynamic"), "toStdString"),
					[OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [value])]);
			case _:
				throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-stringifier]: unsupported stringifier "$stringifier"';
		};
	}
}
#end
