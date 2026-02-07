package haxe.macro;

import haxe.macro.Type;
import haxe.macro.Expr.ComplexType;

/**
	Macro-host override for `haxe.macro.TypeTools`.

	Why
	- When compiling **normal** (non-macro) targets, upstream Haxe intentionally provides only a
	  restricted surface of `haxe.macro.*` helpers. Many `TypeTools` helpers (e.g. `follow`) are
	  missing unless you are in macro evaluation (`#if (eval || neko || display)`).
	- For Stage4 bring-up, we execute macro-like initialization code at **runtime** inside
	  `hxhx-macro-host`, and some libraries (notably Reflaxe) reference a small subset of
	  `TypeTools` helpers from non-macro code guarded by custom defines (e.g. `reflaxe_runtime`).

	What
	- Provide a minimal, compilation-safe subset of `TypeTools` that:
	  - keeps compile-time macros working by delegating to `Context.*` in macro-eval contexts,
	  - keeps runtime macro-host code building by providing stub implementations.

	How
	- In macro contexts (`#if macro`), call the compiler’s macro API through `haxe.macro.Context`.
	- In runtime contexts, return conservative results (often identity), and prefer explicit
	  failures only when a call site becomes correctness-critical for a gate.

	Gotchas
	- This is deliberately not feature-complete. Add methods only when a bead/gate demands them,
	  and document any behavioral assumptions in the calling code.
**/
class TypeTools {
	/**
		Follow monomorphs/typedefs/abstracts to a more concrete type.

		Bring-up behavior
		- In macro-eval contexts, delegates to `Context.follow` (compiler-defined semantics).
		- In runtime macro-host contexts, returns the input unchanged.
	**/
	public static inline function follow(t:Type, ?once:Bool = false):Type {
		#if macro
		return Context.follow(t, once);
		#else
		// Runtime stub: we do not yet have a real `Type` model in the host.
		if (once != false) {}
		return t;
		#end
	}

	/**
		Like `follow`, but also follows abstracts to their underlying implementation.

		Bring-up behavior
		- Macro-eval: delegates to `Context.followWithAbstracts`.
		- Runtime: identity.
	**/
	public static inline function followWithAbstracts(t:Type, once:Bool = false):Type {
		#if macro
		return Context.followWithAbstracts(t, once);
		#else
		if (once != false) {}
		return t;
		#end
	}

	/**
		Returns true if `t1` and `t2` unify, false otherwise.

		Bring-up behavior
		- Macro-eval: delegates to `Context.unify`.
		- Runtime: conservatively returns false (until we have a real type model).
	**/
	public static inline function unify(t1:Type, t2:Type):Bool {
		#if macro
		return Context.unify(t1, t2);
		#else
		if (t1 != null) {}
		if (t2 != null) {}
		return false;
		#end
	}

	/**
		Convert `Type` to `ComplexType`.

		Bring-up behavior
		- Macro-eval: delegates to `Context.toComplexType`.
		- Runtime: returns null (not implemented yet).
	**/
	public static inline function toComplexType(type:Null<Type>):Null<ComplexType> {
		#if macro
		return Context.toComplexType(type);
		#else
		if (type != null) {}
		return null;
		#end
	}

	/**
		Calls function `f` on each component of type `t`.

		Bring-up behavior
		- Macro-eval: best-effort traversal (mirrors the upstream helper).
		- Runtime: no-op (until we have a real `Type` model).
	**/
	public static function iter(t:Type, f:Type->Void):Void {
		#if macro
		switch (t) {
			case TMono(tm):
				final inner = tm.get();
				if (inner != null) f(inner);
			case TEnum(_, tl) | TInst(_, tl) | TType(_, tl) | TAbstract(_, tl):
				for (tt in tl) f(tt);
			case TDynamic(t2):
				if (t != t2) f(t2);
			case TLazy(ft):
				f(ft());
			case TAnonymous(an):
				for (field in an.get().fields) f(field.type);
			case TFun(args, ret):
				for (arg in args) f(arg.t);
				f(ret);
		}
		#else
		if (t != null) {}
		if (f == null) {}
		#end
	}

	/**
		Apply type parameters to a type.

		Bring-up behavior
		- Macro-eval: best-effort identity (callers that need real behavior should use macro-eval-only paths).
		- Runtime: identity.
	**/
	public static inline function applyTypeParameters(t:Type, typeParameters:Array<TypeParameter>, concreteTypes:Array<Type>):Type {
		// Keep signature compatible with upstream `TypeTools.applyTypeParameters`.
		if (typeParameters != null && concreteTypes != null && typeParameters.length != concreteTypes.length) {
			throw "typeParameters and concreteTypes must have the same length";
		}
		#if macro
		return t;
		#else
		return t;
		#end
	}
}
