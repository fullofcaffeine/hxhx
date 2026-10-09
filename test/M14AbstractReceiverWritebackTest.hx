import backend.BackendContext;
import backend.vm.NekoTargetCore;
import sys.io.File;
import sys.FileSystem;

/** Inline abstract method calls must preserve the caller's storage and the helper's result separately. */
class M14AbstractReceiverWritebackTest {
	static function main():Void {
		final source = 'abstract Counter(Int) from Int to Int {
public inline function bump():Int {this=this+1;return this;}
public inline function add(amount:Int):Int {this=this+amount;return this;}
public inline function ifadd(amount:Int):Int {if(amount>0)this=this+amount;return this;}
public inline function twice(amount:Int):Int {this=this+amount;this=this+amount;return this;}
public inline function conditional(amount:Int):Int {if(amount<0)return this;this=this+amount;return this;}
public inline function fail(amount:Int):Int {this=this+amount;throw "stop";}
@:op(A++) public inline function post():Int {var old=this;bump();return old;}
}
class Holder {public var value:Counter;public function new(){value=10;}}
class Main {
static var events="";
static var holder=new Holder();
static function receiver():Holder {events=events+"receiver;";return holder;}
static function argument():Int {events=events+"argument;";return 3;}
static function main():Void {
var direct:Counter=4;var updated=direct.bump();Sys.println(updated);Sys.println((direct:Int));
var nested:Counter=8;var old=nested++;Sys.println(old);Sys.println((nested:Int));
var alias:Counter=2;var result=alias.twice((alias:Int));Sys.println(result);Sys.println((alias:Int));
result=alias.conditional(-1);Sys.println(result);Sys.println((alias:Int));
result=alias.conditional(1);Sys.println(result);Sys.println((alias:Int));
try {alias.fail(2);} catch(error:Dynamic) {Sys.println(error);}Sys.println((alias:Int));
result=alias.ifadd(2);Sys.println(result);result=alias.ifadd(-1);Sys.println(result);
result=receiver().value.add(argument());Sys.println(events);Sys.println(result);Sys.println((holder.value:Int));
}}';
		final expected = "5\n5\n8\n9\n6\n6\n6\n6\n7\n7\nstop\n9\n11\n11\nargument;receiver;receiver;receiver;\n13\n13\n";
		final root = ".tmp/abstract_receiver_writeback_" + Date.now().getTime();
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		@:privateAccess M14JsRuntimeTypeOperandsTest.run("haxe", ["-cp", root, "-main", "Main", "-neko", root + "/upstream.n"]);
		if (@:privateAccess M14JsRuntimeTypeOperandsTest.run("neko", [root + "/upstream.n"]) != expected)
			throw "upstream abstract receiver result or writeback differs";
		Sys.println("ABSTRACT_RECEIVER_UPSTREAM:PASS");
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final defines = HxDefineMap.fromRawDefines(["neko=1"]);
		final index = TyperIndex.buildHeaders([resolved]);
		final loader = new ModuleLoader([root], defines, index);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final lowered = TypedAbstractOperatorLowering.lowerModules([typed], index);
		final program = new MacroExpandedProgram(lowered, false);
		final context = new BackendContext(root, root + "/main.n", "Main", true, false, defines);
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, root + "/main.neko");
		File.saveContent(split.entryPath, split.entrySource);
		for (part in split.support)
			File.saveContent(part.path, part.source);
		File.saveContent(root + "/single.neko", @:privateAccess NekoTargetCore.renderProgram(program, context));
		for (file in FileSystem.readDirectory(root))
			if (StringTools.endsWith(file, ".neko"))
				@:privateAccess M14JsRuntimeTypeOperandsTest.run("nekoc", [root + "/" + file]);
		for (layout in ["main", "single"]) {
			final actual = @:privateAccess M14JsRuntimeTypeOperandsTest.run("neko", [root + "/" + layout + ".n"]);
			if (actual != expected)
				throw "abstract receiver writeback differs in " + layout + ": " + actual;
			Sys.println("ABSTRACT_RECEIVER_NATIVE:PASS layout=" + layout);
		}
		@:privateAccess M14JsRuntimeTypeOperandsTest.assertUpstreamJs(source, expected);
		JsRuntimeFixture.assertRuntime(lowered[0], "Main", expected);
		Sys.println("ABSTRACT_RECEIVER_NATIVE:PASS target=js");
	}
}
