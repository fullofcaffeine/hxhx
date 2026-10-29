package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlGenericArrayTransportDeclaration;
import reflaxe.ocaml.lowered.OcamlGenericArrayTransportDeclaration.select as selectArrayDeclaration;
import reflaxe.ocaml.lowered.OcamlGenericArrayTransportDeclaration.selectFunction as selectArrayFunction;
import reflaxe.ocaml.lowered.OcamlGenericTransportDeclaration.select as selectDeclaration;
import reflaxe.ocaml.lowered.OcamlGenericTransportDeclaration.selectFunction;

/**
	The closed set of generic declaration shapes that may export an OCaml type variable.

	Each kind keeps its own source proof. `CallbackResult` forwards a callback's
	value unchanged. `ArrayElement` reads a callback's `Array<T>` through checked
	array operations and returns a concrete value.
**/
enum OcamlGenericTransportKind {
	CallbackResult(declaration:OcamlGenericTransportDeclaration);
	ArrayElement(declaration:OcamlGenericArrayTransportDeclaration);
}

/** One direct call retains the declaration's callback position and concrete arguments. */
typedef OcamlGenericTransportCall = {
	final calleeId:String;
	final callbackIndex:Int;
	final argumentTypes:Array<Type>;
}

/**
	Request-local inputs sealed with one ordinary function's final body revision.

	Calls inside nested functions use the root's exact expression lookup. The
	declaration applies only to the root; nested functions have their own results.
**/
typedef OcamlGenericTransportFunction = {
	final declaration:Null<OcamlGenericTransportKind>;
	final calls:ObjectMap<TypedExpr, OcamlGenericTransportCall>;
}

/**
	Keeps generic callback values polymorphic across a closed set of direct calls.

	Selection precedes module emission. First-class uses and calls outside ordinary
	function bodies retain the existing convention. Each selected definition is
	checked again after preprocessing, and every emitted call requires that final
	definition before files can be published. No compiler objects survive a request.
**/
class OcamlGenericTransportProgram {
	final declarations:Map<String, OcamlGenericTransportKind> = [];
	final definitions:Map<String, Bool> = [];
	final used:Map<String, Bool> = [];

	public function new() {}

	/** Builds the complete declaration/use catalog before the first caller is emitted. */
	public function select(classes:Array<ClassType>):Void {
		declarations.clear();
		definitions.clear();
		used.clear();
		for (owner in classes)
			for (field in owner.statics.get()) {
				final selected = selectKind(owner, field);
				if (selected != null)
					declarations.set(OcamlCallPlanner.calleeId(owner, field), selected);
			}
		final rejected:Map<String, Bool> = [];
		function visit(expression:TypedExpr, insideFunction:Bool):Void {
			switch (expression.expr) {
				case TFunction(body):
					visit(body.expr, true);
				case TCall(callee, arguments):
					final id = calleeId(callee);
					final selected = id == null ? null : declarations.get(id);
					if (selected == null) {
						visit(callee, insideFunction);
					} else if (!insideFunction || callFor(selected, id, callee, arguments) == null) {
						rejected.set(id, true);
					}
					for (argument in arguments)
						visit(argument, insideFunction);
				case TField(_, FStatic(_, _)):
					final id = calleeId(expression);
					if (id != null && declarations.exists(id))
						rejected.set(id, true);
				case _:
					TypedExprTools.iter(expression, child -> visit(child, insideFunction));
			}
		}
		for (owner in classes) {
			final fields = owner.statics.get().concat(owner.fields.get());
			if (owner.constructor != null)
				fields.push(owner.constructor.get());
			for (field in fields) {
				final expression = field.expr();
				if (expression != null)
					visit(expression, false);
			}
			if (owner.init != null)
				visit(owner.init, false);
		}
		for (id in rejected.keys())
			declarations.remove(id);
	}

