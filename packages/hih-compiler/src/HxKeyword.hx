/**
	Keyword enum for the Haxe-in-Haxe parser subset.

	Why:
	- Keeping keywords explicit (instead of reusing strings everywhere) makes the
	  lexer and parser easier to evolve safely as we expand language coverage.
**/
enum HxKeyword {
	KPackage;
	KImport;
	KUsing;
	KAs;
	KClass;
	KPublic;
	KPrivate;
	KStatic;
	KFunction;
	KReturn;
	// Control-flow keywords (Stage 3 bring-up).
	//
	// Why
	// - Stage 3 only understands a tiny expression subset. If we tokenize `if`/`switch`/`try`
	//   as identifiers, the parser can accidentally interpret them as normal calls
	//   (e.g. `return if (cond) a else b;` → `if_(cond)`), producing invalid OCaml.
	//
	// What
	// - We recognize these as keywords so the parser can safely treat them as unsupported
	//   and the emitter can fall back to bring-up escape hatches (`Obj.magic`).
	KIf;
	KElse;
	KSwitch;
	KCase;
	KDefault;
	KTry;
	KCatch;
	KThrow;
	KWhile;
	KDo;
	KFor;
	KIn;
	KBreak;
	KContinue;
	KUntyped;
	KCast;
	KVar;
	KFinal;
	KNew;
	KThis;
	KSuper;
	KTrue;
	KFalse;
	KNull;
}
