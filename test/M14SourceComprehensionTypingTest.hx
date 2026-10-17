/** Comprehensions infer their yielded type while retaining the authored loop's binding. */
class M14SourceComprehensionTypingTest {
	static function rejected(action:Void->Void, expected:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) >= 0)
				return;
			throw error;
		}
		throw "comprehension projection accepted foreign or changed facts";
	}

	static function main():Void {
		for (sample in [
			{declaration: "final result = [for (item in [1, 2]) item];", element: "primitive:Int"},
			{declaration: "final result = [for (item in [1, 2]) (\"a=>b\")];", element: "primitive:String"},
			{declaration: "final result:Array<String> = [for (item in [1, 2]) (\"a=>b\")];", element: "primitive:String"}
		]) {
			final path = "Main.hx";
			final source = "class Main { static function main():Void { " + sample.declaration + " } }";
			final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final module = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			final fn = module.getTypedClasses()[0].getFunctions()[0];
			final initializer = fn.getBody().getStatements()[0].getExpressions()[0];
			final arguments = initializer.getType().getTypeArguments();
			if (arguments.length != 1 || arguments[0].getSemanticKey() != sample.element)
				throw "comprehension inferred the loop result instead of the yielded element";
			final loop = initializer.getExpressions()[0];
			if (initializer.getTag() != ArrayDecl || loop.getTag() != SourceFor || loop.getLocalBindings().length != 1)
				throw "typing discarded the authored comprehension loop";
			final binding = loop.getLocalBindings()[0];
			if (binding.getType().getSemanticKey() != "primitive:Int")
				throw "comprehension lost its concrete iteration element";
			final yielded = loop.getExpressions()[1];
			if (yielded.getTag() == LocalRead && yielded.getLocalBindings()[0].getCanonicalIdentity() != binding.getCanonicalIdentity())
				throw "comprehension yield reads a different declaration";
			final original = CompilerTypedTreeRevision.functionBody(fn);
			final lowered = TypedControlLowering.functionBody(fn);
			final loops = new Array<TypedExpr>();
			final appends = new Array<TypedExpr>();
			function visit(expression:TypedExpr):Void {
				if (expression.getTag() == ControlFor)
					loops.push(expression);
				if (expression.getTag() == ArrayAppend)
					appends.push(expression);
				for (child in expression.getExpressions())
					visit(child);
			}
			function statement(node:TypedStmt):Void {
				for (value in node.getExpressions())
					visit(value);
				for (child in node.getStatements())
					statement(child);
			}
			for (node in lowered.getBody().getStatements())
				statement(node);
			if (loops.length != 1
				|| loops[0].getLocalBindings()[0].getCanonicalIdentity() != binding.getCanonicalIdentity()
				|| appends.length != 1
				|| appends[0].getExpressions()[0].getType().getSemanticKey() != initializer.getType().getSemanticKey())
				throw "execution selection lost the shared result or exact iteration binding";
			if (CompilerTypedTreeRevision.functionBody(fn) != original)
				throw "execution selection changed authored source";
			final once = CompilerTypedTreeRevision.functionBody(lowered);
			if (CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)) != once)
				throw "repeated comprehension lowering changed the execution operation";
			final projection = TypedBodySource.functionProjection(fn);
			final value = switch projection.getBody()[0] {
				case SVar(_, _, value, _): value;
				case _: throw "comprehension projection lost its initializer";
			};
			final occurrence = projection.requireAggregate(value);
			if (occurrence.getType().getSemanticKey() != initializer.getType().getSemanticKey())
				throw "backend projection lost the exact collection type";
			rejected(() -> TypedBodySource.functionProjection(fn).requireAggregate(value), "not an exact occurrence");
			switch value {
				case EArrayDecl(values):
					rejected(() -> projection.requireAggregate(EArrayDecl(values.copy())), "not an exact occurrence");
					values.push(EInt(99));
					rejected(() -> projection.requireAggregate(value), "mutated");
					values.pop();
					projection.requireAggregate(value);
				case _:
					throw "comprehension fixture lost its iterable";
			}
		}
		Sys.println("SOURCE_COMPREHENSION_TYPING:PASS");
	}
}
