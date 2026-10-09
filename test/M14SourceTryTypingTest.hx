import TypedExpr.TypedExprTag;

/** Catch declarations and abrupt exits must survive shared lowering without synthetic functions. */
class M14SourceTryTypingTest {
	static function expressions(fn:TypedFunction):Array<TypedExpr> {
		final found = new Array<TypedExpr>();
		function expression(node:TypedExpr):Void {
			found.push(node);
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (value in node.getExpressions())
				expression(value);
			for (child in node.getStatements())
				statement(child);
		}
		for (node in fn.getBody().getStatements())
			statement(node);
		return found;
	}

	static function tagged(nodes:Array<TypedExpr>, tag:TypedExprTag):Array<TypedExpr>
		return nodes.filter(node -> node.getTag() == tag);

	public static function run():Void {
		for (target in ["neko", "cpp"])
			resolvedCatchUses(target);
		capturedCatch();
		final path = "test/oracle/source_try_control_seed/src/Main.hx";
		final source = sys.io.File.getContent(path);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final fn = typed.getTypedClasses()[0].getFunctions()[0];
		final originalRevision = CompilerTypedTreeRevision.functionBody(fn);
		final before = expressions(fn);
		final tries = tagged(before, SourceTry);
		if (tries.length != 2 || tagged(before, SourceFunction).length != 2 || tagged(before, Lambda).length != 0)
			throw "typed try introduced synthetic callable scopes";
		final ordered = tries[0].getLocalBindings();
		if (ordered.length != 2
			|| ordered[0].getSourceName() != "number"
			|| ordered[0].getType().getSemanticKey() != "primitive:Int"
			|| ordered[1].getSourceName() != "text"
			|| ordered[1].getType().getSemanticKey() != "primitive:String")
			throw "catch typing lost ordered concrete declarations";
		for (node in tries) {
			final facts = node.getSourceCatches();
			for (index in 0...facts.length) {
				if (node.getLocalBindings()[index].getKind() != CatchVariable)
					throw "catch binding became an ordinary local or lambda parameter";
				if (source.substr(facts[index].getPosition().getIndex(), 5) != "catch")
					throw "module catch position was not rebased to its exact source";
			}
		}
		final targets = [
			for (node in tagged(before, ReturnExpr))
				node.getControlTarget().getCanonicalIdentity()
		];
		final lowered = TypedControlLowering.functionBody(fn);
		final after = expressions(lowered);
		final regions = tagged(after, ControlTry);
		if (regions.length != 2
			|| tagged(after, SourceTry).length != 0
			|| tagged(after, SourceFunction).length != 0
			|| tagged(after, Lambda).length != 2)
			throw "try lowering changed the authored callable count or left source control";
		for (index in 0...regions.length) {
			final region = regions[index];
			if (region.getControlTarget() != null || region.getExpressions().length != region.getSourceCatches().length + 1)
				throw "try region changed its lexical handler layout";
			final originalBindings = tries[index].getLocalBindings();
			final currentBindings = region.getLocalBindings();
			for (bindingIndex in 0...originalBindings.length)
				if (originalBindings[bindingIndex].getCanonicalIdentity() != currentBindings[bindingIndex].getCanonicalIdentity())
					throw "try lowering replaced an exact catch declaration";
			for (body in region.getExpressions())
				if (body.getTag() != ControlRegion || body.getControlTarget() != null)
					throw "try handler body became a function instead of a lexical region";
		}
		for (node in tagged(after, ReturnExpr))
			if (targets.indexOf(node.getControlTarget().getCanonicalIdentity()) < 0)
				throw "try lowering changed a return destination";
		if (tagged(after, StringValue).filter(node -> node.getTexts()[0] == "after" || node.getTexts()[0] == "wrong").length != 0)
			throw "effects after unconditional try/catch returns remained executable";
		final second = TypedControlLowering.functionBody(lowered);
		if (CompilerTypedTreeRevision.functionBody(second) != CompilerTypedTreeRevision.functionBody(lowered)
			|| CompilerTypedTreeRevision.functionBody(fn) != originalRevision)
			throw "try lowering changed typed source or was not idempotent";
		Sys.println("SOURCE_TRY_TYPING:PASS");
	}

