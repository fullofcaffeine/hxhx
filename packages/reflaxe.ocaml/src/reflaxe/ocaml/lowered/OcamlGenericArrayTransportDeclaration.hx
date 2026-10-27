package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlGenericTransportDeclaration.parameterId;

/**
	A request-local selection of one static helper that reads a generic array through a callback.

	The helper's only generic input is a required zero-argument callback that
	returns `Array<T>`. Its result and every other argument are concrete. Local
	IDs refer to the exact typed function that was selected. The function-plan
	owner must check the final body again before emitting syntax.

	This selection proves source uses only. It lets the declaration export one
	OCaml type variable for the array element. It does not select a caller's
	array representation, change array storage, or authorize other generic shapes.
**/
typedef OcamlGenericArrayTransportDeclaration = {
	final parameterId:String;
	final callbackIndex:Int;
	final callbackLocalId:Int;
	final carrierLocalIds:Array<Int>;
};

/**
	Selects static helpers whose generic elements only move through checked array reads.

	What: a helper such as `unchanged<T>(read:() -> Array<T>):() -> Bool` can
	save a copy of the callback's array and compare its elements later, including
	inside a returned closure.

	Why: OCaml needs an explicit declaration signature for functions in a
	recursive module group. A type variable is only sound when every generic
	value in the body is proved to stay inside the same array element slot.

	How: the body may call the callback, copy the returned array, read its
	length, read elements by Int index, bind immutable locals, and compare two
	elements of the owned type with `==` or `!=`. Nested functions may capture
	those locals because each use is still one of these forms. Any other use of
	a generic value rejects the declaration, which then keeps its existing
	convention.
**/
function select(owner:ClassType, field:ClassField):Null<OcamlGenericArrayTransportDeclaration> {
	final expression = field.expr();
	if (expression == null)
		return null;
	return switch (unwrap(expression).expr) {
		case TFunction(body): selectFunction(owner, field, body);
		case _: null;
	};
}

/** Rechecks the same source contract after Reflaxe has finalized the function body. */
function selectFunction(owner:ClassType, field:ClassField, functionBody:TFunc):Null<OcamlGenericArrayTransportDeclaration> {
	if (owner.isExtern || owner.isInterface || owner.params.length != 0 || owner.meta.has(":native") || field.isExtern || field.meta.has(":native")
		|| field.meta.has(":generic") || field.params.length != 1 || field.overloads.get().length != 0)
		return null;
	switch ([owner.kind, field.kind]) {
		case [KModuleFields(_) | KNormal, FMethod(MethNormal)]:
		case _:
			return null;
	}
	final parameter = unconstrainedParameterId(field.params[0].t);
	if (parameter == null)
		return null;
	final signature = switch (TypeTools.follow(field.type)) {
		case TFun(arguments, result) if (!containsParameter(result, parameter)): arguments;
		case _: return null;
	};
	if (signature.length != functionBody.args.length)
		return null;
	var callbackIndex = -1;
	for (index in 0...signature.length) {
		final argument = signature[index];
		if (argument.opt || functionBody.args[index].value != null)
			return null;
		final isCallback = switch (TypeTools.follow(argument.t)) {
			case TFun([], result): arrayElementParameterId(result) == parameter;
			case _: false;
		};
		if (isCallback) {
			if (callbackIndex != -1)
				return null;
			callbackIndex = index;
		} else if (containsParameter(argument.t, parameter)) {
			return null;
		}
	}
	if (callbackIndex < 0)
		return null;
	return selectBody(functionBody, parameter, callbackIndex);
}

/**
	Returns the owned parameter when this exact type is the standard `Array<T>`.

	The function-plan owner uses the same check to give the array carrier the
	declaration's type variable. Typedef aliases follow to the same class.
**/
function arrayElementParameterId(type:Type):Null<String> {
	return switch (TypeTools.follow(type)) {
		case TInst(reference, [element]) if (isStandardArrayClass(reference.get())): parameterId(element);
		case _: null;
	};
}

