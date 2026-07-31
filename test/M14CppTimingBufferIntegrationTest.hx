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

	static function timingScope(?traceContext:backend.cpp.CppTraceContext):backend.cpp.CppRenderScope {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final owner = new HxClassDecl("TestEReg", false, [], []);
		names.set("TestEReg", true);
		classes.set("TestEReg", owner);
		final lookup:backend.cpp.CppClassLookup = {names: names, byName: classes, all: [owner]};
		if (traceContext != null)
			lookup.traceContext = traceContext;
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, lookup, "void");
		scope.traceOwnerName = "TestEReg";
		scope.traceMethodName = "test";
		scope.traceStmtIndex = 1;
		return scope;
	}

	static function restoreEnv(name:String, value:Null<String>):Void {
		Sys.putEnv(name, value);
	}

	static function tracePrepTiming(scope:backend.cpp.CppRenderScope, owner:String, method:String, phase:String, seconds:Float):Void {
		@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase(scope.traceContext,
			"render_helper_method_prepare_timing owner="
			+ owner
			+ " name="
			+ method
			+ " phase="
			+ phase
			+ " seconds="
			+ Std.string(seconds));
	}

	static function tracePrepCounts(owner:String, method:String, phase:String, scope:backend.cpp.CppRenderScope):Void {
		@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase(scope.traceContext,
			"render_helper_method_prepare_counts owner="
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
		final deepEnv = "HXHX_TRACE_STAGE3_CPP_DEEP";
		final lambdaEnv = "HXHX_TRACE_STAGE3_CPP_LAMBDA_PHASES";
		final callDetailEnv = "HXHX_TRACE_STAGE3_CPP_CALL_ARG_DETAIL_PHASES";
		final classificationEnv = "HXHX_TRACE_STAGE3_CPP_HELPER_CLASSIFICATION_DETAILS";
		final priorTiming = Sys.getEnv(timingEnv);
		final priorFilter = Sys.getEnv(filterEnv);
		final priorDeep = Sys.getEnv(deepEnv);
		final priorLambda = Sys.getEnv(lambdaEnv);
		final priorCallDetail = Sys.getEnv(callDetailEnv);
		final priorClassification = Sys.getEnv(classificationEnv);
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
			Sys.putEnv(deepEnv, null);
			Sys.putEnv(lambdaEnv, null);
			Sys.putEnv(callDetailEnv, null);
			Sys.putEnv(classificationEnv, null);
			final scope = timingScope();
			assertTrue(scope.traceContext.timingsEnabled
				&& scope.traceContext.timingMethodFilter == "TestEReg.test"
				&& !scope.traceContext.deepEnabled
				&& !scope.traceContext.lambdaPhasesEnabled
				&& !scope.traceContext.callArgDetailPhasesEnabled
				&& !scope.traceContext.helperClassificationDetailsEnabled,
				"one C++ program lookup should snapshot its trace environment");
			Sys.putEnv(timingEnv, null);
			Sys.putEnv(filterEnv, "Other.run");
			Sys.putEnv(deepEnv, "1");
			Sys.putEnv(lambdaEnv, "1");
			Sys.putEnv(callDetailEnv, "1");
			Sys.putEnv(classificationEnv, "1");
			final isolatedScope = timingScope();
			assertTrue(!isolatedScope.traceContext.timingsEnabled
				&& isolatedScope.traceContext.timingMethodFilter == "Other.run"
				&& isolatedScope.traceContext.deepEnabled
				&& isolatedScope.traceContext.lambdaPhasesEnabled
				&& isolatedScope.traceContext.callArgDetailPhasesEnabled
				&& isolatedScope.traceContext.helperClassificationDetailsEnabled,
				"a separate C++ program lookup should observe its own trace environment");
			assertTrue(scope.traceContext != isolatedScope.traceContext, "C++ program lookups should not share trace configuration or nested buffers");
			Sys.putEnv(timingEnv, "1");
			Sys.putEnv(filterEnv, "TestEReg.test");
			Sys.putEnv(deepEnv, null);
			Sys.putEnv(lambdaEnv, null);
			Sys.putEnv(callDetailEnv, null);
			Sys.putEnv(classificationEnv, null);
			final untracedScope = timingScope(new backend.cpp.CppTraceContext(false, ""));
			var result = "";
			final measured = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
				@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase(scope.traceContext, "buffer_fixture phase=first");
				@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase(scope.traceContext, "buffer_fixture phase=second");
				result = "rendered";
			});
			assertTrue(result == "rendered", "timed render should preserve callback side effects");
			assertTrue(measured.elapsed >= 0.0, "timed render should capture elapsed time before returning buffered diagnostics");
			assertTrue(measured.phases.length == 2, "timed render should retain both nested timing lines");
			assertTrue(measured.phases[0] == "cpp_target_phase=buffer_fixture phase=first", "first timing line should remain verbatim");
			assertTrue(measured.phases[1] == "cpp_target_phase=buffer_fixture phase=second", "timing lines should retain their original order");
			assertTrue(scope.traceContext.timingPhaseBuffer == null, "timing buffer should be detached before diagnostics are available to flush");
			var innerPhases = new Array<String>();
			final outerMeasured = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
				@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase(scope.traceContext, "nested_fixture phase=outer_before");
				final innerMeasured = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
					@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase(scope.traceContext, "nested_fixture phase=inner");
				});
				innerPhases = innerMeasured.phases;
				@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase(scope.traceContext, "nested_fixture phase=outer_after");
			});
			assertTrue(innerPhases.length == 1 && innerPhases[0] == "cpp_target_phase=nested_fixture phase=inner",
				"a nested measurement should own only its inner diagnostics");
			assertTrue(outerMeasured.phases.length == 2
				&& outerMeasured.phases[0] == "cpp_target_phase=nested_fixture phase=outer_before"
				&& outerMeasured.phases[1] == "cpp_target_phase=nested_fixture phase=outer_after",
				"a nested measurement should restore the enclosing buffer without merging or reordering its diagnostics");
			assertTrue(scope.traceContext.timingPhaseBuffer == null, "nested measurements should restore the original timing sink");
			var caughtExpectedError = false;
			try {
				@:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> throw "timing fixture error");
			} catch (error:String) {
				caughtExpectedError = error == "timing fixture error";
			}
			assertTrue(caughtExpectedError, "timed render should rethrow its original error");
			assertTrue(scope.traceContext.timingPhaseBuffer == null, "exceptional timed render should restore the timing sink");
			var caughtExpectedException = false;
			try {
				@:privateAccess
				backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> throw new haxe.Exception("timing fixture exception"));
			} catch (error:haxe.Exception) {
				caughtExpectedException = error.message == "timing fixture exception";
			}
			assertTrue(caughtExpectedException, "timed render should rethrow its original haxe.Exception");
			assertTrue(scope.traceContext.timingPhaseBuffer == null, "exceptional timed render should restore the timing sink for haxe.Exception values");

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
			final prebuiltRecords = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
				for (_ in 0...calls)
					@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase(scope.traceContext, "bookkeeping_fixture phase=prebuilt");
			});
			assertTrue(prebuiltRecords.phases.length == calls, "prebuilt timing attribution should record one line per call");
			prebuiltRecordSeconds = prebuiltRecords.elapsed;
			final scopeRecords = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
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
			final prepTimingRecords = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
				for (_ in 0...calls)
					tracePrepTiming(scope, "TestEReg", "test", "infer_callable_args", 0.000001);
			});
			prepTimingRecordSeconds = prepTimingRecords.elapsed;
			final prepNegativeCountRecords = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
				for (_ in 0...calls)
					tracePrepCounts("TestEReg", "test", "infer_callable_args", scope);
			});
			prepNegativeCountRecordSeconds = prepNegativeCountRecords.elapsed;
			final positiveScope = timingScope(scope.traceContext);
			positiveScope.argTypeOverrides.set("callback", "std::function<int(int)>");
			positiveScope.localTypeOverrides.set("callback", "std::function<int(int)>");
			final prepPositiveCountRecords = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
				for (_ in 0...calls)
					tracePrepCounts("PositiveOwner", "run", "infer_callable_args", positiveScope);
			});
			prepPositiveCountRecordSeconds = prepPositiveCountRecords.elapsed;
			final prepTracedNegative = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
				for (_ in 0...calls) {
					final phaseStart = Sys.time();
					intSink += @:privateAccess backend.cpp.CppTargetCore.functionMayNeedCallableArgTypeOverrides(prepFn) ? 1 : 0;
					tracePrepTiming(scope, "TestEReg", "test", "infer_callable_args", Sys.time() - phaseStart);
					tracePrepCounts("TestEReg", "test", "infer_callable_args", scope);
				}
			});
			prepTracedNegativeSeconds = prepTracedNegative.elapsed;
			final prepTracedPositive = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
				for (_ in 0...calls) {
					final phaseStart = Sys.time();
					intSink += @:privateAccess backend.cpp.CppTargetCore.functionMayNeedCallableArgTypeOverrides(prepFn) ? 1 : 0;
					tracePrepTiming(positiveScope, "PositiveOwner", "run", "infer_callable_args", Sys.time() - phaseStart);
					tracePrepCounts("PositiveOwner", "run", "infer_callable_args", positiveScope);
				}
			});
			prepTracedPositiveSeconds = prepTracedPositive.elapsed;
			prepTracedLineCount = prepTracedNegative.phases.length + prepTracedPositive.phases.length;
			assertTrue(prepTracedNegative.phases.length == calls * 2 && prepTracedPositive.phases.length == calls * 2,
				"each traced preparation phase should retain one timing and one count record");

			prepFullUntracedSeconds = elapsed(calls, () -> {
				untracedScope.functionAnalysisMemo.functionPreparations.clear();
				@:privateAccess backend.cpp.CppTargetCore.prepareFunctionScope(untracedScope, prepFn);
			});
			final prepFullTraced = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
				for (_ in 0...calls) {
					scope.functionAnalysisMemo.functionPreparations.clear();
					@:privateAccess backend.cpp.CppTargetCore.prepareFunctionScope(scope, prepFn);
				}
			});
			prepFullTracedSeconds = prepFullTraced.elapsed;
			prepFullTracedLineCount = prepFullTraced.phases.length;
			assertTrue(prepFullTracedLineCount == calls * 31,
				"each traced cache-miss preparation should retain fifteen timing/count pairs plus the total record");

			final args = [EString("value")];
			stringSink = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("f", args, untracedScope);
			argRenderSeconds = elapsed(calls,
				() -> stringSink = @:privateAccess backend.cpp.CppTargetCore.renderFunctionTypeCallArgs("", args, untracedScope).join(", "));
			untracedCallSeconds = elapsed(calls, () -> stringSink = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("f", args, untracedScope));
			final untracedOutput = stringSink;
			final tracedCalls = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(scope.traceContext, () -> {
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

			var untracedResult = 0;
			final untraced = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(untracedScope.traceContext, () -> {
				@:privateAccess backend.cpp.CppTargetCore.traceCppTimingPhase(untracedScope.traceContext, "buffer_fixture phase=disabled");
				untracedResult = 7;
			});
			assertTrue(untracedResult == 7, "buffer wrapper should preserve untraced callback behavior");
			assertTrue(untraced.phases.length == 0, "disabled timing should not enqueue diagnostics");
		} catch (error:Dynamic) {
			restoreEnv(timingEnv, priorTiming);
			restoreEnv(filterEnv, priorFilter);
			restoreEnv(deepEnv, priorDeep);
			restoreEnv(lambdaEnv, priorLambda);
			restoreEnv(callDetailEnv, priorCallDetail);
			restoreEnv(classificationEnv, priorClassification);
			throw error;
		}
		restoreEnv(timingEnv, priorTiming);
		restoreEnv(filterEnv, priorFilter);
		restoreEnv(deepEnv, priorDeep);
		restoreEnv(lambdaEnv, priorLambda);
		restoreEnv(callDetailEnv, priorCallDetail);
		restoreEnv(classificationEnv, priorClassification);
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
