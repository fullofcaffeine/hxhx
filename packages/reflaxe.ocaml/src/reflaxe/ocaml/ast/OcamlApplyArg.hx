package reflaxe.ocaml.ast;

/**
 * Represents a single argument in an OCaml function application.
 *
 * Why:
 * - OCaml supports **labelled arguments** (`~label:expr`) and **optional labelled arguments**
 *   (`?label:expr_option`), which are a core part of writing idiomatic OCaml (and interop with
 *   many OCaml libraries).
 * - Haxe does not have a syntax-level equivalent, so the backend needs an explicit representation
 *   to print these callsites correctly.
 *
 * What:
 * - `label == null` means the argument is positional (`f expr`).
 * - `label != null` means the argument is labelled:
 *   - `isOptional == false` => `~label:expr`
 *   - `isOptional == true`  => `?label:expr` (expression must have type `t option`)
 *
 * How:
 * - `OcamlBuilder` emits these only when required (currently for extern interop metadata).
 * - `OcamlASTPrinter` prints the correct OCaml surface syntax.
 */
typedef OcamlApplyArg = {
	final label:Null<String>;
	final isOptional:Bool;
	final expr:OcamlExpr;
}
