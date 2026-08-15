/**
	Conditional compilation filter for bootstrap parsing (`#if`, `#elseif`, `#else`, `#end`).

	Why
	- Upstream-ish Haxe code uses conditional compilation per-target and per-mode:
	  - `#if java` / `#if cs` / `#if js` branches reference target-specific externs and helpers.
	  - `#if macro` sections are only meaningful during macro typing/execution.
	  - `#if (dce == "full") && !interp` appears in upstream unit code.
	- During Stage 1/3 bring-up, we do not implement a full preprocessor, but we *must*
	  avoid treating inactive branches as active source:
	  - it can cause false `import_missing` failures,
	  - it can pull huge dependency surfaces that are irrelevant for the current target,
	  - it makes the module graph non-deterministic.

	What
	- `filterSource(source, defines)` returns a string with the same length and line breaks
	  as the input, where:
	  - inactive `#if` branches are replaced by spaces (newlines preserved),
	  - directive lines themselves are replaced by spaces (newlines preserved).
	- The output is safe to feed into our bootstrap lexers/parsers (native or pure Haxe),
	  because it contains no literal `#if` tokens.

	How
	- Scan block directives line-by-line. Before an active line is emitted, select any
	  inline conditional that starts on that line, including one whose branches span
	  multiple physical lines.
	- Evaluate a small boolean expression subset:
	  - identifiers, `!`, `&&`, `||`, parentheses
	  - `ident == "string"` and `ident != "string"` comparisons
	- Unknown identifiers are treated as false (conservative).

	Gotchas
	- This is not a full Haxe preprocessor. Inline scanning skips quoted strings and comments,
	  but it still supports only the expression subset described above.
	- It is meant to unblock Gate bring-up; grow it only when a gate/test requires it.
**/
class HxConditionalCompilation {
	private static inline function isSpace(c:Int):Bool {
		return c == 9 || c == 32; // \t or space
	}

	private static inline function isLineWs(c:Int):Bool {
		return c == 9 || c == 10 || c == 13 || c == 32; // \t \n \r space
	}

	private static function makeBlankLineLike(line:String, keepFirstSemicolon:Bool = false):String {
		if (line == null || line.length == 0)
			return line;
		final b = new StringBuf();
		var keptSemicolon = false;
		for (i in 0...line.length) {
			final c = line.charCodeAt(i);
			if (keepFirstSemicolon && !keptSemicolon && c == ";".code) {
				b.addChar(c);
				keptSemicolon = true;
			} else {
				b.addChar(c == "\n".code ? "\n".code : (c == "\r".code ? "\r".code : " ".code));
			}
		}
		return b.toString();
	}

	/**
		Filter a whole source string.

		Why
		- The parser accepts raw source strings, while Haxe conditional compilation
		  decides which declarations and expressions are active.
		- Filtering at this boundary gives the sole Haxe-authored parser exactly the
		  source surface selected by the request's definitions.
	**/
	public static function filterSource(source:String, defines:haxe.ds.StringMap<String>):String {
		return filterSourceInternal(source, defines, false).getFilteredSource();
	}

	/**
		Filter source and retain only the compile-time definition facts actually read.

		The returned observation is request-specific and intentionally separate from
		cached parsed syntax. Raw definition values are reduced to one-way revisions
		before they leave this evaluator.
	**/
	public static function filterSourceObserved(source:String, defines:haxe.ds.StringMap<String>):CompilerConditionalCompilationResult {
		return filterSourceInternal(source, defines, true);
	}

