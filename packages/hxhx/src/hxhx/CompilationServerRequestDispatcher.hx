package hxhx;

/**
	Selects the one current compiler behavior for a decoded server request.

	Both stdio and socket transports call this dispatcher. It intentionally owns
	no cache or long-lived compiler state. The compile callback creates the same
	fresh Stage3 work used by a direct invocation; the display branch preserves
	the current bring-up response until full display semantics move behind the
	shared request compiler.
**/
class CompilationServerRequestDispatcher {
	public static function dispatch(request:CompilationServerRequest, runOne:Array<String>->Int):CompilationServerReply {
		final displayRequest = request.findFlagValue("--display");
		#if hxhx_stage0_no_display
		if (displayRequest != null)
			return new CompilationServerReply("hxhx(stage3): display unavailable in stage0 no-display profiling lane", true);
		#else
		if (displayRequest != null) {
			final displaySource = DisplayResponseSynthesizer.readDisplaySource(displayRequest, request.stdinBytes());
			return new CompilationServerReply(DisplayResponseSynthesizer.synthesize(displayRequest, displaySource), false);
		}
		#end

		final code = runOne(request.invocationArgs());
		if (code == 0)
			return new CompilationServerReply("OK", false);
		return new CompilationServerReply("hxhx(stage3): server request failed", true);
	}
}
