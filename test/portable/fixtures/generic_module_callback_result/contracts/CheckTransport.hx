import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlGenericTransportDeclaration;
import reflaxe.ocaml.lowered.OcamlGenericTransportDeclaration.select as selectTransport;
import reflaxe.ocaml.lowered.OcamlGenericTransportDeclaration.selectFunction;

/** Checks independently authored forwarding and non-forwarding Haxe programs. */
class CheckTransport {
	public static function run():Void {
		final selections:Map<String, OcamlGenericTransportDeclaration> = [];
		for (type in Context.getModule("TransportCases")) {
			switch type {
				case TInst(reference, _):
					final owner = reference.get();
					for (field in owner.statics.get()) {
						final selected = selectTransport(owner, field);
						final expected = field.name == "restored" || field.name == "other";
						if ((selected != null) != expected)
							Context.fatalError("wrong forwarding admission for " + field.name, field.pos);
						if (selected != null)
							selections.set(field.name, selected);
						if (field.name == "other") {
							final body = switch (field.expr().expr) {
								case TFunction(body): body;
								case _: throw "missing typed function";
							};
							final nullValue:TypedExpr = {expr: TConst(TNull), t: body.t, pos: body.expr.pos};
							final changed:TypedExpr = {expr: TReturn(nullValue), t: body.expr.t, pos: body.expr.pos};
							if (selectFunction(owner, field, {args: body.args, t: body.t, expr: changed}) != null)
								Context.fatalError("a changed final body retained forwarding permission", field.pos);
						}
					}
				case _:
			}
		}
		if (!selections.exists("restored") || !selections.exists("other"))
			Context.fatalError("missing forwarding cases", Context.currentPos());
		if (selections.get("restored").parameterId == selections.get("other").parameterId)
			Context.fatalError("unrelated generic parameter scopes were merged", Context.currentPos());
		Sys.println("GENERIC_TRANSPORT_DECLARATION:PASS");
	}
}
