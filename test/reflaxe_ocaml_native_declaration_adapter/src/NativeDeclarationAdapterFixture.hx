import backend.ocaml.HxhxOcamlTargetDeclarationAdapter;
import backend.ocaml.HxhxOcamlTargetBindingAdapter;
import backend.ocaml.HxhxOcamlTargetLiteralAdapter;
import backend.ocaml.HxhxOcamlTargetExpressionAdapter;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.OcamlTargetExpressionFact;
import reflaxe.ocaml.target.OcamlTargetExpressionLowerer;
import reflaxe.ocaml.target.OcamlTargetExpressionPath;
import reflaxe.ocaml.target.OcamlTargetFunctionCatalog;
import reflaxe.ocaml.target.OcamlTargetFunctionFact;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionRole;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionSignature;
import reflaxe.ocaml.target.OcamlTargetFunctionLowerer;
import reflaxe.ocaml.target.OcamlTargetLiteralLowerer;
import reflaxe.ocaml.target.OcamlTargetLiteralLowerer.OcamlTargetLiteralCarrier;

/** Verifies that the native adapter compiles without a macro-host compatibility layer. **/
class NativeDeclarationAdapterFixture {
	static function main():Void {
		final owner = new TyNominalTypeId("unit.NativeSample");
		final fields = new haxe.ds.StringMap<TyFieldInfo>();
		fields.set("count", new TyFieldInfo(owner, "unit.NativeSample", "count", TyType.fromHintText("Int"), false, true, false, false, true));
		final info = new TyClassInfo(owner, "NativeSample", "unit.NativeSample", fields, new haxe.ds.StringMap(), new haxe.ds.StringMap(),
			new haxe.ds.StringMap(), new haxe.ds.StringMap(), new haxe.ds.StringMap(), [], Public, false);
		final request = HxhxOcamlTargetDeclarationAdapter.fromClassFacts("native-fixture-program", [new TypedBackendClassSemanticFacts(info, null)]);
		final classes = request.copyClasses();
		if (classes.length != 1 || classes[0].copyFields().length != 1 || classes[0].copyFields()[0].typeDisplay != "Int")
			throw "native semantic field was not copied into target-owned facts";
		final nativeInt = HxhxOcamlTargetLiteralAdapter.fromExpression(TypedExpr.intLiteral(7, TyType.fromHintText("Int"), HxPos.unknown()));
		if (nativeInt == null || nativeInt.getCanonicalIdentity() != LiteralIdentityMacro.stockInt())
			throw "stock Haxe and native hxhx produced different integer literal facts";
		if (new OcamlASTPrinter().printExpr(OcamlTargetLiteralLowerer.buildNonNull(nativeInt, Direct)) != "7")
			throw "native host could not execute the standalone target literal lowerer";
		if (HxhxOcamlTargetLiteralAdapter.fromExpression(TypedExpr.floatLiteral(1.5, TyType.fromHintText("Float"), HxPos.unknown())) != null)
			throw "native adapter admitted a float before the numeric review contract";
		final localId = TyLocalId.forSourceDeclaration("unit.BindingFixture.run", 0, Variable, "value");
		final binding = new TyLocalBinding(localId, "value", TyType.fromHintText("Int"), Variable);
		final nativeBinding = HxhxOcamlTargetBindingAdapter.fromBinding(binding, "root/block-item/0/binding");
		if (nativeBinding.getCanonicalIdentity() != BindingIdentityMacro.stockVariable())
			throw "stock Haxe and native hxhx produced different source-binding facts";
		final renumberedId = TyLocalId.forSourceDeclaration("unit.BindingFixture.run", 99, Variable, "value");
		final renumberedBinding = new TyLocalBinding(renumberedId, "value", TyType.fromHintText("Int"), Variable);
		final renumberedFact = HxhxOcamlTargetBindingAdapter.fromBinding(renumberedBinding, "root/block-item/0/binding");
		if (renumberedFact.getCanonicalIdentity() != nativeBinding.getCanonicalIdentity())
			throw "native traversal allocation leaked into the target-owned binding fact";
		if (HxhxOcamlTargetBindingAdapter.fromBinding(binding, "root/block-item/1/binding").getCanonicalIdentity() == nativeBinding.getCanonicalIdentity())
			throw "two structural declaration paths claimed one target-owned binding fact";
		if (localId.getCanonicalKey() != "unit.BindingFixture.run#local:0:variable:5:value")
			throw "structured native binding access changed the existing local key";
		assertCompilerTemporaryRejected();
		assertRecursiveExpression(binding);
		assertRecursiveFunction();
		assertUnsupportedExpressionFallsBack();
		Sys.println("HXHX_OCAML_TARGET_DECLARATION_ADAPTER:PASS");
	}

