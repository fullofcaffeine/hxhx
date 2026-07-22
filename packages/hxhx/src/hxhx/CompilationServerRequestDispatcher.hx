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
	public static function dispatch(request:CompilationServerRequest,
			runOne:(args:Array<String>, context:CompilationRequestContext) -> Int):CompilationServerReply {
		final displayRequest = request.findFlagValue("--display");
		#if hxhx_stage0_no_display
		if (displayRequest != null)
			return CompilationServerReply.message("hxhx(stage3): display unavailable in stage0 no-display profiling lane", true);
		#else
		if (displayRequest != null) {
			final displaySource = DisplayResponseSynthesizer.readDisplaySource(displayRequest, request.stdinBytes());
			return CompilationServerReply.message(DisplayResponseSynthesizer.synthesize(displayRequest, displaySource), false);
		}
		#end

		final context = CompilationRequestContext.server(request.requestId);
		final code = try {
			runOne(request.invocationArgs(), context);
		} catch (error:haxe.Exception) {
			context.output.stderrLine("hxhx(stage3): server request handler failed: " + error.message);
			2;
		} catch (error:String) {
			context.output.stderrLine("hxhx(stage3): server request handler failed: " + error);
			2;
		}
		if (code != 0 && context.output.events().length == 0)
			context.output.stderrLine("hxhx(stage3): server request failed");
		final events = context.output.events();
		context.close();
		return new CompilationServerReply(events, code != 0);
	}
}
