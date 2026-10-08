package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;

/**
	A candidate method whose callback uses stay within the supplied typed program.

	This is pre-emission selection, not permission to change a calling convention.
	The declaration catalog and final-body sealer must still agree on each
	parameter, result, local, and source occurrence before syntax consumes a view.
**/
typedef OcamlCallableMethodSelection = {
	final calleeId:String;
	final fieldName:String;
	final signature:OcamlGenericValueShape;
};

/** Host objects remain private to the typed-program scan and never enter a stored plan. */
private typedef Candidate = {
	final id:String;
	final fieldName:String;
	final body:TFunc;
	final signature:Null<OcamlGenericValueShape>;
	final dependencies:Array<String>;
	var rejected:Bool;
	var usesViews:Bool;
};

/**
	Selects connected ordinary static methods before any callback ABI can change.

	A callback can be created, aliased, called, compared, passed, or returned only
	through known typed uses. A method with callback parameters or results joins
	its consumers in one component. An unsupported use rejects the entire
	component, including callers discovered before the rejected declaration.
	Nested functions may capture scalar values, but callback captures, mutation,
	containers, erasure, foreign methods, and reflective access need other plans.
	A runtime class value without an exact owner rejects all higher-order
	declaration changes until runtime registry consumers have their own plans.
	Selection is request-local and does not retain host objects in its result.
**/
function select(classes:Array<ClassType>):Array<OcamlCallableMethodSelection> {
	final candidates:Map<String, Candidate> = [];
	var hasUnresolvedClassValue = false;
	function collect(owner:ClassType, field:ClassField, isStatic:Bool):Void {
		final expression = field.expr();
		if (expression == null)
			return;
		final normalOwner = switch (owner.kind) {
			case KNormal: true;
			case _: false;
		};
		final normalMethod = switch (field.kind) {
			case FMethod(MethNormal): true;
			case _: false;
		};
		final eligible = isStatic && normalOwner && normalMethod && !owner.isExtern && !owner.isInterface && owner.params.length == 0
			&& !owner.meta.has(":native") && !field.isExtern && field.params.length == 0 && field.overloads.get().length == 0 && !field.meta.has(":native");
		final body:TFunc = switch (unwrap(expression).expr) {
			case TFunction(functionBody): functionBody;
			case _: {args: [], t: expression.t, expr: expression};
		};
		final declarationId = OcamlCallPlanner.calleeId(owner, field);
		final id = eligible ? declarationId : "callback-observer:" + (isStatic ? "static:" : "instance:") + declarationId;
		if (candidates.exists(id))
			throw "reflaxe.ocaml [callback-program:duplicate-method]: typed declaration occurs twice";
		candidates.set(id, {
			id: id,
			fieldName: field.name,
			body: body,
			signature: callableShape(field.type),
			dependencies: [],
			rejected: !eligible,
			usesViews: false
		});
	}
	for (owner in classes) {
		for (field in owner.statics.get())
			collect(owner, field, true);
		for (field in owner.fields.get())
			collect(owner, field, false);
		if (owner.constructor != null)
			collect(owner, owner.constructor.get(), false);
		// Haxe keeps __init__ outside statics. It can consume callback factories
		// before ordinary code runs, so its dependencies must reject ABI changes
		// just like unsupported static-field and constructor consumers do.
		if (owner.init != null) {
			final id = "callback-class-initializer:" + owner.module + ":" + owner.name;
			candidates.set(id, {
				id: id,
				fieldName: "__init__",
				body: {args: [], t: owner.init.t, expr: owner.init},
				signature: null,
				dependencies: [],
				rejected: true,
				usesViews: false
			});
		}
	}
	function connect(candidate:Candidate, id:String):Void {
		final other = candidates.get(id);
		if (other == null) {
			candidate.rejected = true;
			return;
		}
		if (!candidate.dependencies.contains(id))
			candidate.dependencies.push(id);
		if (!other.dependencies.contains(candidate.id))
			other.dependencies.push(candidate.id);
	}
	for (candidate in candidates) {
		function method(expression:TypedExpr):Null<String> {
			return switch (reflaxe.ocaml.lowered.OcamlCallableOrigin.classify(unwrap(expression))) {
				case StaticDeclaration(id): id;
				case _: null;
			};
		}
		function scan(body:TFunc):Void {
			final locals:Map<Int, OcamlGenericValueShape> = [];
			for (argument in body.args)
				if (isFunction(argument.v.t)) {
					candidate.usesViews = true;
					final shape = callableShape(argument.v.t);
					if (shape == null || argument.value != null)
						candidate.rejected = true;
					else
						locals.set(argument.v.id, shape);
				}
			final resultType = body.t;
			if (isFunction(resultType))
				candidate.usesViews = true;
			var visit:TypedExpr->Void = null;
			var value:(TypedExpr, Null<OcamlGenericValueShape>) -> Void = null;
			function call(expression:TypedExpr, callee:TypedExpr, arguments:Array<TypedExpr>):Void {
				final signature = TypeTools.follow(callee.t);
				switch (signature) {
					case TFun(parameters, result):
						final callbackBoundary = isFunction(result) || Lambda.exists(parameters, parameter -> isFunction(parameter.t));
						final target = method(callee);
						if (target != null) {
							if (callbackBoundary)
								connect(candidate, target);
						} else if (isLocalOrLiteral(callee)) {
							value(callee, callableShape(callee.t));
						} else {
							if (callbackBoundary)
								candidate.rejected = true;
							// Inspect a foreign receiver for callback reads without treating
							// an ordinary direct method itself as a stored callback value.
							switch (unwrap(callee).expr) {
								case TField({expr: TTypeExpr(_)}, FStatic(_, _)):
								case TField(receiver, _): visit(receiver);
								case _: visit(callee);
							}
						}
						if (callbackBoundary && (arguments.length != parameters.length || callableShape(callee.t) == null))
							candidate.rejected = true;
						for (index in 0...arguments.length) {
							final argument = arguments[index];
							if (isFunction(argument.t) || (index < parameters.length && isFunction(parameters[index].t)))
								value(argument, index < parameters.length ? callableShape(parameters[index].t) : null);
							else
								visit(argument);
						}
					case _:
						visit(callee);
						for (argument in arguments)
							visit(argument);
				}
			}
			value = (expression, expected) -> {
				candidate.usesViews = true;
				final shape = callableShape(expression.t);
				if (shape == null || expected == null || crossing(shape, expected) == null)
					candidate.rejected = true;
				switch (unwrap(expression).expr) {
					case TLocal(local):
						if (!locals.exists(local.id)) candidate.rejected = true;
					case TFunction(nested): scan(nested);
					case TCall(callee, arguments): call(expression, callee, arguments);
					case TField(_, _):
						final target = method(expression);
						if (target == null) {
							candidate.rejected = true;
							TypedExprTools.iter(expression, visit);
						} else if (needsBoundary(shape)) connect(candidate, target);
					case _:
						candidate.rejected = true;
						TypedExprTools.iter(expression, visit);
				}
			};
			visit = expression -> {
				final current = unwrap(expression);
				// A runtime Class value has no exact declaration receiver. The
				// registry can expose any supplied class, so no higher-order
				// declaration has a closed consumer set in this program yet.
				final exactClass = switch (current.expr) {
					case TTypeExpr(TClassDecl(_)): true;
					case _: false;
				};
				if (!exactClass && isClassValue(current.t)) {
					candidate.rejected = true;
					hasUnresolvedClassValue = true;
				}
				// An unclaimed function-valued expression is an escape. Continue
				// scanning it so its declaration also joins the rejected component.
				if (isFunction(current.t))
					candidate.rejected = true;
				switch (current.expr) {
					case TVar(local, initializer) if (isFunction(local.t)):
						final shape = callableShape(local.t);
						if (shape == null || initializer == null) {
							candidate.rejected = true;
							if (initializer != null)
								visit(initializer);
						} else {
							value(initializer, shape);
							locals.set(local.id, shape);
						}
					case TReturn(returned) if (returned != null && isFunction(resultType)):
						value(returned, callableShape(resultType));
					case TCall(callee, arguments): call(current, callee, arguments);
					case TBinop(OpEq | OpNotEq, left, right) if (isFunction(left.t) || isFunction(right.t)):
						value(left, callableShape(left.t));
						value(right, callableShape(right.t));
					case TFunction(nested): scan(nested);
					case TField(_, _) if (needsBoundary(callableShape(current.t))):
						final target = method(current);
						if (target != null)
							connect(candidate, target);
						TypedExprTools.iter(current, visit);
					case TTypeExpr(TClassDecl(reference)):
						// A class value can expose static methods through reflection.
						// Direct static calls and admitted method values do not enter
						// this path: their exact receiver is consumed above.
						candidate.rejected = true;
						for (field in reference.get().statics.get()) {
							final id = OcamlCallPlanner.calleeId(reference.get(), field);
							if (candidates.exists(id) && needsBoundary(callableShape(field.type)))
								connect(candidate, id);
						}
					case _: TypedExprTools.iter(current, visit);
				}
			};
			visit(body.expr);
		}
		scan(candidate.body);
		if (candidate.usesViews && candidate.signature == null)
			candidate.rejected = true;
	}
	if (hasUnresolvedClassValue)
		for (candidate in candidates)
			if (needsBoundary(candidate.signature))
				candidate.rejected = true;
	final pending = [for (candidate in candidates) if (candidate.rejected) candidate.id];
	while (pending.length > 0) {
		final id = pending.pop();
		if (id == null)
			break;
		final candidate = candidates.get(id);
		if (candidate == null)
			throw "reflaxe.ocaml [callback-program:missing-method]: rejection lost its typed declaration";
		for (dependency in candidate.dependencies) {
			final other = candidates.get(dependency);
			if (other != null && !other.rejected) {
				other.rejected = true;
				pending.push(dependency);
			}
		}
	}
	final selected:Array<OcamlCallableMethodSelection> = [];
	for (candidate in candidates)
		if (candidate.usesViews && !candidate.rejected && candidate.signature != null)
			selected.push({calleeId: candidate.id, fieldName: candidate.fieldName, signature: candidate.signature});
	selected.sort((left, right) -> Reflect.compare(left.calleeId, right.calleeId));
	return selected;
}