	static function assertRecursiveFunction():Void {
		final signature:OcamlTargetFunctionSignature = {
			moduleId: "unit.NativeSample",
			sourceTypeName: "NativeSample",
			sourceFunctionName: "main",
			role: OcamlTargetFunctionRole.StaticFunction,
			argumentTypeDisplays: [],
			returnTypeDisplay: "Void"
		};
		final targetIdentity = OcamlTargetFunctionFact.identityFor(signature);
		final intType = TyType.fromHintText("Int");
		final voidType = TyType.fromHintText("Void");
		final localId = TyLocalId.forSourceDeclaration(targetIdentity, 0, Variable, "value");
		final binding = new TyLocalBinding(localId, "value", intType, Variable);
		final initializer = TypedExpr.intLiteral(7, intType, HxPos.unknown());
		final declaration = TypedExpr.variableDeclaration("value", "Int", initializer, false, false, intType, HxPos.unknown(), binding);
		final declarations = TypedExpr.variableDeclarations([declaration], voidType, HxPos.unknown());
		final read = TypedExpr.localRead("value", intType, HxPos.unknown(), binding);
		final ignoredId = TyLocalId.forSourceDeclaration(targetIdentity, 1, Variable, "ignored");
		final ignoredBinding = new TyLocalBinding(ignoredId, "ignored", intType, Variable);
		final ignoredInitializer = TypedExpr.intLiteral(8, intType, HxPos.unknown());
		final ignoredDeclaration = TypedExpr.variableDeclaration("ignored", "Int", ignoredInitializer, false, false, intType, HxPos.unknown(), ignoredBinding);
		final ignoredDeclarations = TypedExpr.variableDeclarations([ignoredDeclaration], voidType, HxPos.unknown());
		final body = TypedExpr.block([declarations, read, ignoredDeclarations], voidType, HxPos.unknown());
		final bodyFact = HxhxOcamlTargetExpressionAdapter.fromExpression(body);
		if (bodyFact == null)
			throw "native hxhx adapter rejected the shared target function body";
		final fact = new OcamlTargetFunctionFact(signature, bodyFact);
		if (fact.getCanonicalIdentity() != BindingIdentityMacro.stockFunction())
			throw "stock Haxe and native hxhx produced different target function facts";
		final rendered = new OcamlASTPrinter().printExpr(OcamlTargetFunctionLowerer.build(fact));
		if (rendered.indexOf("fun () -> ignore (let value = 7 in") != 0)
			throw 'native hxhx could not execute the target function lowerer: $rendered';
		final catalog = new OcamlTargetFunctionCatalog();
		catalog.register("native-host-main", fact);
		if (catalog.find("native-host-main") != fact)
			throw "target function catalog lost its registered fact";
		catalog.beginRequest();
		if (catalog.find("native-host-main") != null)
			throw "target function catalog retained a host handle across requests";
	}

	static function assertUnsupportedExpressionFallsBack():Void {
		if (!BindingIdentityMacro.stockUnsupportedExpression())
			throw "stock Haxe adapter admitted an unsupported expression carrier";
		final nullableInt = TyType.fromHintText("Null<Int>");
		final bindingId = TyLocalId.forSourceDeclaration("unit.BindingFixture.unsupported", 0, Variable, "value");
		final binding = new TyLocalBinding(bindingId, "value", nullableInt, Variable);
		final initializer = TypedExpr.intLiteral(7, TyType.fromHintText("Int"), HxPos.unknown());
		final declaration = TypedExpr.variableDeclaration("value", "Null<Int>", initializer, false, false, nullableInt, HxPos.unknown(), binding);
		final declarations = TypedExpr.variableDeclarations([declaration], TyType.fromHintText("Void"), HxPos.unknown());
		final read = TypedExpr.localRead("value", nullableInt, HxPos.unknown(), binding);
		final body = TypedExpr.block([declarations, read], nullableInt, HxPos.unknown());
		if (HxhxOcamlTargetExpressionAdapter.fromExpression(body) != null)
			throw "native hxhx adapter admitted an unsupported local-initializer conversion";
	}

	static function assertRecursiveExpression(binding:TyLocalBinding):Void {
		final intType = TyType.fromHintText("Int");
		final voidType = TyType.fromHintText("Void");
		final initializer = TypedExpr.intLiteral(7, intType, HxPos.unknown());
		final declaration = TypedExpr.variableDeclaration("value", "Int", initializer, false, false, intType, HxPos.unknown(), binding);
		final declarations = TypedExpr.variableDeclarations([declaration], voidType, HxPos.unknown());
		final read = TypedExpr.localRead("value", intType, HxPos.unknown(), binding);
		final body = TypedExpr.block([declarations, read], intType, HxPos.unknown());
		final fact = HxhxOcamlTargetExpressionAdapter.fromExpression(body);
		if (fact == null || fact.getCanonicalIdentity() != BindingIdentityMacro.stockExpression())
			throw "stock Haxe and native hxhx produced different recursive expression facts";
		if (new OcamlASTPrinter().printExpr(OcamlTargetExpressionLowerer.build(fact)) != "let value = 7 in value")
			throw "native host could not execute the recursive standalone target lowerer";
		assertDanglingReadRejected(fact);
	}

	static function assertDanglingReadRejected(valid:OcamlTargetExpressionFact):Void {
		final children = valid.copyChildren();
		final declaration = children[0];
		final binding = declaration.binding;
		if (binding == null)
			throw "recursive expression fixture lost its declaration binding";
		final read = OcamlTargetExpressionFact.localRead(OcamlTargetExpressionPath.indexed(OcamlTargetExpressionPath.ROOT, "block-item", 0), "Int", binding);
		final dangling = OcamlTargetExpressionFact.block(OcamlTargetExpressionPath.ROOT, "Int", [read]);
		var rejected = false;
		try {
			OcamlTargetExpressionLowerer.build(dangling);
		} catch (_:String) {
			rejected = true;
		}
		if (!rejected)
			throw "recursive standalone target lowerer admitted a dangling local read";
	}

	static function assertCompilerTemporaryRejected():Void {
		final temporaryId = TyLocalId.forCompilerTemporary("unit.BindingFixture.run", "binding-fixture-v1", 0, "temporary");
		final temporary = new TyLocalBinding(temporaryId, "temporary", TyType.fromHintText("Int"), CompilerTemporary);
		var rejected = false;
		try {
			HxhxOcamlTargetBindingAdapter.fromBinding(temporary, "root/block-item/0/binding");
		} catch (_:String) {
			rejected = true;
		}
		if (!rejected)
			throw "native OCaml binding adapter admitted a compiler temporary";
	}
}