	/** Target-selected catch facts belong to lexical try handlers and must survive lowering with their exact bindings. */
	static function resolvedCatchUses(target:String):Void {
		function build(name:String):TypedFunction {
			final source = 'class Main { static function read():Int { return try { 3; } catch (' + name + ':Dynamic) { 4; }; } }';
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			final index = TyperIndex.build([resolved]);
			final defines = new haxe.ds.StringMap<String>();
			defines.set(target, "1");
			final loader = new ModuleLoader(["."], defines, index, _ -> false);
			loader.markResolvedAlready([resolved]);
			return TyperStage.typeResolvedModule(resolved, index, loader).getTypedClasses()[0].getFunctions()[0];
		}
		final fn = build("error");
		final source = tagged(expressions(fn), SourceTry)[0];
		if (source == null || source.getCatchUses().length != 1)
			throw "source try lost the target-selected catch use";
		final use = source.getCatchUses()[0];
		final lowered = TypedControlLowering.functionBody(fn);
		TypedBodyInvariant.assertFunction(lowered);
		final statements = lowered.getBody().getStatements();
		final tries = statements.filter(statement -> statement.getTag().match(Try));
		if (tries.length != 1
			|| tries[0].getCatchUses().length != 1
			|| tries[0].getCatchUses()[0].getCanonicalIdentity() != use.getCanonicalIdentity())
			throw "statement try lowering changed the selected catch use";
		// The expression view is used inside authored function-value bodies.
		// Check that view independently from the root statement conversion above.
		final region = TypedExpr.controlTry(source.getSourceCatches(), [
			for (body in source.getExpressions())
				TypedExpr.controlRegion([body], body.getType(), body.getPosition())
		], source.getType(), source.getPosition(),
			source.getLocalBindings()).withCatchUses(source.getCatchUses());
		@:privateAccess TypedBodyInvariant.assertExpr(region, fn.getStableIdentity());
		function rejects(node:TypedExpr, expected:String):Void {
			try {
				@:privateAccess TypedBodyInvariant.assertExpr(node, fn.getStableIdentity());
			} catch (error:haxe.Exception) {
				if (error.message.indexOf(expected) < 0)
					throw error;
				return;
			}
			throw "invalid catch metadata was accepted: " + expected;
		}
		rejects(source.withCatchUses([use, use]), "catch use count differs");
		final foreign = tagged(expressions(build("other")), SourceTry)[0].getCatchUses();
		rejects(source.withCatchUses(foreign), "catch use belongs to another binding");
		rejects(TypedExpr.intLiteral(1, TyType.fromHintText("Int"), null).withCatchUses([use]), "catch uses require");
	}

	/** An escaping handler closure captures the selected catch binding, not a synthetic parameter. */
	static function capturedCatch():Void {
		final source = "class Main { static function make():Void->String { return try { throw 'problem'; } catch (value:String) { function():String { return value; }; }; } }";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final fn = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])).getTypedClasses()[0].getFunctions()[0];
		final projection = TypedBodySource.functionProjection(fn);
		final catalog = projection.requireCaptureCatalog();
		final expressions = catalog.getExpressions();
		if (expressions.length != 1)
			throw "catch capture introduced an extra function";
		final captures = catalog.require(expressions[0]).getCaptures();
		if (captures.length != 1 || captures[0].getSourceName() != "value" || captures[0].getKind() != CatchVariable)
			throw "handler closure lost the exact selected catch variable";
		final allocations = catalog.getPlan().getBindings().filter(entry -> entry.binding.getCanonicalIdentity() == captures[0].getCanonicalIdentity());
		if (allocations.length != 1 || allocations[0].creation != CatchEntry)
			throw "captured handler value lost its catch-entry allocation event";
	}

	static function main():Void
		run();
}
