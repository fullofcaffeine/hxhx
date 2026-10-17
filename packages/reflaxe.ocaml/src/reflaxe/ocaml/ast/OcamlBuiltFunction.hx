package reflaxe.ocaml.ast;

/**
	A completed function and its represented callable type, when fully known.
	The signature comes from checked callable selections or known declaration
	carriers. The recursive module interface checks the expression against that
	type. Absence means module planning cannot export this function yet.
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
	return signatureFromTypes(types, result);
}

/** Haxe functions without source parameters still take unit in generated OCaml. */
function signatureFromTypes(types:Array<OcamlTypeExpr>, result:OcamlTypeExpr):OcamlTypeExpr {
	if (types.length == 0)
		return OcamlTypeExpr.TArrow(OcamlTypeExpr.TIdent("unit"), result);
	var signature = result;
	var index = types.length;
	while (index > 0) {
		index -= 1;
		signature = OcamlTypeExpr.TArrow(types[index], signature);
	}
	return signature;
}
