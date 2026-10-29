import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlGenericArrayTransportDeclaration;
import reflaxe.ocaml.lowered.OcamlGenericArrayTransportDeclaration.select as selectArray;
import reflaxe.ocaml.lowered.OcamlGenericArrayTransportDeclaration.selectFunction;
import reflaxe.ocaml.lowered.OcamlGenericTransportDeclaration.select as selectForwarding;

/** Checks the array-element rule against admitted and rejected Haxe helpers. */
class CheckArrayTransport {
	static final admitted = ["unchanged", "sameEnds"];

	public static function run():Void {
		final selections:Map<String, OcamlGenericArrayTransportDeclaration> = [];
		for (type in Context.getModule("ArrayCases")) {
			switch type {
				case TInst(reference, _):
					final owner = reference.get();
					for (field in owner.statics.get()) {
						final selected = selectArray(owner, field);
						if ((selected != null) != admitted.contains(field.name))
							Context.fatalError("wrong array-element admission for " + field.name, field.pos);
						if (selected != null) {
							selections.set(field.name, selected);
							if (selectForwarding(owner, field) != null)
								Context.fatalError("an array-element helper also received forwarding permission", field.pos);
							checkChangedBody(owner, field);
						}
					}
				case _:
			}
		}
		if (!selections.exists("unchanged") || !selections.exists("sameEnds"))
			Context.fatalError("missing array-element cases", Context.currentPos());
		if (selections.get("unchanged").parameterId == selections.get("sameEnds").parameterId)
			Context.fatalError("unrelated generic parameter scopes were merged", Context.currentPos());
		Sys.println("GENERIC_ARRAY_TRANSPORT_DECLARATION:PASS");
	}

	/** A final body that prints an owned element must lose its permission. */
	static function checkChangedBody(owner:ClassType, field:ClassField):Void {
		final body = switch (field.expr().expr) {
			case TFunction(body): body;
			case _: throw "missing typed function";
		};
		final read = body.args[0].v;
		final readType = read.t;
		final arrayType = switch (haxe.macro.TypeTools.follow(readType)) {
			case TFun(_, result): result;
			case _: throw "missing callback type";
		};
		final elementType = switch (haxe.macro.TypeTools.follow(arrayType)) {
			case TInst(_, [element]): element;
			case _: throw "missing array element";
		};
		final pos = body.expr.pos;
		final call:TypedExpr = {expr: TCall({expr: TLocal(read), t: readType, pos: pos}, []), t: arrayType, pos: pos};
		final element:TypedExpr = {expr: TArray(call, {expr: TConst(TInt(0)), t: Context.getType("Int"), pos: pos}), t: elementType, pos: pos};
		final trace:TypedExpr = {
			expr: TCall({expr: TIdent("trace"), t: Context.getType("Dynamic"), pos: pos}, [element]),
			t: Context.getType("Void"),
			pos: pos
		};
		final changed:TypedExpr = {expr: TBlock([trace, body.expr]), t: body.expr.t, pos: pos};
		if (selectFunction(owner, field, {args: body.args, t: body.t, expr: changed}) != null)
			Context.fatalError("a changed final body retained array-element permission", field.pos);
	}
}
