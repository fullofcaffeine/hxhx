/** Selected case declarations must survive projection without leaking across bodies or source revisions. */
class M14NamedPatternProjectionTest {
	static function program(value:String):{modules:Array<TypedModule>, index:TyperIndex} {
		final sources = [
			{path: "Api", source: 'enum abstract Api(String) { var Ready="' + value + '"; var Waiting="wait"; }'},
			{
				path: "Main",
				source: 'import Api as Status; class Main { static function read(value:Status):Int return switch value { case Status.Ready: 1; case Status.Waiting: 2; case _: 0; }; }'
			},
			{path: "Unused", source: 'class Unused {}'}
		];
		final resolved = [
			for (source in sources)
				new ResolvedModule(source.path, source.path + ".hx", ParserStage.parse(source.source, source.path + ".hx"))
		];
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, _ -> false);
		loader.markResolvedAlready(resolved);
		return {
			modules: [
				for (module in resolved)
					TyperStage.typeResolvedModule(module, index, loader, true)
			],
			index: index
		};
	}

	static function patterns(body:TypedBackendFunctionProjection):Array<HxSwitchPattern> {
		final result = new Array<HxSwitchPattern>();
		TypedBackendSourceWalk.functionDeclaration(body.getDeclaration(), expression -> TypedBackendNamedPattern.inExpression(expression, result.push),
			statement -> TypedBackendNamedPattern.inStatement(statement, result.push));
		return result;
	}

	/** This is also called by the existing enum-pattern binding gate. */
	public static function check():Void {
		final before = program("ready");
		final consumer = before.modules.filter(module -> CompilerTypedModuleRevision.semanticModulePath(module) == "Main")[0];
		var source:Null<TypedFunction> = null;
		for (owner in consumer.getTypedClasses())
			for (fn in owner.getFunctions())
				if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "read")
					source = fn;
		if (source == null)
			throw "missing authored pattern consumer";
		final sourceIdentity = TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(source.getSourceDeclaration()));
		final first = TypedBodySource.functionProjection(source);
		final second = TypedBodySource.functionProjection(source);
		final names = patterns(first);
		if (names.length != 2 || !names[0].match(PEnumValue("Status.Ready")))
			throw "projection rewrote authored case spelling";
		final selected = first.findNamedPattern(names[0]);
		if (selected == null)
			throw "projection lost selected constant";
		switch selected.getKind() {
			case Constant(field):
				if (field.getOwner().getCanonicalName() != "Api" || !field.getConstant().getKind().match(StringValue("ready")))
					throw "alias pattern selected another constant";
			case _:
				throw "enum abstract became an ordinary enum constructor";
		}
		if (first.findNamedPattern(PEnumValue("Status.Ready")) != null || second.findNamedPattern(names[0]) != null)
			throw "foreign or copied pattern borrowed a declaration";
		if (sourceIdentity != TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(source.getSourceDeclaration())))
			throw "projection mutated authored switch syntax";
		var replaced = false;
		TypedBackendSourceWalk.functionDeclaration(first.getDeclaration(), _ -> {}, statement -> {
			switch statement {
				case SSwitch(_, cases, _, _):
					if (!replaced && cases[0] == names[0]) {
						cases[0] = PEnumValue("Status.Ready");
						replaced = true;
					}
				case _:
			}
		});
		var rejected = false;
		try {
			first.findNamedPattern(names[0]);
		} catch (_:String) {
			rejected = true;
		}
		if (!replaced || !rejected)
			throw "removed pattern retained emission authority after an equal-shaped replacement";

		final snapshot = CompilerDependencyCollector.collect(before.modules, before.index);
		final constants = snapshot.getEdges().filter(edge -> edge.consumerModule == "Main" && edge.providerModule == "Api" && edge.kind == ConstantValue);
		if (constants.length != 2)
			throw "case constants lost their cross-module dependencies";
		final after = program("changed");
		final comparison = CompilerDependencyInvalidator.compare(snapshot, CompilerDependencyCollector.collect(after.modules, after.index));
		if (!comparison.isAffected("Main") || comparison.isAffected("Unused"))
			throw "pattern constant edit invalidated the wrong modules";
		Sys.println("NAMED_PATTERN_PROJECTION:PASS");
	}

	static function main():Void
		check();
}