	static function filterSourceInternal(source:String, defines:haxe.ds.StringMap<String>, observeInputs:Bool):CompilerConditionalCompilationResult {
		final decisions = new Array<CompilerConditionalDecision>();
		function evaluate(expression:String):Bool {
			if (!observeInputs)
				return evalExpr(expression, defines);
			final accessByName = new haxe.ds.StringMap<CompilerConditionalDefineAccess>();
			final result = evalExpr(expression, defines, accessByName);
			final inputs = [
				for (name in accessByName.keys())
					CompilerConditionalDefineInput.fromDefines(name, accessByName.get(name), defines)
			];
			decisions.push(CompilerConditionalDecision.fromEvaluation(expression, result, inputs));
			return result;
		}

		if (source == null || source.length == 0)
			return new CompilerConditionalCompilationResult(source, new CompilerConditionalCompilationObservation(decisions));

		var lines = splitLinesPreserveNewlines(source);
		final out = new StringBuf();

		// Each stack frame represents a single `#if ...` block.
		//
		// parentActive: whether this whole block is visible due to outer blocks.
		// branchActive: whether the *current* branch (#if/#elseif/#else) is active.
		// seenTrue: whether a previous branch in this block matched.
		final stack = new Array<{parentActive:Bool, branchActive:Bool, seenTrue:Bool}>();
		var currentActive = true;

		var lineIndex = 0;
		while (lineIndex < lines.length) {
			var line = lines[lineIndex];
			final directive = parseDirectiveLine(line);
			if (directive == null) {
				if (!currentActive) {
					// Consume a multiline inline block as one inactive region. Otherwise,
					// a line-leading #else or #end inside it could be mistaken for the
					// enclosing block directive and reactivate source too early.
					if (line.indexOf("#if") >= 0) {
						var filteredRemaining = false;
						var inlineFiltered = filterInlineConditionals(line, evaluate, false);
						if (inlineFiltered == null) {
							filteredRemaining = true;
							inlineFiltered = filterInlineConditionals(lines.slice(lineIndex).join(""), evaluate, false);
						}
						if (inlineFiltered != null) {
							if (filteredRemaining)
								lines = lines.slice(0, lineIndex).concat(splitLinesPreserveNewlines(inlineFiltered));
							else
								lines[lineIndex] = inlineFiltered;
							line = lines[lineIndex];
						}
					}
					out.add(makeBlankLineLike(line));
					lineIndex++;
					continue;
				}

				// Inline conditionals can begin inside an expression and finish on a later
				// physical line. Filter the remaining source so the chosen payload keeps its
				// original offsets, then continue the ordinary block-directive pass over it.
				//
				// Only inspect the remaining source when the current line has a possible
				// opener. Same-line conditionals stay on the cheap line-local path; only
				// an opener without a local terminator scans the remaining source.
				while (line.indexOf("#if") >= 0) {
					var filteredRemaining = false;
					var inlineFiltered = filterInlineConditionals(line, evaluate);
					if (inlineFiltered == null) {
						filteredRemaining = true;
						inlineFiltered = filterInlineConditionals(lines.slice(lineIndex).join(""), evaluate);
					}
					if (inlineFiltered == null)
						break;
					if (filteredRemaining)
						lines = lines.slice(0, lineIndex).concat(splitLinesPreserveNewlines(inlineFiltered));
					else
						lines[lineIndex] = inlineFiltered;
					line = lines[lineIndex];
				}
				out.add(line);
				lineIndex++;
				continue;
			}

			// Always blank directive lines so the parser doesn't see `#`.
			// Preserve the semicolon in `#end;` expression initializers.
			out.add(makeBlankLineLike(line, directive.kind == "end" && directive.expr == ";"));

			final outerActive = stack.length == 0 ? true : stack[stack.length - 1].parentActive && stack[stack.length - 1].branchActive;

			switch (directive.kind) {
				case "if":
					final cond = outerActive && evaluate(directive.expr);
					stack.push({parentActive: outerActive, branchActive: cond, seenTrue: cond});
				case "elseif":
					if (stack.length == 0) {
						// Malformed; ignore.
					} else {
						final top = stack[stack.length - 1];
						if (!top.parentActive) {
							top.branchActive = false;
						} else if (top.seenTrue) {
							top.branchActive = false;
						} else {
							final cond = evaluate(directive.expr);
							top.branchActive = cond;
							if (cond)
								top.seenTrue = true;
						}
						stack[stack.length - 1] = top;
					}
				case "else":
					if (stack.length == 0) {
						// Malformed; ignore.
					} else {
						final top = stack[stack.length - 1];
						top.branchActive = top.parentActive && !top.seenTrue;
						top.seenTrue = true;
						stack[stack.length - 1] = top;
					}
				case "end":
					if (stack.length > 0)
						stack.pop();
				case _:
			}

			// Recompute currentActive from the full stack.
			currentActive = true;
			for (f in stack) {
				if (!f.parentActive || !f.branchActive) {
					currentActive = false;
					break;
				}
			}
			lineIndex++;
		}

		return new CompilerConditionalCompilationResult(out.toString(), new CompilerConditionalCompilationObservation(decisions));
	}

