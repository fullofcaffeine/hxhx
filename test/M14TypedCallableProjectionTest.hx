/**
	Callback planning must read exact typed occurrences after source-shaped projection.

	Nested calls and comparisons often have no byte position. Their original objects,
	local bindings, declaration identities and body revision still distinguish them
	from another use with the same spelling.
**/
class M14TypedCallableProjectionTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function rejects(diagnostic:String, action:Void->Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			require(error.message.indexOf(diagnostic) >= 0, "Expected " + diagnostic + ": " + error.message);
			return;
		}
		throw "Changed projected syntax must invalidate callable evidence";
	}

	/** A transparent lowered sequence keeps its value producer; effects still own a distinct projected node. */
	static function forwardedValue(source:TypedExpr, projection:TypedBackendFunctionProjection):Void {
		final builder = new TypedBodyProjectionBuilder(projection.getStableIdentity(), projection.getBodyRevision());
		final once = TypedExpr.block([source], source.getType(), null);
		final twice = TypedExpr.block([once], source.getType(), null);
		final projected = TypedBodySource.expression(twice, projection.getLocalCatalog(), builder);
		final occurrences = builder.getCallableExpressions();
		require(occurrences.length == 1 && occurrences[0].expression == projected && occurrences[0].source == source,
			"Transparent blocks must not give one projected callback conflicting typed producers");
		final second = TypedBodySource.expression(twice, projection.getLocalCatalog(), builder);
		require(second != projected
			&& builder.getCallableExpressions().length == 2, "Separate projected occurrences must retain separate callback evidence");

		final effectBuilder = new TypedBodyProjectionBuilder(projection.getStableIdentity(), projection.getBodyRevision());
		final effectful = TypedExpr.block([TypedExpr.intLiteral(1, TyType.fromHintText("Int"), null), source], source.getType(), null);
		final effectProjection = TypedBodySource.expression(effectful, projection.getLocalCatalog(), effectBuilder);
		final effectOccurrences = effectBuilder.getCallableExpressions();
		require(effectOccurrences.length == 2
			&& effectOccurrences[0].source == source
			&& effectOccurrences[1].source == effectful
			&& effectOccurrences[1].expression == effectProjection,
			"A sequence with effects must retain its own callback-producing expression");
	}

	static function main():Void {
		final path = "test/fixtures/stage3_stored_callback_views/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final originalRevision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final fn = typed.getTypedClasses()[0].getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")[0];
		final projection = TypedBodySource.functionProjection(fn);
		final catalog = projection.requireCaptureCatalog();
		final occurrences = catalog.getCallableExpressions();
		require(occurrences.length > 0, "The full stored-callback fixture must retain callable occurrences");
		var staticOrigin = false;
		var localView = false;
		var nestedInvocation = false;
		var comparison = false;
		var literal = false;
		var returned = false;
		var mutableCall:Null<Array<HxExpr>> = null;
		for (entry in occurrences) {
			require(catalog.findCallableExpression(entry.expression) == entry.source, "Projection must preserve the original typed node");
			require(projection.findCallableExpression(entry.expression) == entry.source, "Direct lookup must retain the exact typed occurrence");
			final source = entry.source;
			switch source.getTag() {
				case NameRead:
					final declaration = source.getDeclaration();
					if (declaration != null && declaration.getSignature().getName() == "consume")
						staticOrigin = declaration.getIsStatic();
				case LocalRead:
					final bindings = source.getLocalBindings();
					if (bindings.length == 1 && bindings[0].getSourceName() == "first")
						localView = bindings[0].getIdentity().getOwnerIdentity() == fn.getStableIdentity();
				case Call:
					final callee = source.getExpressions()[0];
					if (callee.getTag() == LocalRead && source.getPosition() == null)
						nestedInvocation = true;
					if (source.getType().isFunction())
						returned = true;
					switch entry.expression {
						case ECall(_, arguments): mutableCall = arguments;
						case _:
					}
				case Binary:
					comparison = source.getExpressions()[0].getType().isFunction() && source.getPosition() == null;
				case Lambda:
					literal = true;
				case _:
			}
		}
		require(staticOrigin && localView && nestedInvocation && comparison && literal && returned,
			"Retain declaration, local, nested-call, comparison, literal and callback-result evidence");
		forwardedValue(occurrences.filter(entry -> entry.source.getTag() == LocalRead)[0].source, projection);
		final other = TypedBodySource.functionProjection(fn).requireCaptureCatalog();
		require(other.findCallableExpression(occurrences[0].expression) == null, "An equal reconstruction cannot borrow occurrence authority");
		require(catalog.findCallableExpression(HxExpr.EIdent("first")) == null, "Spelling alone cannot identify a stored view");
		require(projection.findCallableExpression(HxExpr.EIdent("first")) == null, "Direct lookup cannot authorize reconstructed syntax");
		require(TypedBodySource.functionProjection(fn).findCallableExpression(occurrences[0].expression) == null,
			"Direct lookup cannot borrow another projection's occurrence");
		occurrences.pop();
		require(catalog.getCallableExpressions().length == occurrences.length + 1, "The caller must not edit the retained occurrence inventory");
		require(CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() == originalRevision, "Projection must not change typed source");
		require(mutableCall != null, "The fixture must retain a projected callback invocation");
		mutableCall.push(EInt(99));
		rejects("projection was mutated", () -> catalog.getCallableExpressions());
		rejects("projection was mutated", () -> projection.findCallableExpression(occurrences[0].expression));

		// Equal syntax has the same fingerprint, so exact-object checks must also run.
		final replacement = TypedBodySource.functionProjection(fn).requireCaptureCatalog();
		var replaced = false;
		for (entry in replacement.getCallableExpressions()) {
			if (replaced)
				break;
			switch entry.expression {
				case ECall(_, arguments):
					for (index in 0...arguments.length) {
						final value = replacement.findCallableExpression(arguments[index]);
						if (value == null || value.getTag() != LocalRead)
							continue;
						switch arguments[index] {
							case EIdent(name):
								arguments[index] = HxExpr.EIdent(name);
								replaced = true;
							case _:
						}
						if (replaced)
							break;
					}
				case _:
			}
		}
		require(replaced, "The fixture must contain a callback passed as an argument");
		rejects("callable projection occurrences changed", () -> replacement.getCallableExpressions());
		Sys.println("TYPED_CALLABLE_PROJECTION:PASS");
	}
}
