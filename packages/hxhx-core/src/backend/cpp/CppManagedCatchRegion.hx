package backend.cpp;

import backend.cpp.CppManagedRootedExpression.CppManagedExpressionOwner;

/** The exact projected try occurrence retains its authored statement or lowered expression form. */
enum CppManagedTrySource {
	Statement(node:HxStmt);
	Expression(node:HxExpr);
}

/** Validate lexical occurrence before reading catch facts; equal source text cannot authorize a handler. */
private function requireSource(owner:CppManagedExpressionOwner, source:CppManagedTrySource):Void {
	switch source {
		case Statement(node):
			final projection = switch owner {
				case CallableBody(access):
					access.plan.requireFunction(access.owner);
					switch access.owner {
						case Root(projection): projection;
						case _: throw "managed statement catch requires its root function";
					}
				case _: throw "managed statement catch requires its root function";
			};
			var found = false;
			function visit(candidate:HxStmt):Void {
				if (candidate == node)
					found = true;
				TypedBackendSourceWalk.statementChildren(candidate, _ -> {}, visit);
			}
			for (candidate in projection.getBody())
				visit(candidate);
			if (!found)
				throw "managed catch is not an exact statement in its projection";
		case Expression(node):
			switch owner {
				case CallableBody(access): access.requireExpression(node);
				case FieldInitializer(projection):
					projection.assertCurrent();
					var found = false;
					function visit(candidate:HxExpr):Void {
						if (candidate == node)
							found = true;
						if (!candidate.match(ELambda(_, _)))
							TypedBackendSourceWalk.expressionChildren(candidate, visit);
					}
					visit(projection.getExpression());
					if (!found) throw "managed catch is not an exact expression in its initializer";
			}
	}
}

/** Keep the native unwinding carrier separate from the typed Haxe handler value. */
function render(input:{
	owner:CppManagedExpressionOwner,
	source:CppManagedTrySource,
	locals:CppManagedExpressionLocals,
	heap:String,
	prefix:String,
	indent:String,
	body:String->Array<String>,
	handler:(Int, String) -> Array<String>
}):Array<String> {
	requireSource(input.owner, input.source);
	final names = switch input.source {
		case Statement(STry(_, clauses, _)): [for (clause in clauses) clause.name];
		case Expression(ELoweredControl(Try(clauses), "", children, _)) if (children.length == clauses.length + 1):
			[for (clause in clauses) clause.getName()];
		case _: throw "managed catch requires a well-formed projected try";
	};
	if (names.length == 0)
		throw "managed try requires at least one handler";
	final uses = [
		for (name in names)
			switch input.owner {
				case CallableBody(access):
					access.requireCatchUse(name);
				case FieldInitializer(projection):
					final binding = input.locals.binding(name);
					final use = projection.getLocalCatalog().findCatchUse(binding.getIdentity().getCanonicalKey());
					if (use == null || use.binding != binding)
						throw "managed catch requires its exact typed implicit use";
					use;
			}
	];
	// Carrier handling is complete without runtime classification. Other views
	// must acquire their exact provider and target policy before admission.
	for (use in uses)
		if (use.view != Carrier)
			throw "managed catch requires typed handler selection for " + use.binding.getType().getSemanticKey() + " (haxe_ocaml-qrk0u)";
	final carrier = input.prefix + "carrier";
	final selected = input.prefix + "selected";
	final at = input.indent;
	final lines = [at + "try {"];
	for (line in input.body(at + "  "))
		lines.push(line);
	lines.push(at + "} catch (const hxhx::managed::ThrownValue& " + carrier + ") {");
	lines.push(at + "  hxhx::managed::Root<hxhx::managed::Value> " + selected + "(" + input.heap + ", " + carrier + ".value());");
	for (index in 0...uses.length) {
		lines.push(at + (index == 0 ? "  if (true) {" : "  else if (true) {"));
		for (line in input.locals.renderCatch(uses[index].binding, selected, input.heap, at + "    "))
			lines.push(line);
		for (line in input.handler(index, at + "    "))
			lines.push(line);
		lines.push(at + "  }");
	}
	lines.push(at + "}");
	requireSource(input.owner, input.source);
	return lines;
}