	/**
		Returns true when a dependency came from a target-specific package root that is
		inactive for the current compilation target.

		Why
		- ResolverStage and ModuleLoader use a deliberately broad qualified-name scanner to
		  approximate type-driven dependency discovery during Stage3 bring-up.
		- That scanner can still see names inside preprocessor shapes we do not fully rewrite,
		  for example `php.Global` in a JS compilation.
		- Explicit imports remain authoritative; this helper is only for heuristic qualified
		  dependency discovery.
	**/
	public static function isInactiveTargetQualifiedTypePath(typePath:String, defines:haxe.ds.StringMap<String>):Bool {
		if (typePath == null)
			return false;
		final dot = typePath.indexOf(".");
		if (dot <= 0)
			return false;
		final root = typePath.substr(0, dot);
		if (!isKnownTargetPackageRoot(root))
			return false;
		if (defines != null && defines.exists(root))
			return false;
		return hasAnyKnownTargetDefine(defines);
	}

	/**
		Returns true when a type path belongs to the currently active target-native
		package root and may legitimately be an extern platform type with no `.hx`
		module in Haxe std.

		Why
		- Haxe target std overrides import platform types such as
		  `java.lang.CharSequence` and `cs.system.Type`.
		- Some of those names are external VM/.NET types, not Haxe modules stored
		  under `std/`.
		- ResolverStage walks explicit imports before the full typer/extern model
		  exists, so it needs a narrow way to avoid treating these active target
		  extern imports as hard `import_missing` errors.
	**/
	public static function isActiveTargetNativeExternPath(typePath:String, defines:haxe.ds.StringMap<String>):Bool {
		if (typePath == null)
			return false;
		final dot = typePath.indexOf(".");
		if (dot <= 0)
			return false;
		final root = typePath.substr(0, dot);
		return isKnownTargetPackageRoot(root) && defines != null && defines.exists(root);
	}

	/**
		Whether a missing import may be satisfied by an explicitly declared native library.

		Why
		- Java/C# upstream unit workloads import types from native libraries declared with
		  flags such as `--java-lib native.jar` or `--net-lib native.dll`.
		- Those types do not have `.hx` module files, so the syntax-driven bootstrap resolver
		  must not fail before the target backend/library-introspection layer can handle them.
		- The rule is deliberately gated by internal defines emitted only when such native
		  library flags are present, so ordinary missing Haxe imports remain strict.

		What
		- For Java, dotted missing imports can be external when `java` and
		  `hxhx_java_lib` are active.
		- For C#, dotted imports and no-package native type imports can be external when
		  `cs` and `hxhx_net_lib` are active.
	**/
	public static function isActiveNativeLibraryExternPath(typePath:String, defines:haxe.ds.StringMap<String>):Bool {
		if (typePath == null)
			return false;
		final s = StringTools.trim(typePath);
		if (s.length == 0)
			return false;
		if (defines == null)
			return false;

		final dot = s.indexOf(".");
		if (dot > 0 && defines.exists("java") && defines.exists("hxhx_java_lib"))
			return true;
		if (defines.exists("cs") && defines.exists("hxhx_net_lib")) {
			if (dot > 0)
				return true;
			final first = s.charCodeAt(0);
			return first >= "A".code && first <= "Z".code;
		}
		return false;
	}

	private static function isKnownTargetPackageRoot(root:String):Bool {
		return switch (root) {
			case "php" | "java" | "cs" | "python" | "neko" | "lua" | "cpp" | "hl" | "flash" | "js": true;
			case _: false;
		}
	}

	private static function hasAnyKnownTargetDefine(defines:haxe.ds.StringMap<String>):Bool {
		if (defines == null)
			return false;
		for (root in ["php", "java", "cs", "python", "neko", "lua", "cpp", "hl", "flash", "js"])
			if (defines.exists(root))
				return true;
		return false;
	}

