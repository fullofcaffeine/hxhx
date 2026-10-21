package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;

/** One interface or method-only structural call/capture in a validated final root. */
typedef OcamlMethodDispatchUse = {
	final id:String;
	final binding:OcamlFunctionPlanBinding;
	final source:OcamlLoweredOrigin.OcamlLoweredSourceSpan;
	final receiver:TypedExpr;
	final contract:Null<ClassType>;
	final receiverType:String;
	final field:ClassField;
	final fieldType:String;
	final arguments:Null<Array<TypedExpr>>;
}

/**
	Retains exact expression identities from a final function or standalone root.

	Nested functions remain in their root's lookup, so captures cannot lose their
	permission when the builder enters a nested body. Direct calls own one lookup;
	their callee is not also counted as a captured method value. Ordinary generic
	IMap operations retain their existing specialized owner.
**/
class OcamlMethodDispatchRootPlan {
	final uses:ObjectMap<TypedExpr, OcamlMethodDispatchUse> = new ObjectMap();
	final binding:OcamlFunctionPlanBinding;

	public final views:OcamlMethodViewConversionPlan;

	var ordinal:Int = 0;

	public function new(expression:TypedExpr, binding:OcamlFunctionPlanBinding, ?result:Type, ?expected:Type,
			?progress:reflaxe.ocaml.lowered.OcamlFunctionPreparationTelemetry.OcamlFunctionSyntaxPhase->Void) {
		this.binding = binding;
		if (progress != null)
			progress(MethodViews);
		views = new OcamlMethodViewConversionPlan(expression, expected, result);
		if (progress != null)
			progress(MethodOccurrences);
		visit(expression);
	}

	/** Rechecks the selected receiver, declaration, and arguments before materialization. */
	public function useFor(expression:TypedExpr):Null<OcamlMethodDispatchUse> {
		final use = uses.get(expression);
		if (use == null)
			return null;
		final selected = occurrence(expression);
		if (selected == null
			|| selected.receiver != use.receiver
			|| contractId(selected.contract) != contractId(use.contract)
			|| TypeTools.toString(selected.receiver.t) != use.receiverType
			|| selected.field.name != use.field.name
			|| TypeTools.toString(selected.field.type) != use.fieldType
			|| (selected.arguments == null) != (use.arguments == null))
			throw "reflaxe.ocaml [ocaml-method-dispatch:changed-use]: final method occurrence changed";
		if (selected.arguments != null && use.arguments != null) {
			if (selected.arguments.length != use.arguments.length)
				throw "reflaxe.ocaml [ocaml-method-dispatch:changed-use]: final method arity changed";
			for (index in 0...selected.arguments.length)
				if (selected.arguments[index] != use.arguments[index])
					throw "reflaxe.ocaml [ocaml-method-dispatch:changed-use]: final argument changed";
		}
		return use;
	}

	function visit(expression:TypedExpr):Void {
		final selected = occurrence(expression);
		if (selected != null) {
			uses.set(expression, {
				id: binding.functionId + ":interface-method:" + ordinal++,
				binding: binding,
				source: OcamlLoweredOrigin.sourceSpan(expression.pos),
				receiver: selected.receiver,
				contract: selected.contract,
				receiverType: TypeTools.toString(selected.receiver.t),
				field: selected.field,
				fieldType: TypeTools.toString(selected.field.type),
				arguments: selected.arguments == null ? null : selected.arguments.copy()
			});
			visit(selected.receiver);
			if (selected.arguments != null)
				for (argument in selected.arguments)
					visit(argument);
			return;
		}
		TypedExprTools.iter(expression, visit);
	}

	/**
		Recognizes method calls and captures; native signature selection is separate.

		Ordinary data fields, including function-valued fields, cannot select this
		dispatch path. Reject them before inspecting a potentially large receiver type.
	**/
	public static function occurrence(expression:TypedExpr):Null<{
		receiver:TypedExpr,
		contract:Null<ClassType>,
		field:ClassField,
		arguments:Null<Array<TypedExpr>>
	}> {
		var callee = expression;
		var arguments:Null<Array<TypedExpr>> = null;
		switch (expression.expr) {
			case TCall(target, values):
				callee = target;
				arguments = values;
			case TField(_, _):
			case _:
				return null;
		}
		var unwrapping = true;
		while (unwrapping)
			switch (callee.expr) {
				case TParenthesis(inner) | TMeta(_, inner):
					callee = inner;
				case _:
					unwrapping = false;
			}
		return switch (callee.expr) {
			case TField(receiver, access):
				final field = switch (access) {
					case FInstance(_, _, field) | FClosure(_, field) | FAnon(field): field.get();
					case _: null;
				};
				if (field == null)
					return null;
				switch (field.kind) {
					case FMethod(_):
					case _: return null;
				}
				final contract = interfaceClass(receiver.t);
				final structural = contract == null && OcamlMethodViewConversionPlan.methodFields(receiver.t) != null;
				if (!structural && contract == null) null else {
					receiver: receiver,
					contract: contract,
					field: field,
					arguments: arguments
				};
			case _: null;
		};
	}

	/** Foreign interfaces and the standard IMap carrier have separate owners. */
	public static function interfaceClass(type:Type):Null<ClassType> {
		return switch (TypeTools.follow(type)) {
			case TAbstract(reference, [inner]) if (reference.get().pack.length == 0 && reference.get().name == "Null"): interfaceClass(inner);
			case TInst(reference, _):
				final owner = reference.get();
				!owner.isInterface
				|| owner.isExtern
				|| owner.meta.has(":native")
				|| OcamlStandardIMapCallContract.isIMapClass(owner) ? null : owner;
			case _: null;
		};
	}

	public static function fullName(owner:ClassType):String
		return owner.pack.concat([owner.name]).join(".");

	static function contractId(owner:Null<ClassType>):String
		return owner == null ? "structural" : fullName(owner);
}
#end
