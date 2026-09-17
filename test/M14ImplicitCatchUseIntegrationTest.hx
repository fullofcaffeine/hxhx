import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Proves implicit catch providers are selected during shared typing, before any backend runs. */
class M14ImplicitCatchUseIntegrationTest {
	/** An absent parent declaration cannot prove that a catch type is unrelated to Exception. */
	static function rejectIncompleteAncestry():Void {
		final index = TyperIndex.build([]);
		final context = new TyperContext(index, "Incomplete.hx", "Incomplete", "", [], "Incomplete");
		function nominal(name:String, parent:Null<TyType>):TyClassInfo {
			return new TyClassInfo(new TyNominalTypeId(name), name, name, new haxe.ds.StringMap(), new haxe.ds.StringMap(), new haxe.ds.StringMap(),
				new haxe.ds.StringMap(), new haxe.ds.StringMap(), new haxe.ds.StringMap(), [], HxVisibility.Public, false, parent);
		}
		final ancestor = nominal("haxe.Exception", null);
		final child = nominal("Incomplete", TyType.nominal(new TyNominalTypeId("MissingParent"), []));
		var rejected = false;
		try {
			context.classIsOrExtends(child, ancestor, true);
		} catch (message:String) {
			rejected = message.indexOf("requires indexed ancestry") >= 0;
		}
		if (!rejected)
			throw "missing ancestry silently classified an exception catch";
	}

