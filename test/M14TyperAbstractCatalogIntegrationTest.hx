import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;

/**
	Focused contract test for the shared abstract-operator declaration catalog.

	This test intentionally stops before expression binding. It proves that eager
	and lazy module loading assign the same semantic identities and that backends
	will later be able to consume one canonical declaration decision.
**/
class M14TyperAbstractCatalogIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertEquals(actual:String, expected:String, message:String):Void {
		if (actual != expected)
			throw message + "\nexpected:\n" + expected + "\nactual:\n" + actual;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function findUnary(info:TyAbstractInfo, op:HxUnaryOperator, fixity:HxUnaryFixity):TyAbstractOperatorInfo {
		final candidates = info.getUnaryOperators(op, fixity);
		assertTrue(candidates.length == 1, "expected exactly one "
			+ HxUnaryOperatorTools.sourceToken(op)
			+ " "
			+ Std.string(fixity)
			+ " declaration");
		return candidates[0];
	}

	static function indexFailure(source:String, filePath:String):String {
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule(haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(filePath)), filePath, parsed);
		var failure:Null<String> = null;
		try {
			TyperIndex.build([resolved]);
		} catch (error:TyperError) {
			failure = error.toString();
		}
		assertTrue(failure != null, "expected semantic index construction to reject malformed operator metadata");
		return failure;
	}

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize(".tmp/m14_typer_abstract_catalog_" + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, "src"]);
		final packageDir = haxe.io.Path.join([srcDir, "demo"]);
		final supportDir = haxe.io.Path.join([srcDir, "support"]);
		final catalogPath = haxe.io.Path.join([packageDir, "Catalog.hx"]);
		final carrierPath = haxe.io.Path.join([supportDir, "Carrier.hx"]);
		final decoyPath = haxe.io.Path.join([packageDir, "Decoy.hx"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);
		FileSystem.createDirectory(packageDir);
		FileSystem.createDirectory(supportDir);

		final source = [
			"package demo;",
			"import support.Carrier;",
			"abstract Scalar<T>(Int) {",
			"  @:op(-A)",
			"  public static function arbitraryNeg(value:Scalar<T>):Scalar<T> return value;",
			"  @:op(++A)",
			"  public inline function arbitraryPrefix():Scalar<T> return this;",
			"  @:op(A++)",
			"  public function arbitraryPostfix():Void {}",
			"  @:op(~a)",
			"  public static function arbitraryComplement(value:Scalar<T>):Scalar<T> return value;",
			"  @:op(!A)",
			"  public static function genericNot<U:Int>(value:Scalar<U>):Scalar<U> return value;",
			"  @:op([])",
			"  public function deferredArrayAccess(index:Int):Scalar<T> return this;",
			"  @:optional",
			"  public static function operatorPrefixMetadataControl():Void;",
			"}",
			"abstract NullableNumber(Null<Float>) from Null<Float> to Null<Float> {}",
			"class Ordinary {",
			"  @:op(-A)",
			"  public static function misleading(value:Ordinary):Ordinary return value;",
			"  overload public static function choose(value:Int):Int;",
			"  overload public static function choose(value:String):String;",
			"  public static function carrier(value:Carrier):Carrier return value;",
			"}",
		].join("\n");
		File.saveContent(catalogPath, source);
		final carrierSource = "package support; class Carrier {}";
		final decoySource = "package demo; class Decoy {} class Carrier {}";
		File.saveContent(carrierPath, carrierSource);
		File.saveContent(decoyPath, decoySource);

		final primaryAbstractSource = [
			"abstract Ticket(String) {",
			"  public inline function new(value:String) this = value;",
			"  public static function empty():Ticket return new Ticket(null);",
			"}",
		].join("\n");
		final primaryAbstract = ParserStage.parse(primaryAbstractSource, haxe.io.Path.join([srcDir, "Ticket.hx"]));
		assertEquals(HxClassDecl.getName(HxModuleDecl.getMainClass(primaryAbstract.getDecl())), "Ticket",
			"a module's file-matching abstract must be its primary declaration");
		assertTrue(HxClassDecl.getFunctions(HxModuleDecl.getMainClass(primaryAbstract.getDecl())).filter(function(fn) {
			return HxFunctionDecl.getName(fn) == "empty" && HxFunctionDecl.getIsStatic(fn);
		}).length == 1,
			"the primary abstract lost its public static function before semantic indexing");

		final parsed = ParserStage.parse(source, catalogPath);
		final resolved = new ResolvedModule("demo.Catalog", catalogPath, parsed);
		final carrierResolved = new ResolvedModule("support.Carrier", carrierPath, ParserStage.parse(carrierSource, carrierPath));
		final decoyResolved = new ResolvedModule("demo.Decoy", decoyPath, ParserStage.parse(decoySource, decoyPath));
		final eager = TyperIndex.build([resolved, carrierResolved, decoyResolved]);
		final eagerAgain = TyperIndex.build([resolved, carrierResolved, decoyResolved]);
		final eagerReordered = TyperIndex.build([decoyResolved, carrierResolved, resolved]);
		assertEquals(eager.semanticDump(), eagerAgain.semanticDump(), "identical eager builds must produce identical semantic identities");
		assertEquals(eager.semanticDump(), eagerReordered.semanticDump(), "semantic identities must not depend on resolved-module traversal order");

		final scalar = eager.getAbstractByFullName("demo.Catalog.Scalar");
		assertTrue(scalar != null, "expected Scalar to be represented by TyAbstractInfo");
		assertEquals(scalar.getIdentity().getCanonicalName(), "demo.Catalog.Scalar", "unexpected canonical abstract identity");
		assertEquals(scalar.getUnderlyingType().getSemanticKey(), "primitive:Int", "primitive carrier must not replace abstract identity");
		assertEquals(scalar.getTypeParameters().join(","), "T", "abstract type parameters were not retained");
		assertTrue(scalar.getAllUnaryOperators().length == 5, "non-operator metadata beginning with 'op' was misclassified as @:op");
		final nullableNumber = eager.getAbstractByFullName("demo.Catalog.NullableNumber");
		assertTrue(nullableNumber != null, "expected nullable conversion control to be indexed as an abstract");
		assertTrue(nullableNumber.getImplicitFromTypes().length == 1, "abstract header should retain exactly one from-type");
		assertTrue(nullableNumber.getImplicitToTypes().length == 1, "abstract header should retain exactly one to-type");
		assertEquals(nullableNumber.getImplicitFromTypes()[0].getSemanticKey(), "nullable:primitive:Float",
			"abstract header from-type was not retained as a semantic conversion");
		assertEquals(nullableNumber.getImplicitToTypes()[0].getSemanticKey(), "nullable:primitive:Float",
			"abstract header to-type was not retained as a semantic conversion");

		final neg = findUnary(scalar, HxUnaryOperator.Negate, HxUnaryFixity.Prefix);
		assertEquals(neg.getDeclaration().getSignature().getName(), "arbitraryNeg", "operator catalog selected by helper name");
		assertTrue(neg.getDeclaration().getIsStatic(), "static operator declaration lost its static form");
		assertTrue(!neg.getDeclaration().getIsInline(), "non-inline static helper was marked inline");
		assertEquals(neg.getOperandType().getNominalIdentity().getCanonicalName(), "demo.Catalog.Scalar",
			"static unary operand lost its abstract semantic identity");
		final abstractParameter = neg.getOperandType().getTypeArguments()[0].getTypeParameterIdentity();
		assertTrue(abstractParameter != null
			&& abstractParameter.getName() == "T"
			&& abstractParameter.getScopeIdentity() == "nominal:demo.Catalog.Scalar",
			"applied abstract type argument was not represented by its exact nominal binder");
		assertEquals(neg.getResultType().getSemanticKey(), neg.getOperandType().getSemanticKey(),
			"operator result type must come from the declaration signature");

		final prefix = findUnary(scalar, HxUnaryOperator.Increment, HxUnaryFixity.Prefix);
		assertTrue(!prefix.getDeclaration().getIsStatic(), "instance prefix helper was marked static");
		assertTrue(prefix.getDeclaration().getIsInline(), "inline modifier was discarded before semantic indexing");
		assertTrue(HxFunctionDecl.getBody(prefix.getDeclaration().getSourceDeclaration()).length > 0,
			"shared declaration record lost its source/body reference");
		assertTrue(prefix.getDeclaration().getPosition().getLine() > 0, "shared declaration record lost its source position");

		final postfix = findUnary(scalar, HxUnaryOperator.Increment, HxUnaryFixity.Postfix);
		assertTrue(!postfix.getDeclaration().getIsStatic(), "instance postfix helper was marked static");
		assertTrue(!postfix.getDeclaration().getIsInline(), "non-inline postfix helper was marked inline");
		assertEquals(postfix.getResultType().getSemanticKey(), "primitive:Void", "postfix spelling overrode the declared Void result");
		final complement = findUnary(scalar, HxUnaryOperator.BitwiseNot, HxUnaryFixity.Prefix);
		assertEquals(complement.getDeclaration().getSignature().getName(), "arbitraryComplement",
			"lowercase operator placeholders accepted by Haxe 4.3.7 were not cataloged");
		final genericNot = findUnary(scalar, HxUnaryOperator.LogicalNot, HxUnaryFixity.Prefix);
		assertEquals(genericNot.getDeclaration().getTypeParameters().join(","), "U", "method-level operator type parameters were discarded");
		assertEquals(genericNot.getDeclaration().getTypeParameterConstraints().get("U"), "Int", "method-level operator constraint metadata was discarded");
		final methodParameter = genericNot.getOperandType().getTypeArguments()[0].getTypeParameterIdentity();
		assertTrue(methodParameter != null
			&& methodParameter.getName() == "U"
			&& StringTools.startsWith(methodParameter.getScopeIdentity(), "method:demo.Catalog.Scalar#"),
			"method-level operator type argument was not represented by its exact method binder");

		final ordinary = eager.getByFullName("demo.Catalog.Ordinary");
		assertTrue(ordinary != null && Std.isOfType(ordinary, TyClassInfo), "ordinary class must remain TyClassInfo");
		assertTrue(ordinary.getDeclarations().length == 4, "abstract members leaked into the ordinary class declaration table before semantic indexing");
		assertTrue(eager.getUnaryOperators(ordinary.getIdentity(), HxUnaryOperator.Negate, HxUnaryFixity.Prefix).length == 0,
			"ordinary class acquired operator behavior from @:op-like metadata");
		final chooseIds = [
			for (declaration in ordinary.getDeclarations())
				if (declaration.getSignature().getName() == "choose") declaration.getIdentity().getCanonicalKey()
		];
		assertTrue(chooseIds.length == 2 && chooseIds[0] != chooseIds[1], "overloaded declarations did not receive distinct stable identities");
		final carrierDeclarations = [
			for (declaration in ordinary.getDeclarations())
				if (declaration.getSignature().getName() == "carrier") declaration
		];
		assertTrue(carrierDeclarations.length == 1, "expected cross-module declaration control");
		assertEquals(carrierDeclarations[0].getSignature().getArgs()[0].getSemanticKey(), "nominal:support.Carrier",
			"eager two-pass indexing did not resolve the explicitly imported later module identity");

		final lazy = new TyperIndex();
		final loader = new ModuleLoader([srcDir], new StringMap<String>(), lazy);
		assertTrue(loader.ensureTypeAvailable("demo.Decoy.Carrier", "", []) != null, "expected lazy control to load the colliding short-name type");
		final lazyScalar = loader.ensureTypeAvailable("demo.Catalog.Scalar", "", []);
		assertTrue(lazyScalar != null
			&& Std.isOfType(lazyScalar, TyAbstractInfo), "lazy loading did not index the abstract semantic surface");
		assertEquals(lazy.semanticDump(), eager.semanticDump(), "eager and lazy module loading assigned different identities or catalog entries");

		final malformedSource = [
			"abstract Bad(Int) {",
			"  @:op()",
			"  public static function broken(value:Bad):Bad return value;",
			"}",
		].join("\n");
		final malformedPath = haxe.io.Path.join([tmpRoot, "Malformed.hx"]);
		File.saveContent(malformedPath, malformedSource);
		final malformedFirst = indexFailure(malformedSource, malformedPath);
		final malformedSecond = indexFailure(malformedSource, malformedPath);
		assertEquals(malformedFirst, malformedSecond, "malformed metadata diagnostic was nondeterministic");
		assertTrue(malformedFirst.indexOf("Malformed @:op metadata") >= 0, "malformed metadata diagnostic lacks a stable category");
		final trailingSource = [
			"abstract Trailing(Int) {",
			"  @:op(A nope)",
			"  public static function broken(value:Trailing):Trailing return value;",
			"}",
		].join("\n");
		final trailingPath = haxe.io.Path.join([tmpRoot, "Trailing.hx"]);
		File.saveContent(trailingPath, trailingSource);
		final trailingFailure = indexFailure(trailingSource, trailingPath);
		assertTrue(trailingFailure.indexOf("Malformed @:op metadata") >= 0, "operator metadata with trailing input was accepted as a valid expression prefix");

		final duplicateSource = [
			"abstract Duplicate(Int) {",
			"  @:op(-A) @:op(-A)",
			"  public static function duplicate(value:Duplicate):Duplicate return value;",
			"}",
		].join("\n");
		final duplicatePath = haxe.io.Path.join([tmpRoot, "Duplicate.hx"]);
		File.saveContent(duplicatePath, duplicateSource);
		final duplicateFailure = indexFailure(duplicateSource, duplicatePath);
		assertTrue(duplicateFailure.indexOf("Duplicate unary @:op metadata") >= 0, "duplicate metadata diagnostic lacks a stable category");

		final shapeSource = [
			"abstract WrongShape(Int) {",
			"  @:op(-A)",
			"  public static function missingOperand():WrongShape;",
			"}",
		].join("\n");
		final shapePath = haxe.io.Path.join([tmpRoot, "WrongShape.hx"]);
		File.saveContent(shapePath, shapeSource);
		final shapeFailure = indexFailure(shapeSource, shapePath);
		assertTrue(shapeFailure.indexOf("requires exactly one explicit argument") >= 0,
			"incompatible unary declaration shape was not diagnosed at index construction");

		deleteRecursive(tmpRoot);
	}
}
