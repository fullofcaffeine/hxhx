class M14CppTimingBufferIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function restoreEnv(name:String, value:Null<String>):Void {
		Sys.putEnv(name, value);
	}

	static function main():Void {
		final timingEnv = "HXHX_TRACE_STAGE3_CPP_TIMINGS";
		final priorTiming = Sys.getEnv(timingEnv);
		try {
			Sys.putEnv(timingEnv, "1");
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
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
			@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
			throw error;
		}
		restoreEnv(timingEnv, priorTiming);
		@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
		Sys.println("M14_CPP_TIMING_BUFFER:PASS");
	}
}
