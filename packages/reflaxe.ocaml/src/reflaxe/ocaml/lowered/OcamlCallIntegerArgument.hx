package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/**
	Preserve Haxe's standard Int32-to-Int argument conversion during call planning.

	Haxe can retain `haxe.Int32` on an argument after accepting it for an `Int`
	parameter, for example an Int64 field passed to an ordinary method. The
	OCaml target stores both types as `int`, so that conversion preserves the
	existing value. An optional `Null<Int>` parameter then uses the ordinary
	integer boxing step. This proof applies only at the argument boundary;
	user abstracts, nullable inputs, results, and other destinations are excluded.
 */
function select(type:Type, destination:String, representations:OcamlRepresentationRegistry):Null<OcamlRepresentationDecision> {
	if (destination != "Int" && destination != "Null<Int>")
		return null;
	return switch (type) {
		case TAbstract(reference, parameters):
			final definition = reference.get();
			parameters.length == 0
			&& definition.module == "haxe.Int32"
			&& definition.pack.length == 1
			&& definition.pack[0] == "haxe"
			&& definition.name == "Int32" ? representations.selectExactInt(OcamlRepresentationDomain.InternalValue) : null;
		case _: null;
	};
}
#end
