package reflaxe.ocaml.reuse;

#if macro
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.macro.Context;
import reflaxe.lifecycle.TargetReuseCatalog.TargetReuseCatalogStats;
import sys.FileSystem;
import sys.io.File;
#if eval
import eval.vm.Gc;
#end

/**
	Test-only failure injection for the exact source-reuse lifecycle.

	Failure can replace Haxe's cached macro interpreter, so a test-only sentinel
	directory supplied by the fixture owns one-shot state across that replacement.
	The production path calls this class only when an explicit test define is
	present; ordinary requests receive unchanged bytes and no filesystem access.
**/
class OcamlTargetReuseTestHooks {
	static inline final EXPECT_HIT_MARKER = "expect-hit";
	static inline final EXPECT_MISS_MARKER = "expect-miss";

	/**
		Fails when the fixture marked this request as an expected exact hit.

		The marker is external to the macro realm, so losing or replacing that
		realm cannot turn an expected hit into an unobserved cold compilation.
	**/
	public static function failIfExpectedHitReachedMiss():Void {
		if (!Context.defined("reflaxe_ocaml_target_reuse_test_require_hit"))
			return;
		final path = sentinelPath(EXPECT_HIT_MARKER);
		if (!FileSystem.exists(path))
			return;
		FileSystem.deleteFile(path);
		throw "reflaxe.ocaml: expected exact target reuse hit reached miss-only preparation";
	}

	/** Fails before replay when the fixture marked this request as an expected miss. **/
	public static function failIfExpectedMissReachedHit():Void {
		if (!Context.defined("reflaxe_ocaml_target_reuse_test_require_hit"))
			return;
		final path = sentinelPath(EXPECT_MISS_MARKER);
		if (!FileSystem.exists(path))
			return;
		FileSystem.deleteFile(path);
		throw "reflaxe.ocaml: expected exact target reuse miss reached replay";
	}

	/** Records redacted catalog state so a failed server fixture remains diagnosable. **/
	public static function recordCatalogState(event:String, requestRevision:String, stats:TargetReuseCatalogStats):Void {
		if (!Context.defined("reflaxe_ocaml_target_reuse_test_require_hit"))
			return;
		final safeEvent = event.split("\t").join(" ").split("\r").join(" ").split("\n").join(" ");
		final output = File.append(sentinelPath("catalog-events.tsv"), false);
		output.writeString([
			safeEvent,
			requestRevision,
			stats.realmIdentityRevision,
			Std.string(stats.requestSequence),
			Std.string(stats.entryCount),
			Std.string(stats.admissions),
			Std.string(stats.hits),
			Std.string(stats.payloadBytes),
			Std.string(stats.estimatedOverheadBytes),
			Std.string(stats.totalBudgetBytes),
			Std.string(stats.maximumEntryBytes),
			Std.string(stats.activeLeases)
		].join("\t") + "\n");
		output.close();
	}

	/**
		Compacts the eval heap and records live versus reserved memory.

		This is deliberately test-only: it diagnoses whether repeated compiler
		requests retain reachable objects without changing production GC policy.
	**/
	public static function recordCompactedGcState(event:String, stats:TargetReuseCatalogStats):Void {
		if (!Context.defined("reflaxe_ocaml_target_reuse_test_force_gc"))
			return;
		#if eval
		Gc.compact();
		final gc = Gc.stat();
		final safeEvent = event.split("\t").join(" ").split("\r").join(" ").split("\n").join(" ");
		final output = File.append(sentinelPath("gc-events.tsv"), false);
		output.writeString([
			safeEvent,
			Std.string(stats.requestSequence),
			Std.string(stats.entryCount),
			Std.string(stats.payloadBytes),
			Std.string(stats.estimatedOverheadBytes),
			Std.string(stats.activeLeases),
			Std.string(gc.heap_words),
			Std.string(gc.live_words),
			Std.string(gc.free_words),
			Std.string(gc.major_collections),
			Std.string(gc.compactions),
			Std.string(gc.top_heap_words),
			Std.string(gc.stack_size)
		].join("\t") + "\n");
		output.close();
		#end
	}

	/** Corrupts the first admitted payload so the next request must quarantine it. **/
	public static function admissionPayload(candidate:OcamlSourceBundleCandidate):Bytes {
		final payload = candidate.copyPayload();
		if (!Context.defined("reflaxe_ocaml_target_reuse_test_corrupt_first_admission") || !consumeOnce("corrupt-first-admission"))
			return payload;
		if (payload.length == 0)
			throw "reflaxe.ocaml: exact-reuse corruption fixture received an empty payload";
		final last = payload.length - 1;
		payload.set(last, payload.get(last) ^ 0xff);
		return payload;
	}

	/** Fails once after a complete candidate is staged but before source publication. **/
	public static function failAfterStage():Void {
		if (!Context.defined("reflaxe_ocaml_target_reuse_test_fail_once_after_stage") || !consumeOnce("fail-after-stage"))
			return;
		throw "reflaxe.ocaml: injected exact-reuse failure after candidate staging";
	}

	/** Fails once after published native work but before candidate admission. **/
	public static function failAfterPublishedWork():Void {
		if (!Context.defined("reflaxe_ocaml_target_reuse_test_fail_once_after_published_work")
			|| !consumeOnce("fail-after-published-work"))
			return;
		throw "reflaxe.ocaml: injected exact-reuse failure after published work";
	}

	static function consumeOnce(name:String):Bool {
		final path = sentinelPath(name);
		if (FileSystem.exists(path))
			return false;
		File.saveContent(path, "consumed\n");
		return true;
	}

	static function sentinelPath(name:String):String {
		final root = Sys.getEnv("REFLAXE_OCAML_REUSE_TEST_SENTINEL_DIR");
		if (root == null || root.length == 0)
			throw "reflaxe.ocaml: exact-reuse failure fixture requires REFLAXE_OCAML_REUSE_TEST_SENTINEL_DIR";
		if (!FileSystem.exists(root))
			FileSystem.createDirectory(root);
		return Path.join([root, name]);
	}
}
#end
