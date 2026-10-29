/** A bare trailing wildcard covers the remaining enum payload without erasing source syntax distinctions. */
@:access(M14OptionalEnumPatternTest)
@:access(TypedSwitchPatterns)
class M14EnumWildcardSuffixPatternTest {
	static function admission(pattern:String, accepted:Bool):Void {
		M14OptionalEnumPatternTest.admission("Build(a:Int,b:Bool,c:String);", 'Build(1,true,"kept")', pattern, accepted);
	}

	static function read(pattern:String):TypedFunction {
		final module = M14OptionalEnumPatternTest.typed('enum Value { Build(a:Int,b:Bool,c:String); }'
			+ 'class Main { static function read(value:Value):Int return switch value { case '
			+ pattern
			+ ': a; case _: 0; }; }');
		return module.getTypedClasses().filter(owner -> HxClassDecl.getName(owner.getSourceDeclaration()) == "Main")[0].getFunctions()[0];
	}

	/** Grouping is erased structurally, so both source and typed revisions must retain the parser's permission bit. */
	static function sourceFacts():Void {
		final bare = read("Build(a,_,_)");
		final grouped = read("Build(a,_,(_))");
		final bareBody = HxFunctionDecl.getBody(bare.getSourceDeclaration());
		final groupedBody = HxFunctionDecl.getBody(grouped.getSourceDeclaration());
		final fingerprint = TypedBodyFingerprint.exactStatements(bareBody);
		if (fingerprint == TypedBodyFingerprint.exactStatements(groupedBody)
			|| CompilerTypedTreeRevision.functionBody(bare) == CompilerTypedTreeRevision.functionBody(grouped))
			throw "bare and grouped wildcard provenance disappeared from a pattern revision";
		final barePattern = M14OptionalEnumPatternTest.names(TypedBodySource.functionProjection(bare))[0];
		final groupedPattern = M14OptionalEnumPatternTest.names(TypedBodySource.functionProjection(grouped))[0];
		switch [barePattern, groupedPattern] {
			case [PEnumExtract(_, _, true), PEnumExtract(_, _, false)]:
			case _:
				throw "source projection lost bare-versus-grouped wildcard provenance";
		}
		if (fingerprint != TypedBodyFingerprint.exactStatements(bareBody))
			throw "wildcard projection mutated authored syntax";

		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse('enum Value<T> { Build(a:T,b:Bool,c:String); } class Main {}', "Main.hx"));
		final index = TyperIndex.build([resolved]);
		final context = new TyperContext(index, "Main.hx", "Main", "", [], "Main");
		final owner = context.resolveType("Value");
		final parameter = TyNominalApplication.parameterIds(owner)[0];
		final input = TyType.nominal(owner.getIdentity(), [TyType.typeParameter(parameter)]);
		final invalidPatterns:Array<HxSwitchPattern> = [
			PEnumExtract("Build", [PWildcard]),
			PEnumExtract("Build", [PBind("a")], true),
			PEnumExtract("Build", [], true)
		];
		for (invalid in invalidPatterns) {
			var rejected = false;
			try {
				TyNamedPatternResolver.resolve(input, [invalid], context, HxPos.unknown());
			} catch (_:TyperError) {
				rejected = true;
			}
			if (!rejected)
				throw "absent or forged wildcard provenance granted required suffix coverage";
		}
		final child:HxSwitchPattern = PBind("a");
		final original:HxSwitchPattern = PEnumExtract("Build", [child, PWildcard], true);
		final facts = TyNamedPatternResolver.resolve(input, [original], context, HxPos.unknown());
		final bindings = new haxe.ds.StringMap<TyType>();
		bindings.set(parameter.getCanonicalKey(), TyType.fromHintText("Int"));
		final specialized = facts.substituteTypes(bindings, [original]);
		specialized.assertInput(TyType.nominal(owner.getIdentity(), [TyType.fromHintText("Int")]), [original]);
		final copied = specialized.projectPayloads([original]);
		switch [original, copied[0]] {
			case [
				PEnumExtract(_, [a, PWildcard], true),
				PEnumExtract(_, [b, PWildcard, PWildcard], true)
			] if (a == child && b == child):
			case _:
				throw "type substitution or catalog-free projection lost provenance, child identity, or full payload arity";
		}
		var rejected = false;
		try {
			facts.projectPayloads([PEnumExtract("Build", [child, PWildcard], false)]);
		} catch (_:String) {
			rejected = true;
		}
		if (!rejected)
			throw "written shapes accepted changed wildcard permission";
	}

	/** Nested qualified alternatives and guards keep exact declaration and binding occurrence order. */
	static function nested():Void {
		final module = M14OptionalEnumPatternTest.typed('enum Value { Build(a:Int,b:Bool,c:String); Other(a:Int,b:Bool,c:String); }'
			+ 'enum Outer { Wrap(value:Value,flag:Bool,text:String); }'
			+ 'class Main { static function read(value:Outer):Int return switch value {'
			+ 'case captured=(Outer.Wrap(Value.Build(a,_),_) | Outer.Wrap(Value.Other(a,_),_)) if (a>0):a; case _:0; }; }');
		final function_ = module.getTypedClasses().filter(owner -> HxClassDecl.getName(owner.getSourceDeclaration()) == "Main")[0].getFunctions()[0];
		final before = TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(function_.getSourceDeclaration()));
		final locals = function_.getEnvironment().getLocals().filter(local -> local.getKind() == PatternVariable);
		if (locals.length != 2
			|| locals[0].getName() != "captured"
			|| locals[1].getName() != "a"
			|| locals[1].getType().getSemanticKey() != "primitive:Int")
			throw "wildcard suffix changed capture or alternative binding order";
		final projection = TypedBodySource.functionProjection(function_);
		final patterns = M14OptionalEnumPatternTest.names(projection);
		if (patterns.length != 4)
			throw "wildcard suffix changed nested named occurrence count";
		final owners = ["Main.Outer", "Main.Value", "Main.Outer", "Main.Value"];
		for (index in 0...patterns.length) {
			final selected = projection.findNamedPattern(patterns[index]);
			if (selected == null)
				throw "wildcard suffix lost the exact named occurrence";
			switch [patterns[index], selected.getKind()] {
				case [PEnumExtract(_, children, true), Constructor(owner, _, _, 3)] if (children.length == 3
					&& owner.getCanonicalName() == owners[index]):
				case _:
					throw "wildcard suffix lost full arity, source permission, or selected enum owner";
			}
		}
		if (before != TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(function_.getSourceDeclaration())))
			throw "nested wildcard projection mutated authored patterns";
	}

	public static function check():Void {
		for (pattern in ["Build(a,_)", "Build(_)", "Build(a,_,b)", "Build(_,_,_)"])
			admission(pattern, true);
		for (pattern in [
			"Build(a)",
			"Build()",
			"Build(_,b)",
			"Build(a,_,_,_)",
			"Build(a,(_))",
			"Build(a,tail=_)",
			"Build(a,(_|_))"
		])
			admission(pattern, false);
		M14OptionalEnumPatternTest.admission("Build(a:Int,b:Null<Bool>);", "Build(1,null)", "Build(a)", false);
		M14OptionalEnumPatternTest.admission("Build(a:Int,b:Null<Bool>,c:String);", 'Build(1,null,"kept")', "Build(a,b)", false);
		M14OptionalEnumPatternTest.admission("Build(a:Int,b:Bool,c:String);", 'Value.Build(1,true,"kept")', "Other.Build(_)", false,
			"enum Other { Build(a:Int,b:Bool,c:String); }");
		sourceFacts();
		nested();
		Sys.println("ENUM_WILDCARD_SUFFIX_PATTERN:PASS");
	}
}
