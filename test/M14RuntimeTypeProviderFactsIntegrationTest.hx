import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Checks exact type operands in the real Neko exception provider before emission. */
class M14RuntimeTypeProviderFactsIntegrationTest {
	static function countChecks(expression:TypedExpr):Int {
		var count = 0;
		if (expression.getTag().match(Call)) {
			final declaration = expression.getDeclaration();
			if (declaration != null
				&& declaration.getIdentity().getCanonicalKey() == "Std#static:isOfType(required:dynamic,required:dynamic)->primitive:Bool#0") {
				final arguments = expression.getExpressions();
				if (arguments.length != 3)
					throw "selected Std.isOfType call lost an argument";
				final operand = arguments[2];
				final target = operand.getRuntimeTypeTarget();
				if (!operand.getTag().match(RuntimeTypeValue)
					|| target == null
					|| target.requireDeclarationIdentity().getCanonicalName() != "haxe.Exception"
					|| operand.getType().getSemanticKey() != "nominal:Class<nominal:haxe.Exception>")
					throw "exception provider class operand lost its exact meta-type";
				count++;
			}
		}
		for (child in expression.getExpressions())
			count += countChecks(child);
		return count;
	}

	static function statementChecks(statement:TypedStmt):Int {
		var count = 0;
		for (expression in statement.getExpressions())
			count += countChecks(expression);
		for (child in statement.getStatements())
			count += statementChecks(child);
		return count;
	}

	static function main():Void {
		final arguments = Stage1Args.parse(["-cp", "test/neko_exception_provider", "-main", "Main"], true);
		if (arguments == null)
			throw "provider fixture arguments did not parse";
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(arguments),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "neko"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "neko", "neko-native");
		final modules = ResolverStage.parseProjectRoots(paths, ["haxe.Exception"], defines);
		final index = TyperIndex.build(modules);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready(modules);
		var found = false;
		for (module in modules) {
			if (ResolvedModule.getModulePath(module) != "haxe.Exception")
				continue;
			if (!StringTools.endsWith(ResolvedModule.getFilePath(module).split("\\").join("/"), "/neko/_std/haxe/Exception.hx"))
				throw "runtime type test selected the wrong exception provider";
			// This test stops at the production shared typing boundary. The native
			// exception test separately checks projection, provider execution, and catches.
			final built = @:privateAccess TyperStage.buildTypedClasses(ResolvedModule.getParsed(module), index, loader, "haxe.Exception", true);
			TypedBodyInvariant.assertClasses(built.classes);
			final checked = new haxe.ds.StringMap<Bool>();
			for (cls in built.classes)
				for (fn in cls.getFunctions()) {
					var count = 0;
					for (statement in fn.getBody().getStatements())
						count += statementChecks(statement);
					if (count > 0)
						checked.set(HxFunctionDecl.getName(fn.getSourceDeclaration()), true);
				}
			if (!checked.exists("caught") || !checked.exists("thrown"))
				throw "both real provider conversion methods must retain selected type checks";
			found = true;
		}
		if (!found)
			throw "real Neko exception provider was not loaded";
		Sys.println("RUNTIME_TYPE_PROVIDER_FACTS:PASS");
	}
}
