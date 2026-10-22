#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/** Embed authored target providers and register their exact build dependencies. */
class CompilerBundledSourcesMacro {
	public static macro function files():ExprOf<Array<CompilerBundledSources.BundledSourceFile>> {
		final anchor = Context.resolvePath("CompilerBundledSources.hx");
		final root = haxe.io.Path.normalize(haxe.io.Path.join([haxe.io.Path.directory(anchor), "../std"]));
		final files = new Array<Expr>();
		function add(name:String, path:String):Void {
			Context.registerModuleDependency(Context.getLocalModule(), path);
			final content = sys.io.File.getContent(path);
			files.push(macro {name: $v{name}, content: $v{content}});
		}
		// This inventory is deliberate: adding a provider changes target semantics.
		for (name in ["cpp/_std/haxe/Exception.hx", "cpp/_std/haxe/Int64.hx"]) {
			final path = haxe.io.Path.join([root, name]);
			add(name, path);
		}
		final ocamlRoot = haxe.io.Path.normalize(haxe.io.Path.join([root, "../../reflaxe.ocaml/std/ocaml/_std"]));
		for (name in [
			"Math.hx",
			"StringTools.hx",
			"haxe/io/FPHelper.hx",
			"haxe/Exception.hx",
			"haxe/ValueException.hx",
			"haxe/CallStack.hx",
			"haxe/NativeStackTrace.hx"
		])
			add("ocaml/_std/" + name, haxe.io.Path.join([ocamlRoot, name]));
		return {expr: EArrayDecl(files), pos: Context.currentPos()};
	}
}
