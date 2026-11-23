# Regex literal syntax

Haxe 4.3.7 keeps a regex literal as `EConst(CRegexp(pattern, flags))` in the syntax tree. Its lexer decodes `\/`, `\r`, `\n` and `\t` in the pattern and keeps other escapes as written.

hxhx keeps the literal (`HxExpr.ERegexLiteral`) only in authored parsing (`ParserStage.parseAuthored`), which the parse oracle reads. Ordinary parsing still gives the typer and backends `new EReg(rawPattern, flags)`.

`expected.bodies.json` holds the bodies that upstream's parse recorder (`scripts/oracle/upstream/ParseOracleUpstream.hx`) printed for `Main.hx`. Run `node_modules/.bin/haxe test/m14_regex_literal_syntax_test.hxml`.
