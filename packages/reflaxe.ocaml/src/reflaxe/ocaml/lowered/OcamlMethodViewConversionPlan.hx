package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlMethodDispatchSignature.hasClosedDispatchSourceType;

/** An exact final expression that preserves a class object under a method-only view. */
typedef OcamlMethodViewConversion = {
	final source:ClassType;
	final sourceType:String;
	final targetType:String;
	final fields:Array<ClassField>;
}

/**
	Finds contextual class-to-method-view conversions before target syntax.

	An anonymous type containing only required methods can retain the original
	class object. Ordinary anonymous literals still use their existing table.
	The consumer checks either representation before binding a method. This plan
	does not admit data properties, optional methods, or foreign class layouts.
**/
class OcamlMethodViewConversionPlan {
	final conversions:ObjectMap<TypedExpr, Map<String, OcamlMethodViewConversion>> = new ObjectMap();

	public function new(expression:TypedExpr, expected:Null<Type>, result:Null<Type>) {
		visit(expression, expected, result, (value, conversion) -> {
			var targets = conversions.get(value);
			if (targets == null) {
				targets = [];
				conversions.set(value, targets);
			}
			targets.set(conversion.targetType, conversion);
		});
	}

	/** Rejects a new or changed conversion instead of silently choosing a layout. */
	public function requireConversion(value:TypedExpr, target:Type):OcamlMethodViewConversion {
		final targets = conversions.get(value);
		final planned = targets == null ? null : targets.get(TypeTools.toString(target));
		final selected = select(value, target);
		if (planned == null
			|| selected == null
			|| planned.sourceType != selected.sourceType
			|| planned.source.module != selected.source.module
			|| planned.source.name != selected.source.name
			|| planned.targetType != selected.targetType)
			throw "reflaxe.ocaml [ocaml-method-view:missing-conversion]: final source and destination lack a matching method-view plan";
		return planned;
	}

	/** Uses typed assignment contexts; object and array elements inherit their expected type. */
	public static function visit(expression:TypedExpr, expected:Null<Type>, result:Null<Type>, accept:TypedExpr->OcamlMethodViewConversion->Void):Void {
		final target = expected ?? expression.t;
		final conversion = select(expression, target);
		if (conversion != null)
			accept(expression, conversion);
		function child(value:TypedExpr, ?type:Type):Void
			visit(value, type, result, accept);
		switch (expression.expr) {
			case TFunction(functionValue):
				visit(functionValue.expr, null, functionValue.t, accept);
			case TVar(variable, initializer):
				if (initializer != null)
					child(initializer, variable.t);
			case TReturn(value):
				if (value != null)
					child(value, result);
			case TBinop(OpAssign, left, right):
				child(left);
				child(right, left.t);
			case TCall(callee, arguments):
				child(callee);
				final parameters = switch (TypeTools.follow(callee.t)) {
					case TFun(parameters, _): parameters;
					case _: [];
				};
				for (index in 0...arguments.length)
					child(arguments[index], index < parameters.length ? parameters[index].t : null);
			case TNew(reference, parameters, arguments):
				final owner = reference.get();
				final constructor = owner.constructor;
				final argumentsType = constructor == null ? null : TypeTools.applyTypeParameters(constructor.get().type, owner.params, parameters);
				final callParameters = argumentsType == null ? [] : switch (TypeTools.follow(argumentsType)) {
					case TFun(parameters, _): parameters;
					case _: [];
				};
				for (index in 0...arguments.length)
					child(arguments[index], index < callParameters.length ? callParameters[index].t : null);
			case TObjectDecl(fields):
				final declarations = switch (TypeTools.follow(target)) {
					case TAnonymous(reference): reference.get().fields;
					case _: [];
				};
				for (field in fields) {
					final declaration = Lambda.find(declarations, declaration -> declaration.name == field.name);
					child(field.expr, declaration == null ? null : declaration.type);
				}
			case TArrayDecl(values):
				final element = switch (TypeTools.follow(target)) {
					case TInst(reference, [element]) if (reference.get().module == "Array" && reference.get().name == "Array"): element;
					case _: null;
				};
				for (value in values)
					child(value, element);
			case TBlock(values):
				for (index in 0...values.length)
					child(values[index], index == values.length - 1 ? expected : null);
			case TIf(condition, whenTrue, whenFalse):
				child(condition);
				child(whenTrue, target);
				if (whenFalse != null)
					child(whenFalse, target);
			case TSwitch(value, cases, otherwise):
				child(value);
				for (arm in cases) {
					for (value in arm.values)
						child(value);
					child(arm.expr, target);
				}
				if (otherwise != null)
					child(otherwise, target);
			case TTry(body, catches):
				child(body, target);
				for (clause in catches)
					child(clause.expr, target);
			case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
				child(inner, target);
			case _:
				TypedExprTools.iter(expression, value -> child(value));
		}
	}

	/** Closed method-only shapes have no data fields whose access could assume a table. */
	public static function methodFields(type:Type):Null<Array<ClassField>> {
		return switch (TypeTools.follow(type)) {
			case TAnonymous(reference):
				final definition = reference.get();
				if (definition.status != AClosed || definition.fields.length == 0)
					return null;
				for (field in definition.fields) {
					if (field.meta.has(":optional") || field.meta.has(":native") || field.params.length != 0 || field.overloads.get().length != 0)
						return null;
					switch (field.kind) {
						case FMethod(MethNormal | MethInline):
						case _: return null;
					}
				}
				hasClosedDispatchSourceType(type) ? definition.fields.copy() : null;
			case _: null;
		};
	}

	/** Explicit casts retain the declared source; contextual constructors retain their actual class. */
	public static function sourceClass(value:TypedExpr):Null<ClassType> {
		final source = switch (value.expr) {
			case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _): return sourceClass(inner);
			case TNew(reference, parameters, _): TInst(reference, parameters);
			case _: value.t;
		};
		return ordinaryClass(source);
	}

	private static function ordinaryClass(source:Type):Null<ClassType> {
		return switch (TypeTools.follow(source)) {
			case TAbstract(reference, [inner]) if (reference.get().pack.length == 0 && reference.get().name == "Null"): ordinaryClass(inner);
			case TInst(reference, []) if (!reference.get().isExtern && reference.get().params.length == 0 && !reference.get().meta.has(":native")):
				final owner = reference.get();
				switch (owner.kind) {
					case KNormal: owner;
					case _: null;
				}
			case _: null;
		};
	}

	public static function select(value:TypedExpr, target:Type):Null<OcamlMethodViewConversion> {
		final fields = methodFields(target);
		final source = fields == null ? null : sourceClass(value);
		return source == null || fields == null ? null : {
			source: source,
			sourceType: TypeTools.toString(value.t),
			targetType: TypeTools.toString(target),
			fields: fields
		};
	}
}
#end
