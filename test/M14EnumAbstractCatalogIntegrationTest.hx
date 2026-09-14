import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Prove that enum-abstract methods reach the shared declaration catalog.

	The same upstream-valid declaration is a primary type and a module-local type.
	Checks cover signatures, source bodies, values, and eager/lazy loading identity.
	Expression binding and target-specific representation remain separate contracts.
**/
class M14EnumAbstractCatalogIntegrationTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function unary(info:TyAbstractInfo, op:HxUnaryOperator, fixity:HxUnaryFixity):TyAbstractOperatorInfo {
		final operators = info.getUnaryOperators(op, fixity);
		require(operators.length == 1, "expected one enum-abstract unary declaration: " + Std.string(op) + " " + Std.string(fixity));
		return operators[0];
	}

	/** Check both file ownership forms against explicit, independently written expectations. */
	static function check(source:String, directory:String, moduleName:String):Void {
		final filePath = Path.join([directory, moduleName + ".hx"]);
		File.saveContent(filePath, source);
		final parsed = ParserStage.parse(source, filePath);
		final classes = HxModuleDecl.getClasses(parsed.getDecl());
		final counters = classes.filter(c -> HxClassDecl.getName(c) == "Counter");
		require(counters.length == 1, "enum abstract was lost or duplicated");
		final counter = counters[0];
		if (moduleName == "Counter")
			require(HxClassDecl.getName(HxModuleDecl.getMainClass(parsed.getDecl())) == "Counter", "primary enum abstract was not selected");
		final functions = HxClassDecl.getFunctions(counter);
		require(functions.length == 5, "enum abstract lost its five method declarations");
		for (fn in functions) {
			require(HxFunctionDecl.getHasBody(fn) && HxFunctionDecl.getBody(fn).length > 0, "method lost its parsed body");
			require(HxFunctionDecl.getBodyText(fn).length > 0, "method lost its source body text");
			require(HxFunctionDecl.getPos(fn).getLine() > 0
				&& HxFunctionDecl.getEndPos(fn).getLine() >= HxFunctionDecl.getPos(fn).getLine(),
				"method lost its source range");
		}
		final hidden = functions.filter(fn -> HxFunctionDecl.getName(fn) == "hidden");
		require(hidden.length == 1
			&& HxFunctionDecl.getVisibility(hidden[0]) == HxVisibility.Private, "private method visibility changed");
		final read = functions.filter(fn -> HxFunctionDecl.getName(fn) == "read");
		require(read.length == 1 && HxFunctionDecl.getReturnTypeHint(read[0]) == "Int", "ordinary method result type changed");
		final args = HxFunctionDecl.getArgs(read[0]);
		require(args.length == 1
			&& HxFunctionArg.getIsOptional(args[0])
			&& HxFunctionArg.getTypeHint(args[0]) == "Int"
			&& HxFunctionArg.getDefaultValueText(args[0]) == "0",
			"optional argument type or default changed");
		final fields = HxClassDecl.getFields(counter);
		require(fields.length == 2, "enum value fields were lost or duplicated");
		for (i in 0...fields.length) {
			require(HxFieldDecl.getName(fields[i]) == (i == 0 ? "One" : "Three")
				&& HxFieldDecl.getIsStatic(fields[i])
				&& HxFieldDecl.getVisibility(fields[i]) == HxVisibility.Public,
				"enum value identity or implicit public/static form changed");
			require(switch (HxFieldDecl.getInit(fields[i])) {
				case EInt(value): value == (i == 0 ? 1 : 3);
				case _: false;
			}, "enum value initializer changed");
		}

		final resolved = new ResolvedModule(moduleName, filePath, parsed);
		final eager = TyperIndex.build([resolved]);
		final fullName = moduleName == "Counter" ? "Counter" : moduleName + ".Counter";
		final info = eager.getAbstractByFullName(fullName);
		require(info != null && info.getUnderlyingType().getSemanticKey() == "primitive:Int", "enum abstract lost its semantic carrier");
		require(info.getTypeParameters().join(",") == "T", "enum abstract lost its generic header");
		require(HxClassDecl.getMetadata(counter).indexOf("keep") >= 0, "enum abstract lost type metadata");
		require(info.getImplicitFromTypes().length == 1
			&& info.getImplicitFromTypes()[0].getSemanticKey() == "primitive:Int"
			&& info.getImplicitToTypes().length == 1
			&& info.getImplicitToTypes()[0].getSemanticKey() == "primitive:Int",
			"header conversions changed");
		final negation = unary(info, HxUnaryOperator.Negate, HxUnaryFixity.Prefix);
		final declaration = negation.getDeclaration();
		require(switch (HxFunctionDecl.getBody(declaration.getSourceDeclaration())) {
			case [SVar(_, _, _, _), SIf(_, _, _, _), SReturn(_, _)]: true;
			case _: false;
		}, "branching static operator body was flattened or discarded");
		require(declaration.getSignature().getName() == "reverse" && declaration.getIsStatic() && !declaration.getIsInline(),
			"arbitrary-name static operator metadata changed");
		require(declaration.getTypeParameters().join(",") == "U" && declaration.getTypeParameterConstraints().get("U") == "Int",
			"operator method generic parameter or constraint changed");
		require(negation.getOperandType().getNominalIdentity().getCanonicalName() == fullName
			&& negation.getResultType().getSemanticKey() == negation.getOperandType().getSemanticKey(),
			"operator operand/result identity changed");
		for (fixity in [HxUnaryFixity.Prefix, HxUnaryFixity.Postfix]) {
			final increment = unary(info, HxUnaryOperator.Increment, fixity).getDeclaration();
			require(!increment.getIsStatic() && increment.getIsInline(), "instance inline operator modifiers changed");
		}
		final plain = eager.getByFullName(moduleName + ".Plain");
		require(plain != null && !Std.isOfType(plain, TyAbstractInfo), "ordinary enum became an abstract");
		final plainClasses = classes.filter(c -> HxClassDecl.getName(c) == "Plain");
		require(plainClasses.length == 1
			&& HxClassDecl.getFunctions(plainClasses[0]).length == 1
			&& HxFunctionDecl.getName(HxClassDecl.getFunctions(plainClasses[0])[0]) == "Wrapped",
			"ordinary enum constructor changed");
		require(eager.getUnaryOperators(plain.getIdentity(), HxUnaryOperator.Negate, HxUnaryFixity.Prefix).length == 0,
			"operator declarations leaked into an ordinary enum");
		final neighbor = classes.filter(c -> HxClassDecl.getName(c) == "Neighbor");
		require(neighbor.length == 1
			&& HxClassDecl.getFunctions(neighbor[0]).length == 1
			&& HxFunctionDecl.getName(HxClassDecl.getFunctions(neighbor[0])[0]) == "marker",
			"members leaked into a neighboring class");

		final lazy = new TyperIndex();
		final loader = new ModuleLoader([directory], new StringMap<String>(), lazy);
		require(loader.ensureTypeAvailable(fullName, "", []) != null, "lazy loading lost the enum abstract");
		require(lazy.semanticDump() == eager.semanticDump(), "eager/lazy catalog identities differ");
		FileSystem.deleteFile(filePath);
	}

	static function main():Void {
		final source = File.getContent("test/enum_abstract_catalog/Counter.hx");
		final directory = Path.join([".tmp", "enum_abstract_catalog_" + Std.string(Date.now().getTime())]);
		FileSystem.createDirectory(directory);
		check(source, directory, "Counter");
		check(source, directory, "Catalog");
		FileSystem.deleteDirectory(directory);
		Sys.println("ENUM_ABSTRACT_CATALOG:PASS");
	}
}
