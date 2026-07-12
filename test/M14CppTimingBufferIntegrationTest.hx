import HxExpr;
import haxe.ds.StringMap;

/**
	Freezes buffered Cpp timing output and attributes its residual bookkeeping.

	The render timers are opt-in diagnostics, but nested records can still make
	an enclosing phase look slower than its leaf renderer. The focused samples
	separate timer reads, label assembly, buffer insertion, argument rendering,
	and the complete traced/untraced direct-call paths without imposing a timing
	threshold on noisy developer machines.
**/
class M14CppTimingBufferIntegrationTest {
	static inline final DEFAULT_CALLS = 1000;
	static var floatSink = 0.0;
	static var intSink = 0;
	static var stringSink = "";

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function envInt(name:String, fallback:Int):Int {
		final raw = Sys.getEnv(name);
		if (raw == null || StringTools.trim(raw).length == 0)
			return fallback;
		final parsed = Std.parseInt(raw);
		return parsed == null || parsed <= 0 ? fallback : parsed;
	}

	static function elapsed(calls:Int, action:Void->Void):Float {
		final start = Sys.time();
		for (_ in 0...calls)
			action();
		return Sys.time() - start;
	}

	static function timingScope():backend.cpp.CppRenderScope {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final owner = new HxClassDecl("TestEReg", false, [], []);
		names.set("TestEReg", true);
		classes.set("TestEReg", owner);
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: [owner]}, "void");
		scope.traceOwnerName = "TestEReg";
		scope.traceMethodName = "test";
		scope.traceStmtIndex = 1;
		return scope;
	}

	static function restoreEnv(name:String, value:Null<String>):Void {
		Sys.putEnv(name, value);
	}

	static function tracePrepTiming(owner:String, method:String, phase:String, seconds:Float):Void {
		@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase("render_helper_method_prepare_timing owner=" + owner + " name=" + method + " phase="
			+ phase + " seconds=" + Std.string(seconds));
	}

	static function tracePrepCounts(owner:String, method:String, phase:String, scope:backend.cpp.CppRenderScope):Void {
		@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase("render_helper_method_prepare_counts owner="
			+ owner
			+ " name="
			+ method
			+ " phase="
			+ phase
			+ " arg_overrides="
			+ Std.string(@:privateAccess backend.cpp.CppTargetCore.countStringMap(scope.argTypeOverrides))
			+ " local_overrides="
			+ Std.string(@:privateAccess backend.cpp.CppTargetCore.countStringMap(scope.localTypeOverrides))
			+ " local_types="
			+ Std.string(@:privateAccess backend.cpp.CppTargetCore.countStringMap(scope.localTypes))
			+ " arg_override_values="
			+ @:privateAccess backend.cpp.CppTargetCore.summarizeStringValueMap(scope.argTypeOverrides)
			+ " local_override_values="
			+ @:privateAccess backend.cpp.CppTargetCore.summarizeStringValueMap(scope.localTypeOverrides));
	}

	static function main():Void {
		final timingEnv = "HXHX_TRACE_STAGE3_CPP_TIMINGS";
		final filterEnv = "HXHX_TRACE_STAGE3_CPP_METHOD_TIMING_FILTER";
		final priorTiming = Sys.getEnv(timingEnv);
		final priorFilter = Sys.getEnv(filterEnv);
		final calls = envInt("HXHX_CPP_TIMING_BOOKKEEPING_CALLS", DEFAULT_CALLS);
		var timerReadSeconds = 0.0;
		var labelSeconds = 0.0;
		var pushSeconds = 0.0;
		var prebuiltRecordSeconds = 0.0;
		var scopeRecordSeconds = 0.0;
		var argRenderSeconds = 0.0;
		var untracedCallSeconds = 0.0;
		var tracedCallSeconds = 0.0;
		var tracedLineCount = 0;
		var prepWorkSeconds = 0.0;
		var prepTimingRecordSeconds = 0.0;
		var prepNegativeCountRecordSeconds = 0.0;
		var prepPositiveCountRecordSeconds = 0.0;
		var prepTracedNegativeSeconds = 0.0;
		var prepTracedPositiveSeconds = 0.0;
		var prepTracedLineCount = 0;
		var prepFullUntracedSeconds = 0.0;
		var prepFullTracedSeconds = 0.0;
		var prepFullTracedLineCount = 0;
		try {
			Sys.putEnv(timingEnv, "1");
			Sys.putEnv(filterEnv, "TestEReg.test");
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingMethodFilterCache = null;
			var result = "";
			final measured = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase("buffer_fixture phase=first");
				@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase("buffer_fixture phase=second");
				result = "rendered";
			});
			assertTrue(result == "rendered", "timed render should preserve callback side effects");
			assertTrue(measured.elapsed >= 0.0, "timed render should capture elapsed time before returning buffered diagnostics");
			assertTrue(measured.phases.length == 2, "timed render should retain both nested timing lines");
			assertTrue(measured.phases[0] == "cpp_target_phase=buffer_fixture phase=first", "first timing line should remain verbatim");
			assertTrue(measured.phases[1] == "cpp_target_phase=buffer_fixture phase=second", "timing lines should retain their original order");
			assertTrue(@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhaseBuffer == null,
				"timing buffer should be detached before diagnostics are available to flush");
			var caughtExpectedError = false;
			try {
				@:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> throw "timing fixture error");
			} catch (error:String) {
				caughtExpectedError = error == "timing fixture error";
			}
			assertTrue(caughtExpectedError, "timed render should rethrow its original error");
			assertTrue(@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhaseBuffer == null, "exceptional timed render should restore the timing sink");

			final scope = timingScope();
			timerReadSeconds = elapsed(calls, () -> {
				final start = Sys.time();
				floatSink += Sys.time() - start;
			});
			labelSeconds = elapsed(calls, () -> {
				stringSink = "direct_call_phase=render_function_call_args call=f seconds=" + Std.string(floatSink) + " args=1 rendered=1";
				intSink += stringSink.length;
			});
			assertTrue(intSink > 0, "label attribution should retain every assembled diagnostic");
			final prebuiltLine = "cpp_target_phase=bookkeeping_fixture phase=prebuilt";
			final pushed = new Array<String>();
			pushSeconds = elapsed(calls, () -> pushed.push(prebuiltLine));
			assertTrue(pushed.length == calls, "buffer attribution should retain every prebuilt line");
			final prebuiltRecords = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				for (_ in 0...calls)
					@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase("bookkeeping_fixture phase=prebuilt");
			});
			assertTrue(prebuiltRecords.phases.length == calls, "prebuilt timing attribution should record one line per call");
			prebuiltRecordSeconds = prebuiltRecords.elapsed;
			final scopeRecords = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				for (_ in 0...calls) {
					final phaseStart = Sys.time();
					@:privateAccess backend.cpp.CppTargetCore.traceCppScopeStmtTimingPhase(scope,
						"direct_call_phase=render_function_call_args call=f seconds=" + Std.string(Sys.time() - phaseStart) + " args=1 rendered=1");
				}
			});
			assertTrue(scopeRecords.phases.length == calls, "scope timing attribution should record one complete line per call");
			scopeRecordSeconds = scopeRecords.elapsed;

			final prepFn = new HxFunctionDecl("test", Public, false, [], "Void", [], "");
			prepWorkSeconds = elapsed(calls,
				() -> intSink += @:privateAccess backend.cpp.CppTargetCore.functionMayNeedCallableArgTypeOverrides(prepFn) ? 1 : 0);
			final prepTimingRecords = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				for (_ in 0...calls)
					tracePrepTiming("TestEReg", "test", "infer_callable_args", 0.000001);
			});
			prepTimingRecordSeconds = prepTimingRecords.elapsed;
			final prepNegativeCountRecords = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				for (_ in 0...calls)
					tracePrepCounts("TestEReg", "test", "infer_callable_args", scope);
			});
			prepNegativeCountRecordSeconds = prepNegativeCountRecords.elapsed;
			final positiveScope = timingScope();
			positiveScope.argTypeOverrides.set("callback", "std::function<int(int)>");
			positiveScope.localTypeOverrides.set("callback", "std::function<int(int)>");
			final prepPositiveCountRecords = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				for (_ in 0...calls)
					tracePrepCounts("PositiveOwner", "run", "infer_callable_args", positiveScope);
			});
			prepPositiveCountRecordSeconds = prepPositiveCountRecords.elapsed;
			final prepTracedNegative = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				for (_ in 0...calls) {
					final phaseStart = Sys.time();
					intSink += @:privateAccess backend.cpp.CppTargetCore.functionMayNeedCallableArgTypeOverrides(prepFn) ? 1 : 0;
					tracePrepTiming("TestEReg", "test", "infer_callable_args", Sys.time() - phaseStart);
					tracePrepCounts("TestEReg", "test", "infer_callable_args", scope);
				}
			});
			prepTracedNegativeSeconds = prepTracedNegative.elapsed;
			final prepTracedPositive = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				for (_ in 0...calls) {
					final phaseStart = Sys.time();
					intSink += @:privateAccess backend.cpp.CppTargetCore.functionMayNeedCallableArgTypeOverrides(prepFn) ? 1 : 0;
					tracePrepTiming("PositiveOwner", "run", "infer_callable_args", Sys.time() - phaseStart);
					tracePrepCounts("PositiveOwner", "run", "infer_callable_args", positiveScope);
				}
			});
			prepTracedPositiveSeconds = prepTracedPositive.elapsed;
			prepTracedLineCount = prepTracedNegative.phases.length + prepTracedPositive.phases.length;
			assertTrue(prepTracedNegative.phases.length == calls * 2 && prepTracedPositive.phases.length == calls * 2,
				"each traced preparation phase should retain one timing and one count record");

			Sys.putEnv(timingEnv, null);
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
			prepFullUntracedSeconds = elapsed(calls, () -> {
				@:privateAccess backend.cpp.CppTargetCore.functionScopePrepCache = new StringMap();
				@:privateAccess backend.cpp.CppTargetCore.prepareFunctionScope(scope, prepFn);
			});
			Sys.putEnv(timingEnv, "1");
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
			final prepFullTraced = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				for (_ in 0...calls) {
					@:privateAccess backend.cpp.CppTargetCore.functionScopePrepCache = new StringMap();
					@:privateAccess backend.cpp.CppTargetCore.prepareFunctionScope(scope, prepFn);
				}
			});
			prepFullTracedSeconds = prepFullTraced.elapsed;
			prepFullTracedLineCount = prepFullTraced.phases.length;
			assertTrue(prepFullTracedLineCount == calls * 31,
				"each traced cache-miss preparation should retain fifteen timing/count pairs plus the total record");

			final args = [EString("value")];
			Sys.putEnv(timingEnv, null);
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
			stringSink = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("f", args, scope);
			argRenderSeconds = elapsed(calls,
				() -> stringSink = @:privateAccess backend.cpp.CppTargetCore.renderFunctionTypeCallArgs("", args, scope).join(", "));
			untracedCallSeconds = elapsed(calls, () -> stringSink = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("f", args, scope));
			final untracedOutput = stringSink;
			Sys.putEnv(timingEnv, "1");
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
			final tracedCalls = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				for (_ in 0...calls)
					stringSink = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("f", args, scope);
			});
			assertTrue(stringSink == untracedOutput, "timing diagnostics should not change rendered direct-call output");
			assertTrue(tracedCalls.phases.length == calls * 8, "each traced free call should retain its eight ordered timing records");
			assertTrue(tracedCalls.phases[0].indexOf("direct_call_phase=bytes_fast_get call=f") >= 0,
				"the first direct-call timing label should retain its order");
			assertTrue(tracedCalls.phases[tracedCalls.phases.length - 1].indexOf("direct_call_phase=explicit_types call=f") >= 0,
				"the final direct-call timing label should retain its order");
			tracedCallSeconds = tracedCalls.elapsed;
			tracedLineCount = tracedCalls.phases.length;

			Sys.putEnv(timingEnv, null);
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
			var untracedResult = 0;
			final untraced = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
				@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase("buffer_fixture phase=disabled");
				untracedResult = 7;
			});
			assertTrue(untracedResult == 7, "buffer wrapper should preserve untraced callback behavior");
			assertTrue(untraced.phases.length == 0, "disabled timing should not enqueue diagnostics");
		} catch (error:Dynamic) {
			restoreEnv(timingEnv, priorTiming);
			restoreEnv(filterEnv, priorFilter);
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingMethodFilterCache = null;
			throw error;
		}
		restoreEnv(timingEnv, priorTiming);
		restoreEnv(filterEnv, priorFilter);
		@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
		@:privateAccess backend.cpp.CppTargetCore.traceCppTimingMethodFilterCache = null;
		Sys.println("M14_CPP_TIMING_BUFFER:PASS calls=" + calls + " timer_read_seconds=" + timerReadSeconds + " label_seconds=" + labelSeconds
			+ " push_seconds=" + pushSeconds + " prebuilt_record_seconds=" + prebuiltRecordSeconds + " scope_record_seconds=" + scopeRecordSeconds
			+ " arg_render_seconds=" + argRenderSeconds + " untraced_call_seconds=" + untracedCallSeconds + " traced_call_seconds=" + tracedCallSeconds
			+ " traced_lines=" + tracedLineCount + " prep_work_seconds=" + prepWorkSeconds + " prep_timing_record_seconds=" + prepTimingRecordSeconds
			+ " prep_negative_count_record_seconds=" + prepNegativeCountRecordSeconds + " prep_positive_count_record_seconds="
			+ prepPositiveCountRecordSeconds + " prep_traced_negative_seconds=" + prepTracedNegativeSeconds + " prep_traced_positive_seconds="
			+ prepTracedPositiveSeconds + " prep_traced_lines=" + prepTracedLineCount + " prep_full_untraced_seconds=" + prepFullUntracedSeconds
			+ " prep_full_traced_seconds=" + prepFullTracedSeconds + " prep_full_traced_lines=" + prepFullTracedLineCount);
	}
}
