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

/** Select only independently supported value tags; other catch families retain their explicit boundary. */
private function ordinaryKind(use:TypedCatchUse):String {
	if (use.view == OrdinaryValue && use.target != null)
		return switch use.target.getKind() {
			case BoolCore: "Boolean";
			case StringCore: "String";
			case _: throw "managed catch requires typed handler selection for " + use.binding.getType().getSemanticKey() + " (haxe_ocaml-qrk0u)";
		};
	throw "managed catch requires typed handler selection for " + use.binding.getType().getSemanticKey() + " (haxe_ocaml-qrk0u)";
}

/**
	Keep the native unwinding carrier separate from the typed Haxe handler value.
	A wrapped payload can match any supported typed handler in source order. If
	none matches, propagate the original wrapper rather than enter a later catch-all.
 */
function render(input:{
	owner:CppManagedExpressionOwner,
	source:CppManagedTrySource,
	locals:CppManagedExpressionLocals,
	?classes:CppManagedClassStorage,
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
	final kinds = [for (use in uses) use.view == Carrier ? null : ordinaryKind(use)];
	var payload:Null<backend.cpp.CppManagedClassStorage.CppManagedInstanceMember> = null;
	for (use in uses) {
		if (use.view == OrdinaryValue) {
			if (input.classes == null)
				throw "managed typed catch requires its program class storage";
			final selectedPayload = input.classes.catchPayload(use);
			if (payload != null && (payload.layout.symbol != selectedPayload.layout.symbol || payload.slot != selectedPayload.slot))
				throw "managed catch views disagree on their payload provider";
			payload = selectedPayload;
		}
	}
	final carrier = input.prefix + "carrier";
	final selected = input.prefix + "selected";
	final ordinary = input.prefix + "ordinary";
	final wrapped = input.prefix + "wrapped";
	final at = input.indent;
	final lines = [at + "try {"];
	for (line in input.body(at + "  "))
		lines.push(line);
	lines.push(at + "} catch (const hxhx::managed::ThrownValue& " + carrier + ") {");
	lines.push(at + "  hxhx::managed::Root<hxhx::managed::Value> " + selected + "(" + input.heap + ", " + carrier + ".value());");
	if (payload != null) {
		// Unwrap one layer without modifying the original carrier. Unmatched
		// propagation must retain the original exception.
		lines.push(at + "  hxhx::managed::Root<hxhx::managed::Value> " + ordinary + "(" + input.heap + ", " + selected + ".get());");
		lines.push(at + "  const bool " + wrapped + " = hxhx_runtime_is_of_type(" + selected + ".get(), hxhx::managed::Value::descriptor(&"
			+ payload.layout.symbol + "));\n");
		lines.push(at + "  if (" + wrapped + ") {");
		lines.push(at
			+ "    "
			+ ordinary
			+ ".set("
			+ selected
			+ ".get().asManaged().as<hxhx::managed::InstancePayload>()->read("
			+ payload.layout.symbol
			+ ", "
			+ payload.slot
			+ "));");
		lines.push(at + "  }");
	}
	var sawOrdinaryHandler = false;
	for (index in 0...uses.length) {
		final isCarrier = uses[index].view == Carrier;
		final condition = isCarrier ? (sawOrdinaryHandler ? "!" + wrapped : "true") : ordinary + ".get().kind() == hxhx::managed::ValueKind::" + kinds[index];
		lines.push(at + (index == 0 ? "  if (" : "  else if (") + condition + ") {");
		// Upstream C++ commits a ValueException to the primitive handler group.
		// Test every typed handler before the final rethrow; a failed early test
		// must not hide a later match. A raw unmatched value can reach Dynamic.
		if (!isCarrier)
			sawOrdinaryHandler = true;
		for (line in input.locals.renderCatch(uses[index].binding, isCarrier ? selected : ordinary, input.heap, at + "    "))
			lines.push(line);
		for (line in input.handler(index, at + "    "))
			lines.push(line);
		lines.push(at + "  }");
	}
	lines.push(at + "  else { throw; }");
	lines.push(at + "}");
	requireSource(input.owner, input.source);
	return lines;
}
