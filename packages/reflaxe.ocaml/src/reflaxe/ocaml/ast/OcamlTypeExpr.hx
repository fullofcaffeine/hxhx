package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlTypeRecordField;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;

enum OcamlTypeExpr {
	/** A type identifier: `int`, `string`, `t`, `My_mod.t` */
	TIdent(name:String);

	/**
		A checked private-runtime type name.

		The reference proves which sealed compiler decision authorized the name.
		It does not contain Haxe type semantics or let the printer choose a type.
	**/
	TRuntimeIdent(reference:OcamlRuntimeReference);

	/** A checked private-runtime type constructor applied to ordinary type inputs. */
	TRuntimeApp(reference:OcamlRuntimeReference, params:Array<OcamlTypeExpr>);

	/** Type application: `'a list`, `(int, string) result` */
	TApp(name:String, params:Array<OcamlTypeExpr>);

	/** Function type: `a -> b` */
	TArrow(from:OcamlTypeExpr, to:OcamlTypeExpr);

	/** Tuple type: `a * b * c` */
	TTuple(items:Array<OcamlTypeExpr>);

	/** Type variable: `'a` */
	TVar(name:String);

	/** Record type: `{ mutable x : int; y : string }` */
	TRecord(fields:Array<OcamlTypeRecordField>);
}
