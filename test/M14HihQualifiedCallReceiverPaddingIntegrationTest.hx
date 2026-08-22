import haxe.ds.StringMap;
import sys.FileSystem;
import sys.io.File;

class M14HihQualifiedCallReceiverPaddingIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path)) {
				deleteRecursive(haxe.io.Path.join([path, entry]));
			}
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function findExtensionCallInExpr(expression:TypedExpr):Null<TypedExpr> {
		if (expression.getExtensionProvider() != null)
			return expression;
		for (child in expression.getExpressions()) {
			final found = findExtensionCallInExpr(child);
			if (found != null)
				return found;
		}
		return null;
	}

	static function findExtensionCallInStmt(statement:TypedStmt):Null<TypedExpr> {
		for (expression in statement.getExpressions()) {
			final found = findExtensionCallInExpr(expression);
			if (found != null)
				return found;
		}
		for (child in statement.getStatements()) {
			final found = findExtensionCallInStmt(child);
			if (found != null)
				return found;
		}
		return null;
	}

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_hih_qualified_call_receiver_padding_' + Std.string(Date.now().getTime()));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);

		final mainHx = haxe.io.Path.join([srcDir, 'Main.hx']);
		final src = [
			'using Syntax;',
			'class Syntax {',
			'  public function new() {}',
			'  public function equal(left:Dynamic, right:Dynamic):Bool {',
			'    return true;',
			'  }',
			'  public function ping():Int {',
			'    return 7;',
			'  }',
			'  public function callPing():Int {',
			'    return ping();',
			'  }',
			'  public static #if js inline #end function hasSuffix(value:String, suffix:String):Bool {',
			'    return value == suffix;',
			'  }',
			'}',
			'class Main {',
			'  public static function equal(left:Dynamic, right:Dynamic):Bool {',
			'    return Syntax.equal(left, right);',
			'  }',
			'  static function main() {',
			'    equal(1, 2);',
			'    new Syntax().callPing();',
			'    if (!"file.hx".hasSuffix("file.hx")) Sys.exit(9);',
			'  }',
			'}',
		].join("\n");
		File.saveContent(mainHx, src);

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, mainHx);
			final resolved = new ResolvedModule('Main', mainHx, parsed);
			final index = TyperIndex.build([resolved]);
			final loader = new ModuleLoader([srcDir], new StringMap<String>(), index, _ -> false);
			loader.markResolvedAlready([resolved]);
			final typed = TyperStage.typeResolvedModule(resolved, index, loader);
			final syntaxClass = HxModuleDecl.getClasses(parsed.getDecl()).filter(cls -> HxClassDecl.getName(cls) == 'Syntax')[0];
			final hasSuffix = HxClassDecl.getFunctions(syntaxClass).filter(fn -> HxFunctionDecl.getName(fn) == 'hasSuffix')[0];
			assertTrue(HxFunctionDecl.getIsStatic(hasSuffix), 'Conditional inline syntax erased the preceding static function modifier.');
			var extensionCall:Null<TypedExpr> = null;
			for (typedClass in typed.getTypedClasses()) {
				for (typedFunction in typedClass.getFunctions()) {
					for (statement in typedFunction.getBody().getStatements()) {
						final found = findExtensionCallInStmt(statement);
						if (found != null)
							extensionCall = found;
					}
				}
			}
			assertTrue(extensionCall != null, 'Typed body lost the selected extension-provider call.');
			final extensionDeclaration = extensionCall.getDeclaration();
			assertTrue(extensionDeclaration != null && extensionDeclaration.getIsStatic(), 'Extension call did not retain its exact static declaration.');
			assertTrue(extensionDeclaration.getSignature().getArgs().length == 2, 'Extension declaration should contain only its two declared parameters.');
			assertTrue(extensionCall.getExpressions().length == 2,
				'Extension call should retain one callee plus one explicit source argument; the receiver remains in the callee field.');
			final expanded = MacroStage.expandProgram([typed], []);
			EmitterStage.emitToDir(expanded, outDir, true, false);

			var foundPaddedCall = false;
			var foundUnpaddedCall = false;
			var foundDoubleReceiver = false;
			var foundExactExtensionCall = false;
			var foundPaddedExtensionCall = false;
			for (entry in FileSystem.readDirectory(outDir)) {
				if (!StringTools.endsWith(entry, '.ml'))
					continue;
				final mlPath = haxe.io.Path.join([outDir, entry]);
				final ocaml = File.getContent(mlPath);
				if (ocaml.indexOf('.equal ((Obj.magic HxRuntime.hx_null)) (left) (right)') >= 0)
					foundPaddedCall = true;
				if (ocaml.indexOf('.equal (left) (right)') >= 0)
					foundUnpaddedCall = true;
				if (ocaml.indexOf('ping (this_) (this_)') >= 0)
					foundDoubleReceiver = true;
				if (ocaml.indexOf('Syntax.hasSuffix ("file.hx") ("file.hx")') >= 0)
					foundExactExtensionCall = true;
				if (ocaml.indexOf('Syntax.hasSuffix ((Obj.magic HxRuntime.hx_null)) ("file.hx") ("file.hx")') >= 0)
					foundPaddedExtensionCall = true;
			}

			assertTrue(foundPaddedCall, 'Expected receiver-padded qualified call not found in emitted OCaml.');
			assertTrue(!foundUnpaddedCall, 'Found unpadded qualified call shape `.equal (left) (right)` in emitted OCaml.');
			assertTrue(!foundDoubleReceiver, 'Found duplicated receiver call shape `ping (this_) (this_)` in emitted OCaml.');
			assertTrue(foundExactExtensionCall, 'Expected exact two-argument extension-provider call not found in emitted OCaml.');
			assertTrue(!foundPaddedExtensionCall, 'Extension-provider call gained a phantom null receiver argument.');

			final runtimeExtensionHx = haxe.io.Path.join([srcDir, 'RuntimeExtensions.hx']);
			final runtimeMainHx = haxe.io.Path.join([srcDir, 'RuntimeMain.hx']);
			final runtimeOutDir = haxe.io.Path.join([tmpRoot, 'runtime_out']);
			final runtimeExtensionSource = [
				'class RuntimeExtensions {',
				'  public static #if js inline #end function matches(value:String, expected:String):Bool {',
				'    return value == expected;',
				'  }',
				'}',
			].join("\n");
			final runtimeMainSource = [
				'using RuntimeExtensions;',
				'class RuntimeMain {',
				'  static function main():Void {',
				'    if (!"extension-ok".matches("extension-ok")) Sys.exit(9);',
				'  }',
				'}',
			].join("\n");
			File.saveContent(runtimeExtensionHx, runtimeExtensionSource);
			File.saveContent(runtimeMainHx, runtimeMainSource);
			final runtimeExtensionResolved = new ResolvedModule('RuntimeExtensions', runtimeExtensionHx,
				ParserStage.parse(runtimeExtensionSource, runtimeExtensionHx));
			final runtimeMainResolved = new ResolvedModule('RuntimeMain', runtimeMainHx, ParserStage.parse(runtimeMainSource, runtimeMainHx));
			final runtimeResolved = [runtimeMainResolved, runtimeExtensionResolved];
			final runtimeIndex = TyperIndex.build(runtimeResolved);
			final runtimeLoader = new ModuleLoader([srcDir], new StringMap<String>(), runtimeIndex, _ -> false);
			runtimeLoader.markResolvedAlready(runtimeResolved);
			final runtimeTyped = [
				for (module in runtimeResolved)
					TyperStage.typeResolvedModule(module, runtimeIndex, runtimeLoader)
			];
			final executable = EmitterStage.emitToDir(MacroStage.expandProgram(runtimeTyped, []), runtimeOutDir, true);
			assertTrue(FileSystem.exists(executable), 'Extension-provider fixture did not produce a native executable.');
			assertTrue(Sys.command(executable) == 0, 'Native extension-provider runtime behavior differed from the source contract.');
		} catch (e:Dynamic) {
			thrown = e;
		}

		if (thrown != null) {
			Sys.println('debug_out=' + tmpRoot);
			throw thrown;
		}
		deleteRecursive(tmpRoot);
	}
}
