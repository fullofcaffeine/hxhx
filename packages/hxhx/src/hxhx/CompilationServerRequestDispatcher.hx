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
		final context = CompilationRequestContext.server(request.requestId);
		if (request.hasInvocationFlag("--hxhx-server-report"))
			context.enableBaselineReport();
		if (request.hasRequestFlag(CompilationServerProtocol.REQUEST_TIMEOUT_FLAG)) {
			final timeoutText = request.findFlagValue(CompilationServerProtocol.REQUEST_TIMEOUT_FLAG);
			final timeoutMs = CompilationServerProtocol.parseRequestTimeoutMs(timeoutText);
			if (timeoutMs == null) {
				context.output.stderrLine('hxhx(stage3): ${CompilationServerProtocol.REQUEST_TIMEOUT_FLAG} must be a decimal integer from 0 to ${CompilationServerProtocol.MAX_REQUEST_TIMEOUT_MS}');
				return finish(context, true);
			}
			context.configureTimeoutMs(timeoutMs);
		}
		if (!context.checkpoint("request-dispatch"))
			return finish(context, true);
		if (request.hasRequestFlag("--hxhx-server-control")) {
			final control = request.findFlagValue("--hxhx-server-control");
			if (control == "shutdown") {
				context.output.stdoutLine("hxhx_server_control.shutdown=ok");
				return finish(context, false, true);
			}
			context.output.stderrLine(control == null ? "hxhx(stage3): missing value after --hxhx-server-control" : 'hxhx(stage3): unsupported server control "$control"');
			return finish(context, true);
		}
		final displayRequest = request.findFlagValue("--display");
		#if hxhx_stage0_no_display
		if (displayRequest != null) {
			context.output.stderrLine("hxhx(stage3): display unavailable in stage0 no-display profiling lane");
			return finish(context, true);
		}
		#else
		if (displayRequest != null) {
			final displaySource = DisplayResponseSynthesizer.readDisplaySource(displayRequest, request.stdinBytes());
			context.output.stderrLine(DisplayResponseSynthesizer.synthesize(displayRequest, displaySource));
			return finish(context, false);
		}
		#end

		final code = try {
			runOne(request.compilerArgs(), context);
		} catch (error:haxe.Exception) {
			context.output.stderrLine("hxhx(stage3): server request handler failed: " + error.message);
			2;
		} catch (error:String) {
			context.output.stderrLine("hxhx(stage3): server request handler failed: " + error);
			2;
		}
		final completedWithinDeadline = context.checkpoint("request-complete");
		if (code != 0 && context.output.events().length == 0)
			context.output.stderrLine("hxhx(stage3): server request failed");
		return finish(context, code != 0 || !completedWithinDeadline);
	}

	static function finish(context:CompilationRequestContext, isError:Bool, stopServer:Bool = false):CompilationServerReply {
		final cleanupSucceeded = context.close();
		final events = context.output.events();
		return new CompilationServerReply(events, isError || !cleanupSucceeded, stopServer && cleanupSucceeded);
	}
}