	/** Binds declaration and call evidence to the exact final body stored by the registry. */
	public function plan(data:ClassFuncData):OcamlGenericTransportFunction {
		final id = OcamlCallPlanner.calleeId(data.classType, data.field);
		final selected = declarations.get(id);
		var finalDeclaration:Null<OcamlGenericTransportKind> = null;
		if (selected != null) {
			if (data.expr == null || data.tfunc == null)
				throw 'reflaxe.ocaml [ocaml-generic-transport:missing-body]: $id';
			final finalBody:TFunc = {
				args: data.tfunc.args,
				t: data.tfunc.t,
				expr: data.expr
			};
			finalDeclaration = switch (selected) {
				case CallbackResult(original):
					final checked = selectFunction(data.classType, data.field, finalBody);
					if (checked == null || checked.parameterId != original.parameterId || checked.callbackIndex != original.callbackIndex)
						throw 'reflaxe.ocaml [ocaml-generic-transport:changed-body]: $id no longer forwards its callback result';
					CallbackResult(checked);
				case ArrayElement(original):
					final checked = selectArrayFunction(data.classType, data.field, finalBody);
					if (checked == null || checked.parameterId != original.parameterId || checked.callbackIndex != original.callbackIndex)
						throw 'reflaxe.ocaml [ocaml-generic-transport:changed-body]: $id no longer keeps its array elements in checked reads';
					ArrayElement(checked);
			};
			definitions.set(id, true);
		}
		final calls = new ObjectMap<TypedExpr, OcamlGenericTransportCall>();
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TCall(callee, arguments):
					final targetId = calleeId(callee);
					final target = targetId == null ? null : declarations.get(targetId);
					if (target != null) {
						final call = callFor(target, targetId, callee, arguments);
						if (call == null)
							throw 'reflaxe.ocaml [ocaml-generic-transport:changed-call]: $targetId';
						calls.set(expression, call);
						used.set(targetId, true);
					} else {
						visit(callee);
					}
					for (argument in arguments)
						visit(argument);
				case TField(_, FStatic(_, _)):
					final targetId = calleeId(expression);
					if (targetId != null && declarations.exists(targetId))
						throw 'reflaxe.ocaml [ocaml-generic-transport:escaped-declaration]: $targetId';
				case _:
					TypedExprTools.iter(expression, visit);
			}
		}
		if (data.expr != null)
			visit(data.expr);
		return {declaration: finalDeclaration, calls: calls};
	}

	/** A caller cannot authorize an absent or differently preprocessed definition. */
	public function validate():Void {
		for (id in used.keys())
			if (!definitions.exists(id))
				throw 'reflaxe.ocaml [ocaml-generic-transport:missing-definition]: $id';
	}

	public function isSelectedCallee(expression:TypedExpr):Bool {
		final id = calleeId(expression);
		return id != null && declarations.exists(id);
	}

	/** The callback-result proof keeps priority; its selector rejects every array-element helper. */
	static function selectKind(owner:ClassType, field:ClassField):Null<OcamlGenericTransportKind> {
		final callbackResult = selectDeclaration(owner, field);
		if (callbackResult != null)
			return CallbackResult(callbackResult);
		final arrayElement = selectArrayDeclaration(owner, field);
		return arrayElement == null ? null : ArrayElement(arrayElement);
	}

	/** Both kinds pass exactly one zero-argument callback at a fixed argument position. */
	static function callbackIndexOf(selected:OcamlGenericTransportKind):Int {
		return switch (selected) {
			case CallbackResult(declaration): declaration.callbackIndex;
			case ArrayElement(declaration): declaration.callbackIndex;
		};
	}

	static function callFor(selected:OcamlGenericTransportKind, id:String, callee:TypedExpr, arguments:Array<TypedExpr>):Null<OcamlGenericTransportCall> {
		final callbackIndex = callbackIndexOf(selected);
		final parameters = switch (TypeTools.follow(callee.t)) {
			case TFun(parameters, _): parameters;
			case _: return null;
		};
		if (parameters.length != arguments.length || callbackIndex >= arguments.length)
			return null;
		final callback = unwrap(arguments[callbackIndex]);
		switch (callback.expr) {
			case TFunction(_), TLocal(_):
			case _:
				return null;
		}
		switch (TypeTools.follow(callback.t)) {
			case TFun([], _):
			case _:
				return null;
		}
		return {calleeId: id, callbackIndex: callbackIndex, argumentTypes: parameters.map(parameter -> parameter.t)};
	}

	static function calleeId(expression:TypedExpr):Null<String> {
		return switch (unwrap(expression).expr) {
			case TField(_, FStatic(owner, field)): OcamlCallPlanner.calleeId(owner.get(), field.get());
			case _: null;
		};
	}

	static function unwrap(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TParenthesis(inner), TMeta(_, inner): unwrap(inner);
			case _: expression;
		};
	}
}
#end
