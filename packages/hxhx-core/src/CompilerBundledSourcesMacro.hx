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
		// This inventory is deliberate: adding a provider changes target semantics.
		for (name in ["cpp/_std/haxe/Exception.hx"]) {
			final path = haxe.io.Path.join([root, name]);
			Context.registerModuleDependency(Context.getLocalModule(), path);
			final content = sys.io.File.getContent(path);
			files.push(macro {name: $v{name}, content: $v{content}});
		}
		return {expr: EArrayDecl(files), pos: Context.currentPos()};
	}
}
