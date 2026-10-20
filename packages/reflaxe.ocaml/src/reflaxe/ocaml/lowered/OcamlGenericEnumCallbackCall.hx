package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.parameterId;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.lowered.OcamlNativeEnumRepresentation.OcamlNativeEnumDescriptor;

/** Exact source operands and enum storage for an immediately invoked generic callback. */
typedef OcamlGenericEnumCallbackCall = {
	final moduleId:String;
	final typeName:String;
	final fieldName:String;
	final receiver:TypedExpr;
	final callback:TypedExpr;
	final enumType:OcamlNativeEnumDescriptor;
	final conversion:OcamlGenericValueConversion;
};

/**
	Selects a direct generic class method whose sole argument maps T to T.

	The class instantiation must bind T to one ordinary native enum. The method
	may invoke its callback repeatedly, but cannot store, return, reassign, or
	compare it. That restriction makes a native arrow adapter unobservable as a
	new function identity. Enum payloads keep their existing shared representation.
	Other callback layouts remain owned by their existing conversion boundaries.
**/
function select(expression:TypedExpr, context:CompilationContext):Null<OcamlGenericEnumCallbackCall> {
	return switch (expression.expr) {
		case TCall({expr: TField(receiver, FInstance(reference, parameters, fieldReference))}, [callback]):
			final owner = reference.get();
			final field = fieldReference.get();
			if (!context.virtualTypesComputed
				|| owner.params.length == 0
				|| owner.params.length != parameters.length
				|| owner.isExtern
				|| owner.isInterface
				|| owner.meta.has(":native")
				|| owner.superClass != null
				|| owner.interfaces.length != 0
				|| context.dispatchTypes.exists(owner.pack.concat([owner.name]).join("."))
				|| field.params.length != 0
				|| field.isExtern
				|| field.meta.has(":native")
				|| field.overloads.get().length != 0)
				return null;
			switch ([owner.kind, field.kind]) {
				case [KNormal, FMethod(MethNormal)]:
				case _: return null;
			}
			final declared = switch (TypeTools.follow(field.type)) {
				case TFun([{opt: false, t: type}], _): type;
				case _: return null;
			};
			final parameter = switch (TypeTools.follow(declared)) {
				case TFun([{opt: false, t: input}], output): final id = parameterId(input); id != null && id == parameterId(output) ? id : null;
				case _: null;
			};
			if (parameter == null)
				return null;
			var index = -1;
			for (candidate in 0...owner.params.length)
				if (parameterId(owner.params[candidate].t) == parameter)
					index = candidate;
			if (index < 0)
				return null;
			final descriptor = OcamlNativeEnumRepresentation.select(parameters[index], context);
			if (descriptor == null)
				return null;
			final receiverMatches = switch (TypeTools.follow(receiver.t)) {
				case TInst(receiverOwner, actualParameters)
					if (receiverOwner.get().module == owner.module
						&& receiverOwner.get().name == owner.name
						&& actualParameters.length == owner.params.length): final actual = OcamlNativeEnumRepresentation.select(actualParameters[index],
						context); actual != null && actual.revision == descriptor.revision;
				case _: false;
			};
			if (!receiverMatches)
				return null;
			final matches = switch (TypeTools.follow(callback.t)) {
				case TFun([{opt: false, t: input}], output):
					final inputEnum = OcamlNativeEnumRepresentation.select(input, context);
					final outputEnum = OcamlNativeEnumRepresentation.select(output, context);
					inputEnum != null
					&& outputEnum != null
					&& inputEnum.revision == descriptor.revision
					&& outputEnum.revision == descriptor.revision;
				case _: false;
			};
			if (!matches || !onlyInvoked(field.expr()))
				return null;
			{
				moduleId: owner.module,
				typeName: owner.name,
				fieldName: field.name,
				receiver: receiver,
				callback: callback,
				enumType: descriptor,
				conversion: AdaptFunction([UnboxValue], BoxValue)
			};
		case _: null;
	};
}

/** Reject every use that could expose an adapter's identity or replace its callback. */
private function onlyInvoked(expression:Null<TypedExpr>):Bool {
	if (expression == null)
		return false;
	return switch (expression.expr) {
		case TFunction({args: [argument], expr: body}):
			var safe = true;
			function visit(value:TypedExpr):Void {
				if (!safe)
					return;
				switch (value.expr) {
					case TCall({expr: TLocal(local)}, inputs) if (local.id == argument.v.id):
						for (input in inputs)
							visit(input);
					case TLocal(local) if (local.id == argument.v.id):
						safe = false;
					case _:
						TypedExprTools.iter(value, visit);
				}
			}
			visit(body);
			safe;
		case _: false;
	};
}
#end
