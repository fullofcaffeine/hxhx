import backend.ocaml.Stage3OcamlClassStorage;
import sys.io.File;

/** Prove native class representation selection and the ownership of its typed operations. */
class M14NativeClassStorageTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function reject(action:Void->Void, diagnostic:String):Void {
		var rejected = false;
		try {
			action();
		} catch (error:String) {
			rejected = error.indexOf(diagnostic) >= 0;
		}
		require(rejected, "missing ownership rejection: " + diagnostic);
	}

	/** Ancestry includes runtime and extern parents without assigning them generated object storage. */
	static function providerAncestry():Void {
		for (externParent in [false, true]) {
			final source = "class Main extends Parent implements ChildMarker {} "
				+ (externParent ? "extern " : "")
				+ "class Parent implements ParentMarker {} "
				+ "interface ParentMarker extends Root {} interface ChildMarker extends Root {} interface Root {}";
			final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			final classes = typed.getBackendProjection().getClasses();
			final child = classes.filter(owner -> HxClassDecl.getName(owner.getDeclaration()) == "Main")[0];
			final parent = classes.filter(owner -> HxClassDecl.getName(owner.getDeclaration()) == "Parent")[0];
			final storage = new Stage3OcamlClassStorage();
			for (owner in classes)
				storage.add(owner, !externParent && owner == parent);
			final quote = (value:String) -> '"' + value + '"';
			if (externParent)
				reject(() -> storage.classRegistration(child, quote), "extern reflection requires a target-owned runtime identity");
			else
				require(storage.classRegistration(child,
					quote) == 'let () = HxType.register_class_tags "Main" ["Main"; "Parent"; "ParentMarker"; "Root"; "ChildMarker"]',
					"provider ancestry lost an exact parent or repeated a shared interface");
			final parentInfo = typed.getTypedClasses().filter(owner -> owner.getSemanticInfo().getShortName() == "Parent")[0];
			final parentType = TyType.nominal(parentInfo.getSemanticInfo().getIdentity(), []);
			require(storage.nominalName(parentType) == null, "ancestry metadata admitted a provider to typed catches");
			require(!storage.usesIdentity(parentType), "ancestry metadata admitted a provider to generated storage");
			require(storage.classRegistration(parent, quote) == null, "generated code registered a provider-owned class");
			require(storage.instanceInitializers(parent) == null, "provider acquired generated instance initializers");
			reject(() -> storage.add(parent, !externParent), "owner registered twice");
			final incomplete = new Stage3OcamlClassStorage();
			incomplete.add(child, false);
			reject(() -> incomplete.classRegistration(child, quote), "lacks exact ancestor facts: Main.Parent");
		}
		Sys.println("NATIVE_CLASS_PROVIDER_ANCESTRY:PASS");
	}

	/** Reconstructed syntax and independently typed declarations cannot borrow current storage facts. */
	static function ownership():Void {
		final source = "class Main { public var length:Int; static var initial:Bool = new Main() == new Main(); "
			+ "public function new() {} static function probe(a:Main, b:Main):Bool return a == b; "
			+ "static function read(a:Main):Int return a.length; } extern class Native { public var length:Int; } abstract Count(Int) {}";
		function typed():TypedModule {
			final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		}
		final first = typed();
		final second = typed();
		final classes = first.getBackendProjection().getClasses();
		final storage = new Stage3OcamlClassStorage();
		for (owner in classes)
			storage.add(owner, false);
		reject(() -> storage.classRegistration(second.getBackendProjection().getClasses()[0], value -> '"' + value + '"'), "exact class projection");
		for (owner in first.getTypedClasses()) {
			final type = TyType.nominal(owner.getSemanticInfo().getIdentity(), []);
			require(storage.usesIdentity(type) == (owner.getSemanticInfo().getShortName() == "Main"), "wrong class representation selection");
		}
		final runtimeStorage = new Stage3OcamlClassStorage();
		runtimeStorage.add(classes[0], true);
		require(runtimeStorage.nominalName(TyType.nominal(first.getTypedClasses()[0].getSemanticInfo().getIdentity(), [])) == null,
			"runtime provider borrowed ordinary class tags");
		require(!runtimeStorage.usesIdentity(TyType.nominal(first.getTypedClasses()[0].getSemanticInfo().getIdentity(), [])),
			"runtime provider acquired generated class storage");
		var equalityCount = 0;
		var fieldCount = 0;
		for (fn in classes[0].getFunctions()) {
			final foreign = second.getBackendProjection()
				.getClasses()[0].getFunctions()
				.filter(other -> HxFunctionDecl.getName(other.getDeclaration()) == HxFunctionDecl.getName(fn.getDeclaration()))[0];
			TypedBackendSourceWalk.functionDeclaration(fn.getDeclaration(), expression -> {
				final field = fn.findField(expression);
				if (field != null && !field.getField().getIsStatic())
					require(storage.read(field, _ -> "receiver", "this_", value -> '"' + value + '"') != null, "owned class field lost storage");
				final equality = fn.findEquality(expression);
				if (equality != null) {
					equalityCount++;
					require(foreign.findEquality(expression) == null, "foreign function borrowed equality");
					require(fn.findEquality(EBinop("==", equality.left, equality.right)) == null, "copied equality borrowed facts");
					reject(() -> equality.assertCurrent("foreign", fn.getBodyRevision()), "another executable");
				}
			}, _ -> {});
			TypedBackendSourceWalk.functionDeclaration(foreign.getDeclaration(), expression -> {
				final field = foreign.findField(expression);
				if (field != null && !field.getField().getIsStatic()) {
					fieldCount++;
					reject(() -> {
						storage.read(field, _ -> "receiver", "this_", value -> '"' + value + '"');
					}, "exact declaration");
				}
			}, _ -> {});
		}
		var initializerCount = 0;
		for (initializer in classes[0].getFieldInitializers())
			TypedBackendSourceWalk.expression(initializer.getExpression(), expression -> {
				final equality = initializer.findEquality(expression);
				if (equality != null) {
					initializerCount++;
					require(storage.usesIdentity(equality.leftType)
						&& storage.usesIdentity(equality.rightType), "initializer lost class operand types");
					require(initializer.findEquality(EBinop("==", equality.left, equality.right)) == null, "copied initializer equality borrowed facts");
					for (foreign in second.getBackendProjection().getClasses()[0].getFieldInitializers())
						require(foreign.findEquality(expression) == null, "foreign initializer borrowed equality facts");
				}
			});
		require(equalityCount == 1 && fieldCount == 1 && initializerCount == 1, "ownership controls were not exercised");
		final probe = classes[0].getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "probe")[0];
		var selected:Null<HxExpr> = null;
		TypedBackendSourceWalk.functionDeclaration(probe.getDeclaration(), expression -> {
			if (probe.findEquality(expression) != null)
				selected = expression;
		}, _ -> {});
		final body = probe.getBody();
		body.splice(0, body.length);
		reject(() -> {
			probe.findEquality(selected);
		}, "mutated");
		Sys.println("NATIVE_CLASS_STORAGE_OWNERSHIP:PASS");
	}

	public static function main():Void {
		providerAncestry();
		ownership();
		final root = "test/fixtures/native_class_storage";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), ".tmp/native_class_storage", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("NATIVE_CLASS_STORAGE_RUNTIME:PASS");
	}
}
