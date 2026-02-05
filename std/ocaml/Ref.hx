package ocaml;

/**
 * OCaml-native ref surface.
 *
 * Why
 * - OCaml’s `ref` type is a small, explicit mutability primitive: `'a ref`.
 * - Haxe is imperative/mutable by default, but in OCaml we want mutable intent to be explicit
 *   and idiomatic (prefer `let` when possible, use `ref` only when needed).
 * - This type exists for **OCaml-native mode**: it is intentionally non-portable, and gives
 *   advanced users a direct way to express “this is an OCaml ref” in typed Haxe code.
 *
 * What
 * - `Ref<T>` represents OCaml `'t ref`.
 * - This class exposes a minimal API that the compiler backend special-cases:
 *   - `Ref.make(v)` lowers to `ref v`
 *   - `Ref.get(r)` lowers to `!r`
 *   - `Ref.set(r, v)` lowers to `r := v`
 *
 * How
 * - `Ref` is declared as `extern` because it has no portable Haxe implementation.
 * - The OCaml backend maps `ocaml.Ref<T>` to OCaml `T ref` at the type level and rewrites the
 *   API calls above to their target-native forms in the builder.
 *
 * Notes
 * - This is separate from the *portable* mutability lowering:
 *   - the backend already uses `ref` internally when it needs to preserve Haxe semantics
 *     (e.g. mutated captured locals).
 *   - `ocaml.Ref<T>` is an opt-in, user-facing “native surface” for writing OCaml-idiomatic code.
 */
extern class Ref<T> {
	/**
		Create a new OCaml ref containing `value`.
	**/
	public static function make<T>(value:T):Ref<T>;

	/**
		Read the current value of `r`.
	**/
	public static function get<T>(r:Ref<T>):T;

	/**
		Replace the current value of `r` with `value`.
	**/
	public static function set<T>(r:Ref<T>, value:T):Void;
}