	/**
		Select the first inline conditional that begins on the first physical line.

		The selected payload and all source outside the conditional keep their original
		offsets. Directive text and inactive payloads become spaces, with line endings
		preserved. Nested directives are used to find the matching `#end`; a selected
		nested directive remains for a later filtering pass. When `selectBranch` is false,
		the complete conditional is blanked without evaluating its definitions; this keeps
		conditionals inside an inactive outer block inert.
	**/
	private static function filterInlineConditionals(source:String, evaluate:String->Bool, selectBranch:Bool = true):Null<String> {
		if (source == null || source.length == 0 || source.indexOf("#if") == -1 || source.indexOf("#end") == -1)
			return null;

		final tokens = findConditionalDirectiveTokens(source);
		final firstLineEnd = source.indexOf("\n") < 0 ? source.length : source.indexOf("\n");
		var openerIndex = -1;
		var openerCondStart = -1;
		var openerCondEnd = -1;
		for (i in 0...tokens.length) {
			final token = tokens[i];
			if (token.start >= firstLineEnd)
				break;
			if (token.kind != "if")
				continue;
			var condStart = token.end;
			while (condStart < source.length && isLineWs(source.charCodeAt(condStart)))
				condStart++;
			final condEnd = parseInlineCondEnd(source, condStart, source.length);
			if (condEnd <= condStart || condEnd > firstLineEnd)
				continue;
			final linePayload = stripLineCommentOutsideStrings(source.substr(condEnd, firstLineEnd - condEnd));
			final hasSameLineDirective = i + 1 < tokens.length && tokens[i + 1].start < firstLineEnd;
			if (StringTools.trim(linePayload).length == 0 && !hasSameLineDirective)
				continue;
			openerIndex = i;
			openerCondStart = condStart;
			openerCondEnd = condEnd;
			break;
		}
		if (openerIndex < 0)
			return null;

		var depth = 0;
		var endIndex = -1;
		final branchTokenIndexes = new Array<Int>();
		for (i in openerIndex...tokens.length) {
			final token = tokens[i];
			switch (token.kind) {
				case "if":
					depth++;
				case "end":
					depth--;
					if (depth == 0) {
						endIndex = i;
						break;
					}
				case "elseif" | "else":
					if (depth == 1)
						branchTokenIndexes.push(i);
				case _:
			}
			if (endIndex >= 0)
				break;
		}
		if (endIndex < 0)
			return null;

		final endToken = tokens[endIndex];
		final branches = new Array<{cond:Null<String>, start:Int, end:Int}>();
		final firstBranchEnd = branchTokenIndexes.length == 0 ? endToken.start : tokens[branchTokenIndexes[0]].start;
		branches.push({
			cond: StringTools.trim(source.substr(openerCondStart, openerCondEnd - openerCondStart)),
			start: openerCondEnd,
			end: firstBranchEnd
		});
		for (i in 0...branchTokenIndexes.length) {
			final token = tokens[branchTokenIndexes[i]];
			final branchEnd = i + 1 < branchTokenIndexes.length ? tokens[branchTokenIndexes[i + 1]].start : endToken.start;
			if (token.kind == "else") {
				branches.push({cond: null, start: token.end, end: branchEnd});
				continue;
			}
			var condStart = token.end;
			while (condStart < source.length && isLineWs(source.charCodeAt(condStart)))
				condStart++;
			final condEnd = parseInlineCondEnd(source, condStart, branchEnd);
			if (condEnd <= condStart)
				return null;
			branches.push({
				cond: StringTools.trim(source.substr(condStart, condEnd - condStart)),
				start: condEnd,
				end: branchEnd
			});
		}

		var keepStart = -1;
		var keepEnd = -1;
		if (selectBranch) {
			for (branch in branches) {
				if (branch.cond == null || evaluate(branch.cond)) {
					keepStart = branch.start;
					keepEnd = branch.end;
					break;
				}
			}
		}

		final outCodes = [for (i in 0...source.length) source.charCodeAt(i)];
		var i = tokens[openerIndex].start;
		while (i < endToken.end) {
			final c = source.charCodeAt(i);
			outCodes[i] = c == "\n".code || c == "\r".code ? c : " ".code;
			i++;
		}
		if (keepStart >= 0) {
			i = keepStart;
			while (i < keepEnd) {
				outCodes[i] = source.charCodeAt(i);
				i++;
			}
		}

		final out = new StringBuf();
		for (c in outCodes)
			out.addChar(c);
		return out.toString();
	}