private function unwrap(expression:TypedExpr):TypedExpr {
	return switch (expression.expr) {
		case TMeta(_, inner), TParenthesis(inner): unwrap(inner);
		case _: expression;
	};
}

private function isFunction(type:Type):Bool {
	return switch (TypeTools.follow(type)) {
		case TFun(_, _): true;
		case _: false;
	};
}

/** Runtime class references can expose methods even when their names come from strings. */
private function isClassValue(type:Type):Bool {
	return switch (TypeTools.follow(type)) {
		case TAbstract(reference, [_]): final declaration = reference.get(); declaration.pack.length == 0 && declaration.name == "Class" && declaration.meta.has(":coreType");
		case _: false;
	};
}

private function isLocalOrLiteral(expression:TypedExpr):Bool {
	return switch (unwrap(expression).expr) {
		case TLocal(_), TFunction(_), TCall(_, _): true;
		case _: false;
	};
}

private function needsBoundary(shape:Null<OcamlGenericValueShape>):Bool {
	function callback(value:OcamlGenericValueShape):Bool {
		return switch (value) {
			case FunctionValue(_, _): true;
			case _: false;
		};
	}
	return switch (shape) {
		case FunctionValue(arguments, result): callback(result) || Lambda.exists(arguments, callback);
		case _: false;
	};
}
#end
