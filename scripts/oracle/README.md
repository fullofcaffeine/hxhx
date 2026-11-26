# Frontend parse and typed oracles

This tool measures how closely the `hxhx` parser matches the upstream Haxe 4.3.7 parser.
It parses the same files with both compilers and compares the parsed body of every field.
It is milestone B1 of `docs/00-project/ARCHITECTURE_REVIEW_2026_11_16.md` (bead
`haxe_ocaml-7cxgt`).

## Run it

```sh
npm run oracle:parse            # print the numbers and write .tmp/parse-oracle/
npm run test:oracle:parse       # the same, and fail if the numbers fall below the baseline
```

The output line looks like this:

```
PARSE_ORACLE: fields=1850 match=1687 (91.2%) ... files=138 fully_matching=78 (56.5%) ... hxhx_only=0 hxhx_only_lowering=258
```

- `fields`: the number of function bodies and field initializers that upstream parsed.
- `match`: the bodies that print the same after both parsers.
- `fully_matching`: the files in which every body matches.
- `hxhx_only` and `hxhx_only_lowering`: bodies that only `hxhx` has. They are for information
  only and count toward no other number or the baseline. `hxhx_only_lowering` counts the members
  that `hxhx`'s enum lowering adds to a parsed enum (`__hx_is_enum`, `__hx_enum_ctors`, and one
  member per constructor). `hxhx_only` counts all other extras.

`.tmp/parse-oracle/mismatches.txt` shows each differing body from both sides.
`report.json` has the counts, the export errors, and the files that `hxhx` could not parse.

## How it works

1. Upstream Haxe compiles the corpus for the interp target with a global build macro
   (`upstream/ParseOracleUpstream.hx`). The macro records each field body before typing.
   Upstream is used only as a black box. No upstream source is copied.
2. `ParseOracleHxhx.hx` runs `hxhx-core` under `haxe --run`. It applies the same defines with
   `HxConditionalCompilation`, parses each file with `ParserStage`, and exports each body with
   `MacroBodyExport`.
3. Both sides print bodies with `haxe.macro.Printer`, after the same normalization
   (`shared/ParseOracleNormalize.hx`).
4. Bodies are paired by key (`module.Type.field`). Overloads share a key: `haxe.ds.Vector` has two
   constructors. Each side numbers its second and later records with one key (`key#2`) in
   record order, which is declaration order on both sides. A pair matches only when its bodies
   print the same.

The normalization removes only spellings that cannot change meaning: quote style (but not
interpolated strings), number spelling, `default:` against `case _:`, `case A, B:` against
`case A | B:`, `case var t:` against `case t:`, and empty case bodies. Every other difference
counts as a mismatch, including desugaring that `hxhx` does while it parses.

Abstract constructors need one more rule. Upstream builds an abstract's constructor as the
implementation function `_new` before build macros run, and wraps the authored body in
`var this:T; ...; return cast this;` (Haxe 4.3.7 `typeloadFields.ml:265-298`). The upstream side
removes exactly that wrapper and records the authored statements under `new`; any other `_new`
shape stays `_new` and counts as missing. The wrapper loses the authored bracing, so the `hxhx`
side prints an abstract's `new` as a block. The oracle therefore does not compare the bracing of a
single-statement abstract constructor (`function new(i) this = i;`).

## Authored-only parity where the compile path is not equivalent

The oracle reads `hxhx`'s authored parse (`ParserStage.parseAuthored`). Usually the compile path
differs from it only in lowered forms that mean the same thing. These cases are different: the
authored parse matches upstream, but the compile path does not yet behave the same.

- Same-name overloads of an abstract (`haxe.ds.Vector`'s two `extern overload` constructors).
  Authored parsing keeps every overload. The compile path keeps only the first, because the
  frozen Stage3 OCaml backend rejects an abstract with two constructor bodies
  (`Stage3OcamlAbstractConstructors.hx`). So a call to a
  later overload does not type there. Tracked by `haxe_ocaml-95co6`.

## Corpus and baseline

The default corpus is the `haxe` package of the upstream standard library, excluding
`haxe.atomic`, which the interp target rejects, plus every module that it loads. Use
`--package` and `--exclude` to choose another corpus.

`parse-oracle-baseline.json` records the matching field and file counts for the default
corpus. The test fails when a change lowers either count. When a change raises a count, the
tool prints the new numbers. Raise the baseline in the same pull request.

## Typed oracle

The typed oracle compares how the two compilers type the same modules. This first version
compares method signatures after typing: each parameter's name, optional flag, and type, and the
return type, with inferred types filled in.

```sh
npm run oracle:typed            # print the numbers and write .tmp/typed-oracle/
npm run test:oracle:typed       # the same, and fail if the count falls below the baseline
```

- Upstream Haxe records each typed method signature after typing
  (`upstream/TypedOracleUpstream.hx`).
- `TypedOracleHxhx.hx` parses every module of the same corpus with the same defines. It builds
  one typer index and types each module through one shared module loader with the interp
  standard-library class paths.
- Both sides print types in one canonical form:
  - types are named by module (`haxe.Constraints.IMap`, `haxe.ds.List.ListNode`), and core types
    keep their bare names (`Int`, `Null<T>`);
  - typedefs are expanded;
  - a type nested deeper than 12 levels prints as `...`. Only structure counts toward the depth
    (type arguments, `Null`, function arguments and results, structure fields), not typedef
    expansion, so both sides cut a type at the same place;
  - function types print as `(A,B)->R`, and anonymous structures print their fields sorted by
    name;
  - an unresolved monomorph prints as `?`;
  - an abstract's methods drop the implicit `this` parameter, and its constructor returns `Void`.

The output line looks like this:

```
TYPED_ORACLE: methods=1671 match=1365 (81.7%) mismatch=48 missing=258 hxhx_error=0 module_errors=19 match_truncated=40
```

A method is missing when `hxhx` could not type its module; `report.json` lists those module
errors. `match_truncated` counts the matches whose signature contains `...`: they are part of
`match`, but nothing below the cut was compared. `typed-oracle-baseline.json` holds the matching count for the default corpus, with the
same raise-on-improvement rule as the parse oracle.
