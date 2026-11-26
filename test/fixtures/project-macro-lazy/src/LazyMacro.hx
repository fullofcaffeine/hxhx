#if macro
import haxe.macro.Expr;
import haxe.macro.Type;
#end

/**
	A macro that builds a `TLazy` type itself. Upstream Haxe 4.3.7 runs it. hxhx cannot build its
	plugin: the Stage3 emitter has no native representation for the function payload of
	`haxe.macro.Type.TLazy`, and it says so where the macro builds the constructor.
**/
class LazyMacro {
	public static macro function lazyType():haxe.macro.Expr {
		#if macro
		final lazy:Type = TLazy(() -> TDynamic(null));
		return macro $v{lazy != null};
		#else
		return null;
		#end
	}
}
