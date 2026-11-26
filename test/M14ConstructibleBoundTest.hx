import sys.io.File;

/**
	A `haxe.Constraints.Constructible<F>` bound is satisfied by a class whose public constructor
	fits F, as in upstream Haxe 4.3.7 (haxe_ocaml-g3l8y). Fixture: `test/fixtures/constructible_bound`.

	Upstream (tUnification.ml:824-838) unifies the class's constructor field type, its own or the
	nearest inherited one, with F, and requires the constructor to be public. hxhx had no rule for
	Constructible, so every such bound failed: `get<Arg, Cls:Constructible<Arg->Void>>` and a class
	parameter `M:IMap<K, String> & Constructible<() -> Void>` with `EnumValueMap` (whose constructor
	is inherited from `BalancedTree`).

	- `Main`: hxhx must type it. It is not emitted: js-native cannot yet construct a @:generic
	  type parameter (`new Cls(a)`, haxe_ocaml-ohbr2).
	- `WrongArgument`: `TakeChild.new(child:Child)` does not accept a `Parent`. Upstream reports the
	  constructor mismatch ("Parent should be Child"); hxhx reports the failed bound for get.Cls.
	- `WrongPrivate`: a non-public constructor fails the bound, as upstream reports for make.Cls.
**/
class M14ConstructibleBoundTest {
	static inline final ROOT = "test/fixtures/constructible_bound";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		requireUpstreamError("WrongArgument", "Parent should be Child");
		requireUpstreamError("WrongPrivate", "Constraint check failure for make.Cls");

		typeModule("Main");
		requireRejected("WrongArgument", "WrongArgument.hx:8:", "Constraint check failure for get.Cls");
		requireRejected("WrongPrivate", "WrongPrivate.hx:10:", "Constraint check failure for make.Cls");
		Sys.println("M14_CONSTRUCTIBLE_BOUND:PASS");
	}

	static function typeModule(name:String):Void {
		final std = stdRoot();
		final defines = new haxe.ds.StringMap<String>();
		for (define in ["eval", "interp", "sys", "haxe4"])
			defines.set(define, "1");
		final path = ROOT + "/" + name + ".hx";
		final module = new ResolvedModule(name, path, ParserStage.parse(HxConditionalCompilation.filterSource(File.getContent(path), defines), path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([ROOT, std + "/eval/_std", std], defines, index);
		loader.markResolvedAlready([module]);
		TyperStage.typeResolvedModule(module, index, loader, true);
	}

	static function requireRejected(name:String, position:String, message:String):Void {
		try {
			typeModule(name);
		} catch (error:TyperError) {
			final text = error.toString();
			require(text.indexOf(position) >= 0 && text.indexOf(message) >= 0, name + " was rejected with another error: " + text);
			return;
		}
		throw name + " was accepted; upstream rejects it";
	}

	static function requireUpstreamError(name:String, error:String):Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", ROOT, "-main", name, "--interp"]);
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code != 0 && stderr.indexOf(error) >= 0, "upstream no longer rejects " + name + " with `" + error + "`:\n" + stderr);
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, command + " exited " + code + ": " + stderr);
		return stdout;
	}

	/** CI installs the pinned compiler through Lix; developers may set HAXE_STD_PATH. */
	static function stdRoot():String {
		final configured = Sys.getEnv("HAXE_STD_PATH");
		if (configured != null && configured != "" && sys.FileSystem.isDirectory(configured))
			return haxe.io.Path.removeTrailingSlashes(configured);
		final lixManaged = haxe.io.Path.join([Sys.getEnv("HOME"), "haxe", "versions", "4.3.7", "std"]);
		if (sys.FileSystem.isDirectory(lixManaged))
			return lixManaged;
		throw "Could not locate the Haxe 4.3.7 standard library. Set HAXE_STD_PATH or install that version through Lix.";
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}
}
