package reflaxe.ocaml.ast;

/**
	A completed function and its represented callable type, when fully known.
	The signature comes from the same checked parameter and result selections as
	the expression. Absence means module planning cannot export this function yet.
**/
typedef OcamlBuiltFunction = {
	final expression:OcamlExpr;
	final signature:Null<OcamlTypeExpr>;
}

/** Combines explicit parameter annotations with an already selected result type. */
function signatureFromParameters(parameters:Array<OcamlPat>, result:OcamlTypeExpr):Null<OcamlTypeExpr> {
	if (parameters.length == 0)
		return null;
	final types:Array<OcamlTypeExpr> = [];
	for (parameter in parameters) {
		switch (parameter) {
			case PAnnot(_, type):
				types.push(type);
			case PConst(CUnit):
				types.push(OcamlTypeExpr.TIdent("unit"));
			case _:
				return null;
		}
	}
	var signature = result;
	var index = types.length;
	while (index > 0) {
		index -= 1;
		signature = OcamlTypeExpr.TArrow(types[index], signature);
	}
	return signature;
}