	/**
		Find conditional directive keywords that can affect inline branch nesting.

		Quoted strings and line or block comments are skipped so text such as `"#end"`
		does not close a real source conditional. Each result keeps exact source offsets;
		the caller owns condition parsing and matching nested `#if`/`#end` pairs.
	**/
	private static function findConditionalDirectiveTokens(source:String):Array<{kind:String, start:Int, end:Int}> {
		final out = new Array<{kind:String, start:Int, end:Int}>();
		var i = 0;
		var quote = 0;
		var lineComment = false;
		var blockComment = false;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (lineComment) {
				if (c == "\n".code)
					lineComment = false;
				i++;
				continue;
			}
			if (blockComment) {
				if (c == "*".code && i + 1 < source.length && source.charCodeAt(i + 1) == "/".code) {
					blockComment = false;
					i += 2;
				} else {
					i++;
				}
				continue;
			}
			if (quote != 0) {
				if (c == "\\".code) {
					i += 2;
				} else {
					if (c == quote)
						quote = 0;
					i++;
				}
				continue;
			}
			if (c == "/".code && i + 1 < source.length) {
				final next = source.charCodeAt(i + 1);
				if (next == "/".code) {
					lineComment = true;
					i += 2;
					continue;
				}
				if (next == "*".code) {
					blockComment = true;
					i += 2;
					continue;
				}
			}
			if (c == "\"".code || c == "'".code) {
				quote = c;
				i++;
				continue;
			}
			if (c == "#".code) {
				var kind:Null<String> = null;
				var length = 0;
				for (candidate in ["elseif", "else", "end", "if"]) {
					if (source.substr(i + 1, candidate.length) != candidate)
						continue;
					final after = i + 1 + candidate.length;
					if (after < source.length) {
						final boundary = source.charCodeAt(after);
						if ((boundary >= "a".code && boundary <= "z".code)
							|| (boundary >= "A".code && boundary <= "Z".code)
							|| (boundary >= "0".code && boundary <= "9".code)
							|| boundary == "_".code)
							continue;
					}
					kind = candidate;
					length = candidate.length + 1;
					break;
				}
				if (kind != null) {
					out.push({kind: kind, start: i, end: i + length});
					i += length;
					continue;
				}
			}
			i++;
		}
		return out;
	}

	private static function parseInlineCondEnd(line:String, start:Int, max:Int):Int {
		// If the condition starts with `(`, scan to the matching `)`.
		// Otherwise, scan to the next whitespace.
		final first = line.charCodeAt(start);
		if (first == "(".code) {
			var depth = 0;
			var i = start;
			while (i < line.length && i < max) {
				final c = line.charCodeAt(i);
				if (c == "(".code) {
					depth++;
				} else if (c == ")".code) {
					depth--;
					if (depth == 0)
						return i + 1;
				} else if (c == "\"".code || c == "'".code) {
					// Skip over quoted strings inside the condition (best-effort).
					i = skipStringLiteral(line, i, c, max);
					continue;
				}
				i++;
			}
			return -1;
		}

		var i = start;
		while (i < line.length && i < max && !isLineWs(line.charCodeAt(i)))
			i++;
		return i;
	}

	private static function skipStringLiteral(line:String, start:Int, quote:Int, max:Int):Int {
		// start points at the opening quote
		var i = start + 1;
		while (i < line.length && i < max) {
			final c = line.charCodeAt(i);
			if (c == "\\".code) {
				i += 2;
				continue;
			}
			if (c == quote)
				return i + 1;
			i++;
		}
		return i;
	}

	private static function splitLinesPreserveNewlines(s:String):Array<String> {
		final out = new Array<String>();
		var start = 0;
		var i = 0;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c == "\n".code) {
				out.push(s.substr(start, i - start + 1));
				i += 1;
				start = i;
				continue;
			}
			i += 1;
		}
		if (start < s.length)
			out.push(s.substr(start));
		return out;
	}

	private static function stripLineCommentOutsideStrings(s:String):String {
		if (s == null || s.length == 0)
			return s;
		var i = 0;
		var inSingle = false;
		var inDouble = false;
		var escaped = false;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (escaped) {
				escaped = false;
				i += 1;
				continue;
			}
			if (c == "\\".code && (inSingle || inDouble)) {
				escaped = true;
				i += 1;
				continue;
			}
			if (!inSingle && c == "\"".code) {
				inDouble = !inDouble;
				i += 1;
				continue;
			}
			if (!inDouble && c == "'".code) {
				inSingle = !inSingle;
				i += 1;
				continue;
			}
			if (!inSingle && !inDouble && c == "/".code && i + 1 < s.length && s.charCodeAt(i + 1) == "/".code) {
				return s.substr(0, i);
			}
			i += 1;
		}
		return s;
	}

	private static function parseDirectiveLine(line:String):Null<{kind:String, expr:String}> {
		if (line == null)
			return null;
		var i = 0;
		while (i < line.length && isSpace(line.charCodeAt(i)))
			i++;
		if (i >= line.length)
			return null;
		if (line.charCodeAt(i) != "#".code)
			return null;
		i++;
		while (i < line.length && isSpace(line.charCodeAt(i)))
			i++;

		final rest = line.substr(i);
		final restNoComment = stripLineCommentOutsideStrings(rest);
		// This bootstrap preprocessor only supports directives that occupy the whole
		// physical line. Haxe also allows “inline” conditional compilation like:
		//   #if (cond) expr #else other #end(...)
		// on a *single* physical line. If we treat that as a normal `#if` directive,
		// we would push to the stack but never observe `#end`, causing the remainder
		// of the file to be blanked (catastrophic for parsing).
		//
		// Heuristic: if there is a same-line `#end`, let the inline conditional
		// filter below preserve the active payload and any suffix after `#end`.
		// Otherwise, if there's any additional `#` after the initial one, treat the
		// line as an opaque preprocessor construct. We still blank it (so parsers
		// never see `#` tokens), but we do not mutate the conditional stack.
		//
		// Strip trailing `//` comment text first so cases like:
		//   #if cs // issue #996
		// do not get misclassified as opaque.
		if (restNoComment.indexOf("#end") != -1)
			return null;
		if (restNoComment.indexOf("#") != -1)
			return {kind: "opaque", expr: ""};
		final trimmed = StringTools.trim(restNoComment);
		if (StringTools.startsWith(trimmed, "if "))
			return {kind: "if", expr: StringTools.trim(trimmed.substr(3))};
		if (StringTools.startsWith(trimmed, "elseif "))
			return {kind: "elseif", expr: StringTools.trim(trimmed.substr(7))};
		if (trimmed == "else")
			return {kind: "else", expr: ""};
		// Expression initializers can terminate a block conditional as `#end;`.
		// The semicolon belongs to the surrounding expression, so preserve it
		// after blanking the directive token itself.
		if (trimmed == "end;")
			return {kind: "end", expr: ";"};
		if (trimmed == "end")
			return {kind: "end", expr: ""};
		return null;
	}

	// --- Expression evaluator (small subset) ---

	private static function evalExpr(expr:String, defines:haxe.ds.StringMap<String>,
			?observedAccessByName:haxe.ds.StringMap<CompilerConditionalDefineAccess>):Bool {
		final p = new ExprParser(expr == null ? "" : expr, defines, observedAccessByName);
		return p.parse();
	}
}