/** Admits only array reads, copies, lengths, immutable bindings, and owned-element comparisons. */
private function selectBody(body:TFunc, parameter:String, callbackIndex:Int):Null<OcamlGenericArrayTransportDeclaration> {
	final callbackId = body.args[callbackIndex].v.id;
	final carriers:Map<Int, Bool> = [];
	var safe = true;
	function isOwnedArray(type:Type):Bool {
		return arrayElementParameterId(type) == parameter;
	}
	function isOwnedElement(type:Type):Bool {
		return parameterId(type) == parameter;
	}
	var visit:TypedExpr->Void = null;
	// A value of type Array<T> or T must come from one of these exact forms.
	function admitted(expression:TypedExpr):Bool {
		final inner = unwrap(expression);
		return switch (inner.expr) {
			case TLocal(local): carriers.exists(local.id);
			case TCall(callee, []) if (isOwnedArray(inner.t)):
				switch (unwrap(callee).expr) {
					case TLocal(local) if (local.id == callbackId): true;
					case TField(receiver, FInstance(owner, _, method)) if (isStandardArrayClass(owner.get()) && method.get().name == "copy"):
						isOwnedArray(receiver.t) && admitted(receiver);
					case _: false;
				}
			case TArray(receiver, index) if (isOwnedElement(inner.t)):
				if (!isOwnedArray(receiver.t) || !admitted(receiver) || containsParameter(index.t, parameter)) {
					false;
				} else {
					visit(index);
					safe;
				}
			case _: false;
		};
	}
	visit = function(expression:TypedExpr):Void {
		if (!safe)
			return;
		switch (expression.expr) {
			case TParenthesis(inner), TMeta(_, inner):
				visit(inner);
			case TVar(local, value) if (containsParameter(local.t, parameter)):
				if (value == null || !(isOwnedArray(local.t) || isOwnedElement(local.t)) || !admitted(value))
					safe = false;
				else
					carriers.set(local.id, true);
			case TField(receiver, FInstance(owner, _, field))
				if (isStandardArrayClass(owner.get()) && field.get().name == "length" && isOwnedArray(receiver.t)):
				if (!admitted(receiver))
					safe = false;
			case TBinop(OpEq | OpNotEq, left, right) if (isOwnedElement(left.t) && isOwnedElement(right.t)):
				if (!admitted(left) || !admitted(right))
					safe = false;
			case TFunction(nested):
				// Nested functions keep their own returns. They may read captured
				// carriers through the same admitted forms, but cannot take or
				// return a generic value themselves.
				for (argument in nested.args)
					if (containsParameter(argument.v.t, parameter))
						safe = false;
				if (containsParameter(nested.t, parameter))
					safe = false;
				visit(nested.expr);
			case TLocal(local) if (local.id == callbackId || carriers.exists(local.id)):
				// A bare use outside an admitted form could escape the array slot.
				safe = false;
			case _:
				if (containsParameter(expression.t, parameter))
					safe = false;
				else
					TypedExprTools.iter(expression, visit);
		}
	};
	visit(body.expr);
	if (!safe)
		return null;
	final carrierIds = [for (id in carriers.keys()) id];
	carrierIds.sort((left, right) -> left - right);
	return {
		parameterId: parameter,
		callbackIndex: callbackIndex,
		callbackLocalId: callbackId,
		carrierLocalIds: carrierIds
	};
}

private function isStandardArrayClass(definition:ClassType):Bool {
	return definition.pack.length == 0 && definition.module == "Array" && definition.name == "Array";
}

private function unconstrainedParameterId(type:Type):Null<String> {
	return switch (TypeTools.follow(type)) {
		case TInst(reference, []):
			switch (reference.get().kind) {
				case KTypeParameter([]): parameterId(type);
				case _: null;
			}
		case _: null;
	};
}

/** Composite types containing the parameter cannot cross unproved storage. */
private function containsParameter(type:Type, parameter:String, depth:Int = 0):Bool {
	if (depth > 64)
		return true;
	if (parameterId(type) == parameter)
		return true;
	return switch (TypeTools.follow(type)) {
		case TFun(arguments, result): containsParameter(result, parameter,
				depth + 1) || Lambda.exists(arguments, argument -> containsParameter(argument.t, parameter, depth + 1));
		case TInst(_, parameters), TEnum(_, parameters), TAbstract(_, parameters):
			Lambda.exists(parameters, item -> containsParameter(item, parameter, depth + 1));
		case TAnonymous(reference): Lambda.exists(reference.get().fields, field -> containsParameter(field.type, parameter, depth + 1));
		case TDynamic(inner): inner != null && containsParameter(inner, parameter, depth + 1);
		case _: false;
	};
}

private function unwrap(expression:TypedExpr):TypedExpr {
	return switch (expression.expr) {
		case TParenthesis(inner), TMeta(_, inner): unwrap(inner);
		case _: expression;
	};
}
#end