	static function observe(provider:CompilerSourceProvider):{typed:Array<TypedModule>, index:TyperIndex} {
		final args = Stage1Args.parse(["-cp", "test/neko_implicit_catch_dependencies", "-main", "Main"], true);
		if (args == null)
			throw "implicit catch fixture arguments did not parse";
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(args),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "neko"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "neko", "neko-native");
		final resolved = ResolverStage.parseProjectRoots(paths, ["Main"], defines, provider);
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(paths, defines, index, null, true, provider);
		loader.markResolvedAlready(resolved);
		final pending = resolved.copy();
		final typed = new Array<TypedModule>();
		var cursor = 0;
		while (cursor < pending.length) {
			typed.push(TyperStage.typeResolvedModule(pending[cursor++], index, loader, true));
			for (loaded in loader.drainNewModules())
				pending.push(loaded);
		}
		return {typed: typed, index: index};
	}

	/** Edit only the request's source view; installed standard-library files remain untouched. */
	static function payloadProvider(edited:Bool):CompilerSourceProvider {
		final filesystem = new CompilerSourceProvider();
		return CompilerSourceProvider.fromCallbacks(filesystem.resolveModule, function(path:String):Null<String> {
			final source = filesystem.readSource(path);
			if (StringTools.endsWith(path, "/neko_implicit_catch_dependencies/Main.hx"))
				return "class Main { static function main():Void { try { throw 1; } catch (unused:String) {} } }";
			if (edited && source != null && StringTools.endsWith(path, "/haxe/ValueException.hx")) {
				final end = source.lastIndexOf("}");
				if (end < 0)
					throw "payload provider has no class boundary";
				return source.substr(0, end) + "public function implicitCatchRevisionProbe():Int return 0;\n" + source.substr(end);
			}
			return source;
		},
			filesystem.parseFilteredSource, filesystem.readDirectory, filesystem.isFile, filesystem.prepareFinish, filesystem.finish, filesystem.report);
	}

	static function main():Void {
		rejectIncompleteAncestry();
		final program = observe(new CompilerSourceProvider());
		final typed = program.typed;
		final index = program.index;
		final uses = new haxe.ds.StringMap<Array<TypedCatchUse>>();
		for (module in typed)
			for (cls in module.getTypedClasses())
				if (cls.getSemanticInfo().getFullName() == "Main")
					for (fn in cls.getFunctions()) {
						final found = new Array<TypedCatchUse>();
						function expression(expr:TypedExpr):Void {
							if (expr.getCatchUses().length > 0) {
								final revision = CompilerTypedTreeRevision.expression(fn.getStableIdentity(), expr);
								if (revision != CompilerTypedTreeRevision.expression(fn.getStableIdentity(), expr.withExpressions(expr.getExpressions()))
									|| revision == CompilerTypedTreeRevision.expression(fn.getStableIdentity(), expr.withCatchUses([])))
									throw "expression revisions failed to preserve or distinguish catch provider facts";
							}
							for (use in expr.getCatchUses())
								found.push(use);
							for (child in expr.getExpressions())
								expression(child);
						}
						function statement(stmt:TypedStmt):Void {
							if (stmt.getCatchUses().length > 0) {
								function revision(value:TypedStmt):String {
									return CompilerTypedTreeRevision.functionBody(fn.withBody(new TypedFunctionBody([value],
										fn.getBody().getSourceFingerprint())));
								}
								if (revision(stmt) != revision(stmt.withChildren(stmt.getExpressions(), stmt.getStatements()))
									|| revision(stmt) == revision(stmt.withCatchUses([])))
									throw "statement revisions failed to preserve or distinguish catch provider facts";
							}
							for (use in stmt.getCatchUses())
								found.push(use);
							for (expr in stmt.getExpressions())
								expression(expr);
							for (child in stmt.getStatements())
								statement(child);
						}
						for (stmt in fn.getBody().getStatements())
							statement(stmt);
						final projected = TypedBodySource.functionProjection(fn);
						for (use in found)
							if (projected.getLocalCatalog().findCatchUse(use.binding.getIdentity().getCanonicalKey()) != use)
								throw "function projection discarded an implicit catch provider";
						uses.set(HxFunctionDecl.getName(fn.getSourceDeclaration()), found);
					}
		for (name in ["statement", "expression", "base", "raw", "subtype"])
			if (uses.get(name) == null || uses.get(name).length != 1)
				throw "missing exact implicit catch use: " + name;
		for (name in ["statement", "expression", "base", "raw", "subtype"]) {
			final use = uses.get(name)[0];
			final catalog = new TypedBackendLocalCatalog([use.binding], [], [use]);
			if (catalog.findCatchUse(use.binding.getIdentity().getCanonicalKey()) != use)
				throw "local projection lost the exact catch provider: " + name;
			var rejected = false;
			try {
				new TypedBackendLocalCatalog([use.binding], [], [use, use]);
			} catch (message:String) {
				rejected = true;
			}
			if (!rejected)
				throw "local projection admitted duplicate catch provider facts";
		}
		for (name in ["statement", "expression"]) {
			final use = uses.get(name)[0];
			if (!use.view.match(OrdinaryValue)
				|| use.conversion != null
				|| use.payload == null
				|| use.payload.getCanonicalKey() != "haxe.ValueException#instance#value")
				throw "ordinary catch lost its exact payload provider: " + name;
		}
		final base = uses.get("base")[0];
		if (!base.view.match(BaseException)
			|| base.conversion == null
			|| base.payload != null
			|| base.conversion.getOwner().getCanonicalName() != "haxe.Exception")
			throw "base exception catch lost its exact conversion";
		if (!uses.get("raw")[0].view.match(Carrier)
			|| !uses.get("subtype")[0].view.match(ExceptionSubtype)
			|| uses.get("subtype")[0].payload != null
			|| uses.get("subtype")[0].conversion != null)
			throw "raw or exception-subtype catches acquired an eager conversion";
		final snapshot = CompilerDependencyCollector.collect(typed, index);
		var conversion = false;
		var payload = false;
		for (edge in snapshot.getEdges())
			if (edge.consumerModule == "Main") {
				if (edge.providerModule == "haxe.Exception" && edge.factIdentity.indexOf("implicit-catch-conversion:") == 0)
					conversion = true;
				if (edge.providerModule == "haxe.ValueException" && edge.factIdentity.indexOf("implicit-catch-payload:") == 0)
					payload = true;
			}
		if (!conversion || !payload)
			throw "implicit provider uses disappeared from the shared dependency snapshot";
		final before = observe(payloadProvider(false));
		final after = observe(payloadProvider(true));
		for (module in before.typed)
			for (cls in module.getTypedClasses())
				if (cls.getSemanticInfo().getFullName() == "Main" && cls.getFunctions().length != 1)
					throw "implicit-only source override was not selected";
		final comparison = CompilerDependencyInvalidator.compare(CompilerDependencyCollector.collect(before.typed, before.index),
			CompilerDependencyCollector.collect(after.typed, after.index));
		final reason = comparison.reasonFor("Main");
		if (!comparison.isAffected("Main")
			|| reason == null
			|| reason.describe().indexOf("public-interface:Main->haxe.ValueException") < 0)
			throw "an implicit payload provider edit did not invalidate its unused catch consumer";
		final filesystem = new CompilerSourceProvider();
		final privateEdit = CompilerSourceProvider.fromCallbacks(filesystem.resolveModule, path -> {
			final source = filesystem.readSource(path);
			if (source != null && StringTools.endsWith(path, "/neko/_std/haxe/Exception.hx")) {
				final signature = "function caught(value:Any)";
				if (source.indexOf(signature) < 0)
					throw "private catch provider signature was not selected";
				return source.split(signature).join("function caught(?value:Any)");
			}
			return source;
		},
			filesystem.parseFilteredSource, filesystem.readDirectory, filesystem.isFile, filesystem.prepareFinish, filesystem.finish, filesystem.report);
		final privateProgram = observe(privateEdit);
		final privateSnapshot = CompilerDependencyCollector.collect(privateProgram.typed, privateProgram.index);
		if (snapshot.findModule("haxe.Exception").publicInterfaceRevision != privateSnapshot.findModule("haxe.Exception").publicInterfaceRevision)
			throw "private helper edit unexpectedly changed the public interface";
		final privateComparison = CompilerDependencyInvalidator.compare(snapshot, privateSnapshot);
		final privateReason = privateComparison.reasonFor("Main");
		if (!privateComparison.isAffected("Main")
			|| privateReason == null
			|| privateReason.describe().indexOf("private-declaration:Main->haxe.Exception") < 0)
			throw "a private implicit conversion signature edit did not invalidate its catch consumer";
		Sys.println("IMPLICIT_CATCH_USES:PASS");
	}
}
