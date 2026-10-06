package backend.cpp;

import backend.cpp.CppManagedRuntime.CppManagedRuntimeFile;
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/** Embed authored runtime files without storing build-machine paths in generated programs. */
class CppManagedRuntimeMacro {
	public static macro function files():haxe.macro.Expr.ExprOf<Array<CppManagedRuntimeFile>> {
		final anchor = Context.resolvePath("backend/cpp/CppManagedRuntime.hx");
		final root = haxe.io.Path.normalize(haxe.io.Path.join([haxe.io.Path.directory(anchor), "../../../runtime/cpp"]));
		final expressions = new Array<Expr>();
		for (name in [
			"ManagedHeap.hpp",
			"ManagedValue.hpp",
			"ManagedEquality.hpp",
			"ManagedMap.hpp",
			"ManagedThrow.hpp",
			"ManagedStack.hpp",
			"ManagedCallable.hpp",
			"ManagedOutput.hpp",
			"ManagedString.hpp"
		]) {
			final path = haxe.io.Path.join([root, name]);
			Context.registerModuleDependency(Context.getLocalModule(), path);
			final content = sys.io.File.getContent(path);
			final sha256 = haxe.crypto.Sha256.encode(content);
			expressions.push(macro {name: $v{name}, content: $v{content}, sha256: $v{sha256}});
		}
		return {expr: EArrayDecl(expressions), pos: Context.currentPos()};
	}
}
