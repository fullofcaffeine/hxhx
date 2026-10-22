package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;

/**
	A request-local selection of one callback-to-result forwarding declaration.

	Local IDs refer to this exact typed function. The function-plan owner must
	bind them to its final body before retaining a plan or emitting syntax.
	This selection proves source uses only. It does not select a caller's
	callback representation or authorize a native calling convention.
**/
typedef OcamlGenericTransportDeclaration = {
	final parameterId:String;
	final callbackIndex:Int;
	final callbackLocalId:Int;
	final aliasLocalIds:Array<Int>;
};

/**
	Selects module functions that return their callback's value without inspecting it.

	The single owned type parameter can pass from a required zero-argument
	callback through immutable local aliases and returns. Other concrete work,
	including restoration and exception handling, can surround that transport.
	A read in any other context rejects the declaration. This prevents a native
	polymorphic result from being confused with erased Haxe storage.
**/
function select(owner:ClassType, field:ClassField):Null<OcamlGenericTransportDeclaration> {
	final expression = field.expr();
	if (expression == null)
		return null;
	return switch (unwrap(expression).expr) {
		case TFunction(body): selectFunction(owner, field, body);
		case _: null;
	};
}

/** Rechecks the same source contract after Reflaxe has finalized the function body. */
function selectFunction(owner:ClassType, field:ClassField, functionBody:TFunc):Null<OcamlGenericTransportDeclaration> {
	if (owner.isExtern || owner.isInterface || owner.params.length != 0 || owner.meta.has(":native") || field.isExtern || field.meta.has(":native")
		|| field.params.length != 1 || field.overloads.get().length != 0)
		return null;
	switch ([owner.kind, field.kind]) {
		case [KModuleFields(_), FMethod(MethNormal)]:
		case _:
			return null;
	}
	final owned = field.params[0].t;
	final parameter = unconstrainedParameterId(owned);
	if (parameter == null)
		return null;
	final signature = switch (TypeTools.follow(field.type)) {
		case TFun(arguments, result) if (parameterId(result) == parameter): arguments;
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
			case TFun([], result): parameterId(result) == parameter;
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

/** Rejects every callback or transported-value use outside its owning return flow. */
private function selectBody(body:TFunc, parameter:String, callbackIndex:Int):Null<OcamlGenericTransportDeclaration> {
	final callbackId = body.args[callbackIndex].v.id;
	final aliases:Map<Int, Bool> = [];
	var safe = true;
	var returned = false;
	function transport(expression:TypedExpr):Bool {
		if (parameterId(expression.t) != parameter)
			return false;
		return switch (unwrap(expression).expr) {
			case TCall(callee, []):
				switch (unwrap(callee).expr) {
					case TLocal(local): local.id == callbackId;
					case _: false;
				}
			case TLocal(local): aliases.exists(local.id);
			case _: false;
		};
	}
	function visit(expression:TypedExpr, nested:Bool):Void {
		if (!safe)
			return;
		switch (expression.expr) {
			case TParenthesis(inner), TMeta(_, inner):
				visit(inner, nested);
			case TVar(local, value) if (parameterId(local.t) == parameter):
				if (nested || value == null || !transport(value))
					safe = false;
				else
					aliases.set(local.id, true);
			case TReturn(value) if (!nested):
				if (value == null || !transport(value))
					safe = false;
				else
					returned = true;
			case TFunction(functionBody):
				// A nested function has its own return owner. It cannot capture the
				// generic callback or aliases and silently create a second transport.
				visit(functionBody.expr, true);
			case TLocal(local) if (local.id == callbackId || aliases.exists(local.id)):
				safe = false;
			case _:
				if (containsParameter(expression.t, parameter))
					safe = false;
				else
					TypedExprTools.iter(expression, child -> visit(child, nested));
		}
	}
	visit(body.expr, false);
	if (!safe || !returned)
		return null;
	final aliasIds = [for (id in aliases.keys()) id];
	aliasIds.sort((left, right) -> left - right);
	return {
		parameterId: parameter,
		callbackIndex: callbackIndex,
		callbackLocalId: callbackId,
		aliasLocalIds: aliasIds
	};
}

/** The declaration scope distinguishes unrelated parameters that share a short name. */
function parameterId(type:Type):Null<String> {
	return switch (TypeTools.follow(type)) {
		case TInst(reference, []):
			final declaration = reference.get();
			switch (declaration.kind) {
				case KTypeParameter(_): [declaration.module, declaration.pack.join("."), declaration.name].join("|");
				case _: null;
			}
		case _: null;
	};
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

/** Composite types containing the parameter cannot cross unproved container storage. */
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