private enum Token {
	TIdent(name:String);
	TString(value:String);
	TNot;
	TAnd;
	TOr;
	TLParen;
	TRParen;
	TEq;
	TNeq;
	TEof;
}

private class ExprLexer {
	final s:String;
	var i:Int = 0;

	public function new(s:String) {
		this.s = s == null ? "" : s;
	}

	inline function eof():Bool
		return i >= s.length;

	inline function peek(off:Int = 0):Int {
		final j = i + off;
		return j >= s.length ? -1 : s.charCodeAt(j);
	}

	inline function bump():Int
		return eof() ? -1 : s.charCodeAt(i++);

	inline function isWs(c:Int):Bool
		return c == 9 || c == 10 || c == 13 || c == 32;

	inline function isIdentStart(c:Int):Bool
		return (c >= "A".code && c <= "Z".code) || (c >= "a".code && c <= "z".code) || c == "_".code;

	inline function isIdentCont(c:Int):Bool
		return isIdentStart(c) || (c >= "0".code && c <= "9".code);

	function skipWs():Void {
		while (!eof() && isWs(peek()))
			i++;
	}

	function readIdent():String {
		final start = i;
		bump();
		while (!eof() && isIdentCont(peek()))
			bump();
		return s.substr(start, i - start);
	}

	function readString(q:Int):String {
		// opening quote already in `q`
		bump();
		final b = new StringBuf();
		while (!eof()) {
			final c = bump();
			if (c == q)
				return b.toString();
			if (c == "\\".code && !eof()) {
				final esc = bump();
				switch (esc) {
					case "n".code:
						b.addChar("\n".code);
					case "r".code:
						b.addChar("\r".code);
					case "t".code:
						b.addChar("\t".code);
					case "\\".code:
						b.addChar("\\".code);
					case "\"".code:
						b.addChar("\"".code);
					case "'".code:
						b.addChar("'".code);
					case _:
						b.addChar(esc);
				}
				continue;
			}
			b.addChar(c);
		}
		return b.toString();
	}

