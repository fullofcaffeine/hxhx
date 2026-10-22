package backend.vm;

import backend.vm.NekoFieldCall.bind;

/** Bind only exact instance-method value reads; function-valued fields retain ordinary field semantics. */
function render(context:NekoEmitContext, expression:HxExpr, emit:HxExpr->String):Null<String> {
	final occurrence = switch context.currentExecutable {
		case FunctionBody(fn): fn.body.findMethodUse(expression);
		case FieldInitializer(initializer): initializer.findMethodUse(expression);
		case null: null;
	};
	if (occurrence == null || occurrence.getUse() != ValueRead)
		return null;
	return switch expression {
		case EField(receiver, name): bind(context.typedProgram, emit(receiver), name);
		case _: throw "Neko method value lost its exact receiver selection";
	};
}
