import HxExpr;
import haxe.ds.StringMap;

/**
	Renderer-only latency probe for the C++ numeric-cast unit-test shape.

	The slow upstream `cpp-numeric-only` probe can spend many minutes in macro
	and suite setup before C++ output is even emitted. This test builds a small
	repo-owned AST that has the same important renderer pressure point:
	many same-owner `deq(expected, actual)` calls where `deq` is only a local
	wrapper around `eq(expected, actual, p)`.

	This command does not compile generated C++. It is a fast routine guard for
	the direct-call renderer path, while the full upstream probe remains the
	slower diagnostic oracle for end-to-end strict-suite claims.
**/
class M14CppNumericCastsRenderBenchIntegrationTest {
	static inline final DEFAULT_CASES = 360;
	static inline final DEFAULT_HELPERS = 64;
	static inline final DEFAULT_REPS = 2;

	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function countOccurrences(haystack:String, needle:String):Int {
		var count = 0;
		var offset = 0;
		while (true) {
			final found = haystack.indexOf(needle, offset);
			if (found < 0)
				return count;
			count++;
			offset = found + needle.length;
		}
	}

	static function envInt(name:String, fallback:Int):Int {
		final raw = Sys.getEnv(name);
		if (raw == null || StringTools.trim(raw).length == 0)
			return fallback;
		final parsed = Std.parseInt(raw);
		return parsed == null || parsed <= 0 ? fallback : parsed;
	}

	static function lookup(owner:HxClassDecl):backend.cpp.CppClassLookup {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final ownerName = HxClassDecl.getName(owner);
		names.set(ownerName, true);
		classes.set(ownerName, owner);
		return {names: names, byName: classes};
	}

	static function eqFn():HxFunctionDecl {
		return new HxFunctionDecl("eq", Public, false, [
			new HxFunctionArg("expected", "Dynamic", NoDefault, false, false),
			new HxFunctionArg("actual", "Dynamic", NoDefault, false, false),
			new HxFunctionArg("p", "PosInfos", NoDefault, true, false)
		], "Void", [], "");
	}

	static function deqFn():HxFunctionDecl {
		return new HxFunctionDecl("deq", Public, false, [
			new HxFunctionArg("expected", "Dynamic", NoDefault, false, false),
			new HxFunctionArg("actual", "Dynamic", NoDefault, false, false),
			new HxFunctionArg("p", "PosInfos", NoDefault, true, false)
		], "Void", [
			SExpr(ECall(EIdent("eq"), [EIdent("expected"), EIdent("actual"), EIdent("p")]), HxPos.unknown())
		], "");
	}

	static function helperFn(index:Int):HxFunctionDecl {
		final typeHint = switch (index % 4) {
			case 0:
				"Int";
			case 1:
				"Float";
			case 2:
				"Null<Int>";
			case _:
				"Dynamic";
		};
		final name = "DynamicNumericCast_" + index;
		return new HxFunctionDecl(name, Public, false, [new HxFunctionArg("v", typeHint, NoDefault, false, false)], typeHint,
			[SReturn(EIdent("v"), HxPos.unknown())], "");
	}

	static function expectedExpr(index:Int):HxExpr {
		return switch (index % 4) {
			case 0:
				EInt(index);
			case 1:
				EFloat(index + 0.5);
			case 2:
				index % 8 == 2 ? ENull : EInt(index);
			case _:
				EInt(index);
		};
	}

	static function actualArgExpr(index:Int):HxExpr {
		return switch (index % 4) {
			case 0:
				EInt(index);
			case 1:
				EFloat(index + 0.5);
			case 2:
				index % 8 == 2 ? ENull : EInt(index);
			case _:
				EInt(index);
		};
	}

	static function benchFn(caseCount:Int, helperCount:Int):HxFunctionDecl {
		final body = new Array<HxStmt>();
		for (i in 0...caseCount) {
			final helperName = "DynamicNumericCast_" + (i % helperCount);
			body.push(SExpr(ECall(EIdent("deq"), [expectedExpr(i), ECall(EIdent(helperName), [actualArgExpr(i)])]), HxPos.unknown()));
		}
		return new HxFunctionDecl("bench", Public, false, [], "Void", body, "");
	}

	static function ownerClass(caseCount:Int, helperCount:Int):HxClassDecl {
		final functions = [eqFn(), deqFn()];
		for (i in 0...helperCount)
			functions.push(helperFn(i));
		functions.push(benchFn(caseCount, helperCount));
		return new HxClassDecl("CppNumericCastsRenderBenchOwner", false, functions, []);
	}

	static function renderOnce(caseCount:Int, helperCount:Int):{elapsed:Float, rendered:String} {
		final owner = ownerClass(caseCount, helperCount);
		final bench = HxClassDecl.getFunctions(owner)[helperCount + 2];
		final classLookup = lookup(owner);
		final start = Sys.time();
		final rendered = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(bench, owner, classLookup).join("\n");
		return {elapsed: Sys.time() - start, rendered: rendered};
	}

	static function main():Void {
		final caseCount = envInt("HXHX_CPP_NUMERIC_CASTS_RENDER_BENCH_CASES", DEFAULT_CASES);
		final helperCount = envInt("HXHX_CPP_NUMERIC_CASTS_RENDER_BENCH_HELPERS", DEFAULT_HELPERS);
		final reps = envInt("HXHX_CPP_NUMERIC_CASTS_RENDER_BENCH_REPS", DEFAULT_REPS);
		assertTrue(helperCount > 0, "helper count must be positive");

		var best = 1.0e9;
		var total = 0.0;
		var rendered = "";
		for (_ in 0...reps) {
			final result = renderOnce(caseCount, helperCount);
			rendered = result.rendered;
			total += result.elapsed;
			if (result.elapsed < best)
				best = result.elapsed;
		}

		final eqCalls = countOccurrences(rendered, "eq(");
		assertTrue(eqCalls == caseCount, "C++ numeric-cast bench should render each deq wrapper as an eq fast-path call");
		assertTrue(rendered.indexOf("deq(") < 0, "C++ numeric-cast bench should not leave deq wrapper calls in the rendered method");
		assertTrue(rendered.indexOf("std::to_string") < 0, "C++ numeric-cast bench should not use string-shaped Dynamic argument rendering");

		final lineCount = countOccurrences(rendered, "\n") + 1;
		Sys.println("CPP_NUMERIC_CASTS_RENDER_BENCH:PASS cases=" + caseCount + " helpers=" + helperCount + " reps=" + reps + " best_seconds=" + best
			+ " total_seconds=" + total + " lines=" + lineCount);
	}
}
