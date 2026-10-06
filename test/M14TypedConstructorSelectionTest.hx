import TypedExpr.TypedExprTag;

/** Construction must retain its selected declaration through typed replay and exact generic application. */
class M14TypedConstructorSelectionTest {
	static function main():Void {
		final source = 'class Main { static function main() { var a = new First(2); var b = new Second(3); var c = new Box<String>("word"); var bad = new Box<Int>("wrong"); var ordinary = new Plain(); var badArity = new First(); } }'
			+ ' abstract First(Int) { public function new(value:Int) { this = value; } }'
			+ ' abstract Second(Int) { public function new(value:Int) { this = value + 1; } }'
			+ ' abstract Box<T>(T) { public function new(value:T) { this = value; } }'
			+ ' class Plain { public function new(value:Int = 4) {} }';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		var checked = 0;
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions()) {
				if (HxClassDecl.getName(cls.getSourceDeclaration()) != "Main")
					continue;
				for (statement in fn.getBody().getStatements()) {
					final expressions = statement.getExpressions();
					if (expressions.length != 1 || expressions[0].getTag() != NewValue)
						continue;
					final expression = expressions[0];
					final declaration = expression.getDeclaration();
					if (statement.getNames()[0] == "bad" || statement.getNames()[0] == "badArity") {
						if (declaration != null)
							throw "inapplicable generic constructor acquired a declaration";
					} else {
						final owner = expression.getType().getNominalIdentity();
						if (declaration == null
							|| owner == null
							|| !declaration.getOwner().equals(owner)
							|| declaration.getIsStatic()
							|| declaration.getSignature().getName() != "new")
							throw "construction lost its selected constructor: "
								+ statement.getNames()[0]
								+ " type="
								+ expression.getType().getSemanticKey()
								+ " declaration="
								+ (declaration == null ? "none" : declaration.getIdentity().getCanonicalKey());
						if (expression.withExpressions(expression.getExpressions()).getDeclaration() != declaration)
							throw "typed replay replaced the exact constructor declaration";
						if (statement.getNames()[0] == "c"
							&& expression.getType().getTypeArguments()[0].getSemanticKey() != "primitive:String")
							throw "constructor selection changed the applied generic result";
						final application = expression.getConstructorApplication();
						if (application == null
							|| application.getDeclaration() != declaration
							|| expression.withExpressions(expression.getExpressions()).getConstructorApplication() != application)
							throw "constructor application lost exact typed replay ownership";
						if (statement.getNames()[0] == "c") {
							final bindings = application.getOwnerArguments();
							if (bindings.length != 1
								|| bindings[0].argument.getSemanticKey() != "primitive:String"
								|| application.getParameterTypes()[0].getSemanticKey() != "primitive:String"
								|| application.getUnderlyingType().getSemanticKey() != "primitive:String")
								throw "constructor application lost exact owner substitution";
							bindings.resize(0);
							if (application.getOwnerArguments().length != 1)
								throw "caller mutated retained constructor owner bindings";
						}
						if (statement.getNames()[0] == "ordinary" && application.getUnderlyingType() != null)
							throw "ordinary construction gained an abstract backing type";
					}
					checked++;
				}
				TypedBodyInvariant.assertFunction(fn);
			}
		if (checked != 6)
			throw "constructor selection fixture lost a source occurrence";
		final first = index.getByFullName("Main.First");
		final second = index.getByFullName("Main.Second");
		final selected = first.declarationForSignature(first.instanceMethodCandidates("new")[0]);
		final foreign = second.declarationForSignature(second.instanceMethodCandidates("new")[0]);
		final constructed = TyType.nominal(first.getIdentity(), []);
		final value = TypedExpr.newValue("First", [TypedExpr.intLiteral(2, TyType.fromHintText("Int"), null)], constructed, null,
			new TypedConstructorApplication(first, selected, constructed));
		final missing = TypedExpr.newValue("First", value.getExpressions(), constructed, null);
		if (CompilerTypedTreeRevision.expression("probe", value) == CompilerTypedTreeRevision.expression("probe", missing))
			throw "constructor declaration does not participate in semantic revision";
		var rejected = false;
		try {
			new TypedConstructorApplication(first, foreign, constructed);
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("exact nominal constructor") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "foreign constructor facts passed publication invariants";
		var wrongResultRejected = false;
		try {
			value.withType(TyType.nominal(second.getIdentity(), []));
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("another applied result") < 0)
				throw error;
			wrongResultRejected = true;
		}
		if (!wrongResultRejected)
			throw "constructor application survived a foreign result relabel";
		Sys.println("TYPED_CONSTRUCTOR_SELECTION:PASS");
	}
}
