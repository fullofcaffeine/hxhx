package backend.ocaml;

/**
	Choose the OCaml binding keyword for one projected local declaration.

	Why
	- Haxe puts a named local function (`function fact(n) ...`) in scope inside its
	  own body, so the body can call itself directly or from a nested closure.
	- A plain OCaml `let fact = fun ...` does not see `fact` inside its right-hand
	  side, so ocamlopt reports `Unbound value fact`.

	What
	- Returns `let rec ` only for a named-function binding whose function value
	  reads its own projected name. Every other local keeps `let `.

	How
	- The local catalog gives each binding of the function a unique projected name,
	  so a read of that name inside the value is a read of this exact binding.
	- `var f = function() ...` is not a named function. Upstream does not put `f`
	  in scope inside that value, so an inner `f` names an earlier binding and a
	  recursive binding would change its meaning.
 */
function bindingKeyword(projectedName:String, value:Null<HxExpr>, catalog:Null<TypedBackendLocalCatalog>):String {
	if (value == null || catalog == null)
		return "let ";
	final entry = catalog.findByProjectedName(projectedName);
	if (entry == null || entry.getBinding().getKind() != NamedFunction)
		return "let ";
	final lambda = switch value {
		case ECast(inner, _) | ECheckType(inner, _): inner;
		case _: value;
	};
	if (!lambda.match(ELambda(_, _)))
		return "let ";
	var selfRead = false;
	TypedBackendSourceWalk.expression(lambda, expression -> switch expression {
		case EIdent(name) if (name == projectedName): selfRead = true;
		case _:
	});
	return selfRead ? "let rec " : "let ";
}
