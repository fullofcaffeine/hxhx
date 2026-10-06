import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Check map yields against real providers without claiming full-program target execution. */
class M14SourceMapComprehensionTypingTest {
	static function main():Void {
		final args = Stage1Args.parse(["-cp", "test/oracle/source_comprehension_seed/maps", "-main", "MapCollection"], true);
		if (args == null)
			throw "map fixture arguments did not parse";
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(args),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "cpp"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "cpp", "cpp-native");
		final resolved = ResolverStage.parseProjectRoots(paths, ["MapCollection"], defines);
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready(resolved);
		final selected = resolved.filter(module -> ResolvedModule.getModulePath(module) == "MapCollection");
		if (selected.length != 1)
			throw "map fixture requires its exact authored module";
		final module = TyperStage.typeResolvedModule(selected[0], index, loader, true);
		final provider = index.getByFullName("haxe.ds.Map");
		if (provider == null)
			throw "map fixture requires the real Map provider";
		var observed = 0;
		for (fn in module.getTypedClasses()[0].getFunctions()) {
			function visit(expression:TypedExpr):Void {
				final children = expression.getExpressions();
				if (expression.getTag() == ArrayDecl && children.length == 1 && children[0].getTag() == SourceFor) {
					var type = expression.getType();
					final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
					if (name == "mapValues" || name == "qualifiedMapValues") {
						final array = index.getByFullName("Array");
						if (array == null || type.getNominalIdentity() != array.getIdentity() || type.getTypeArguments().length != 1)
							throw "yielded map value must remain an array element";
						type = type.getTypeArguments()[0];
					}
					final arguments = type.getTypeArguments();
					if (type.getNominalIdentity() != provider.getIdentity()
						|| arguments.length != 2
						|| arguments[0].getSemanticKey() != "primitive:Int"
						|| arguments[1].getSemanticKey() != "primitive:Int")
						throw "map comprehension lost its exact provider or yielded types in " + name + ": " + type.getSemanticKey();
					final bindings = children[0].getLocalBindings();
					if (bindings.length != (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "indexed" ? 2 : 1))
						throw "map comprehension lost its source loop bindings";
					observed++;
				}
				for (child in children)
					visit(child);
			}
			function statement(node:TypedStmt):Void {
				for (expression in node.getExpressions())
					visit(expression);
				for (child in node.getStatements())
					statement(child);
			}
			for (node in fn.getBody().getStatements())
				statement(node);
		}
		if (observed != 9)
			throw "map typing fixture omitted a comprehension";
		Sys.println("SOURCE_MAP_COMPREHENSION_TYPING:PASS");
	}
}
