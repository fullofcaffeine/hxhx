import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlGenericEnumCallbackCall.select;

/** Rejects callback identity exposure and inconsistent generic instantiations. */
class CheckGenericEnumCallback {
	public static function install():Void {
		Context.onAfterTyping(types -> {
			final context = new CompilationContext();
			context.virtualTypesComputed = true;
			var accepted = 0;
			var rejected = 0;
			for (type in types)
				switch (type) {
					case TClassDecl(reference) if (reference.get().name == "ContractCases"):
						for (field in reference.get().statics.get()) {
							final body = field.expr();
							if (body == null)
								continue;
							function visit(expression:TypedExpr):Void {
								switch (expression.expr) {
									case TCall(callee = {expr: TField(receiver, FInstance(owner, parameters, method))}, [argument])
										if (owner.get().name == "Generic"):
										final target = select(expression, context);
										final isEnum = switch (parameters[0]) {
											case TEnum(_, _): true;
											case _: false;
										};
										if (method.get().name == "invoke" && isEnum) {
											if (target == null)
												throw "valid enum callback was not selected";
											accepted++;
											context.virtualTypesComputed = false;
											if (select(expression, context) != null)
												throw "incomplete class hierarchy was accepted";
											context.virtualTypesComputed = true;
											rejected++;
											final alteredCallee:TypedExpr = {
												expr: TField(receiver, FInstance(owner, [Context.getType("ContractCases.Other")], method)),
												t: callee.t,
												pos: callee.pos
											};
											final altered:TypedExpr = {expr: TCall(alteredCallee, [argument]), t: expression.t, pos: expression.pos};
											if (select(altered, context) != null)
												throw "mismatched enum substitution was accepted";
											rejected++;
										} else {
											if (target != null)
												throw "unsupported or identity-exposing callback was accepted";
											rejected++;
										}
									case _:
								}
								TypedExprTools.iter(expression, visit);
							}
							visit(body);
						}
					case _:
				}
			if (accepted != 1 || rejected != 7)
				throw 'expected 1 accepted and 7 rejected calls, got $accepted/$rejected';
			Sys.println("GENERIC_CLASS_ENUM_CALLBACK_ADMISSION:PASS");
		});
	}
}
