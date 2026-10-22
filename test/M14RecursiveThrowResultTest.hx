import sys.io.File;

/** A throwing return-if branch has no Void result to contaminate recursive inference. */
class M14RecursiveThrowResultTest {
	static function main():Void {
		for (braced in [false, true]) {
			final root = ".tmp/recursive_throw_result_" + braced;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = 'class Node{public var left:Node;public function new(){left=null;}}class Main{static function read(value:Node){return if(value==null)'
				+ (braced ? '{throw "missing";}' : 'throw "missing";')
				+
				'else if(value.left==null)value;else read(value.left);}static function main():Void{var root=new Node();root.left=new Node();Sys.println(read(root)==root.left);try{read(null);}catch(error:String){Sys.println(error);}}}';
			File.saveContent(path, source);
			final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || output != "true\nmissing\n")
				throw "upstream recursive throw differs: " + output + errors;
			final parsed = ParserStage.parse(source, path);
			var voidReturns = 0;
			function inspect(statement:HxStmt):Void {
				switch statement {
					case SReturnVoid(_):
						voidReturns++;
					case SBlock(children, _):
						for (child in children)
							inspect(child);
					case SIf(_, yes, no, _):
						inspect(yes);
						if (no != null)
							inspect(no);
					case _:
				}
			}
			for (cls in HxModuleDecl.getClasses(parsed.getDecl()))
				for (fn in HxClassDecl.getFunctions(cls))
					if (HxFunctionDecl.getName(fn) == "read")
						for (statement in HxFunctionDecl.getBody(fn))
							inspect(statement);
			if (voidReturns != 0)
				throw "parser appended a return after a terminal throw";
			final resolved = new ResolvedModule("Main", path, parsed);
			final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			var observed = 0;
			for (cls in typed.getTypedClasses())
				for (fn in cls.getFunctions())
					if (fn.getDeclaration().getSignature().getName() == "read") {
						if (fn.getEnvironment().getReturnType().getSemanticKey() != "nominal:Main.Node")
							throw "throw polluted recursive result inference";
						observed++;
					}
			if (observed != 1)
				throw "recursive fixture lacks its checked function";
			JsRuntimeFixture.assertRuntime(typed, "Main", output);
			Sys.println("RECURSIVE_THROW_RESULT:PASS braced=" + braced);
		}
	}
}