	public function next():Token {
		skipWs();
		if (eof())
			return TEof;
		return switch (peek()) {
			case "!".code:
				if (peek(1) == "=".code) {
					i += 2;
					TNeq;
				} else {
					i++;
					TNot;
				}
			case "&".code:
				if (peek(1) == "&".code) {
					i += 2;
					TAnd;
				} else {
					i++;
					TEof;
				}
			case "|".code:
				if (peek(1) == "|".code) {
					i += 2;
					TOr;
				} else {
					i++;
					TEof;
				}
			case "(".code:
				i++;
				TLParen;
			case ")".code:
				i++;
				TRParen;
			case "=".code:
				if (peek(1) == "=".code) {
					i += 2;
					TEq;
				} else {
					i++;
					TEof;
				}
			case "\"".code, "'".code:
				final q = peek();
				TString(readString(q));
			case c if (isIdentStart(c)):
				TIdent(readIdent());
			case _:
				i++;
				next();
		}
	}
}

private class ExprParser {
	final lex:ExprLexer;
	final defines:haxe.ds.StringMap<String>;
	final observedAccessByName:Null<haxe.ds.StringMap<CompilerConditionalDefineAccess>>;
	var cur:Token;

	public function new(expr:String, defines:haxe.ds.StringMap<String>, ?observedAccessByName:haxe.ds.StringMap<CompilerConditionalDefineAccess>) {
		this.lex = new ExprLexer(expr);
		this.defines = defines == null ? new haxe.ds.StringMap<String>() : defines;
		this.observedAccessByName = observedAccessByName;
		this.cur = lex.next();
	}

	inline function bump():Void
		cur = lex.next();

	public function parse():Bool {
		final v = parseOr();
		return v;
	}

	function parseOr():Bool {
		var left = parseAnd();
		while (true) {
			switch (cur) {
				case TOr:
					bump();
					left = left || parseAnd();
				case _:
					return left;
			}
		}
	}

	function parseAnd():Bool {
		var left = parseUnary();
		while (true) {
			switch (cur) {
				case TAnd:
					bump();
					left = left && parseUnary();
				case _:
					return left;
			}
		}
	}

	function parseUnary():Bool {
		return switch (cur) {
			case TNot:
				bump();
				!parseUnary();
			case _:
				parsePrimary();
		}
	}

	function parsePrimary():Bool {
		return switch (cur) {
			case TLParen:
				bump();
				final v = parseOr();
				if (cur.match(TRParen))
					bump();
				v;
			case TIdent(name):
				bump();
				parseIdentTail(name);
			case _:
				// Conservative default: any unrecognized expression part becomes false.
				bump();
				false;
		}
	}

	function parseIdentTail(name:String):Bool {
		// Support `defined(NAME)` as a cheap convenience.
		if (name == "defined" && cur.match(TLParen)) {
			bump();
			var key = "";
			switch (cur) {
				case TIdent(n):
					key = n;
					bump();
				case TString(s):
					key = s;
					bump();
				case _:
			}
			if (cur.match(TRParen))
				bump();
			observe(key, CompilerConditionalDefineAccess.Presence);
			return key.length > 0 && defines.exists(key);
		}

		// Optional `== "..."` / `!= "..."`.
		return switch (cur) {
			case TEq:
				bump();
				final lit = parseStringLit();
				(definedValue(name) == lit);
			case TNeq:
				bump();
				final lit = parseStringLit();
				(definedValue(name) != lit);
			case _:
				observe(name, CompilerConditionalDefineAccess.Presence);
				defines.exists(name);
		}
	}

	function parseStringLit():String {
		return switch (cur) {
			case TString(s):
				bump();
				s;
			case TIdent(s):
				// Allow bare idents as “strings” to keep the subset permissive (e.g. `dce == full`).
				bump();
				s;
			case _:
				"";
		}
	}

	function definedValue(name:String):String {
		if (name == null || name.length == 0)
			return "";
		observe(name, CompilerConditionalDefineAccess.Value);
		return defines.exists(name) ? defines.get(name) : "";
	}

	inline function observe(name:String, access:CompilerConditionalDefineAccess):Void {
		if (observedAccessByName == null || name == null || name.length == 0)
			return;
		final previous = observedAccessByName.get(name);
		if (previous == null || access == CompilerConditionalDefineAccess.Value)
			observedAccessByName.set(name, access);
	}
}
