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
PARSE_ORACLE: fields=1850 match=1687 (91.2%) ... files=138 fully_matching=78 (56.5%)
```

- `fields`: the number of function bodies and field initializers that upstream parsed.
- `match`: the bodies that print the same after both parsers.
- `fully_matching`: the files in which every body matches.

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

The normalization removes only spellings that cannot change meaning: quote style (but not
interpolated strings), number spelling, `default:` against `case _:`, `case A, B:` against
`case A | B:`, `case var t:` against `case t:`, and empty case bodies. Every other difference
counts as a mismatch, including desugaring that `hxhx` does while it parses.

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
  - function types print as `(A,B)->R`, and anonymous structures print their fields sorted by
    name;
  - an unresolved monomorph prints as `?`;
  - an abstract's methods drop the implicit `this` parameter, and its constructor returns `Void`.

The output line looks like this:

```
TYPED_ORACLE: methods=1671 match=1365 (81.7%) mismatch=48 missing=258 hxhx_error=0 module_errors=19
```

A method is missing when `hxhx` could not type its module; `report.json` lists those module
errors. `typed-oracle-baseline.json` holds the matching count for the default corpus, with the
same raise-on-improvement rule as the parse oracle.
