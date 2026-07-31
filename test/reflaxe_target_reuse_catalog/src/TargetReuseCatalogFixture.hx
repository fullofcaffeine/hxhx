import haxe.io.Bytes;
import reflaxe.lifecycle.TargetReuseCatalog;

/** Focused mechanics checks for the bounded generic target-reuse catalog. **/
class TargetReuseCatalogFixture {
	static final NAMESPACE = "fixture.target/v1";

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function revision(seed:String):String {
		return haxe.crypto.Sha256.encode(seed);
	}

	static function payload(value:String, length:Int):Bytes {
		final bytes = Bytes.alloc(length);
		for (index in 0...length)
			bytes.set(index, value.charCodeAt(index % value.length));
		return bytes;
	}

	static function testAdmissionLeaseAndEviction():Void {
		final catalog = new TargetReuseCatalog(100, 60);
		final a = revision("a");
		final b = revision("b");
		final c = revision("c");
		final d = revision("d");
		assertTrue(catalog.admit(NAMESPACE, a, payload("a", 40), 5).admitted, "entry A should be admitted");
		assertTrue(catalog.admit(NAMESPACE, b, payload("b", 40), 5).admitted, "entry B should be admitted");

		final leaseA = catalog.lookup(NAMESPACE, a);
		assertTrue(leaseA != null, "entry A should be leased");
		final copied = leaseA.copyPayload();
		copied.set(0, "z".code);
		assertTrue(leaseA.copyPayload().get(0) == "a".code, "callers must not mutate catalog-owned bytes");
		leaseA.close();
		leaseA.close();

		assertTrue(catalog.admit(NAMESPACE, c, payload("c", 40), 5).admitted, "entry C should evict the least-recently-used entry");
		assertTrue(catalog.lookup(NAMESPACE, b) == null, "least-recently-used entry B should be absent");
		final nextA = catalog.lookup(NAMESPACE, a);
		final leaseC = catalog.lookup(NAMESPACE, c);
		assertTrue(nextA != null && leaseC != null, "entries A and C should remain");
		final rejected = catalog.admit(NAMESPACE, d, payload("d", 40), 5);
		assertTrue(!rejected.admitted && rejected.reason == "catalog-budget-exhausted",
			"active leases should reject admission instead of exceeding the budget");
		var resetFailed = false;
		try {
			catalog.resetAll();
		} catch (_:Dynamic) {
			resetFailed = true;
		}
		assertTrue(resetFailed, "active leases should make reset fail closed");
		nextA.close();
		leaseC.close();

		final conflict = catalog.admit(NAMESPACE, a, payload("changed", 40), 5);
		assertTrue(!conflict.admitted
			&& conflict.reason == "same-key-different-payload", "one request key must never silently accept different payload bytes");
		final stats = catalog.snapshotStats();
		assertTrue(stats.payloadBytes + stats.estimatedOverheadBytes <= stats.totalBudgetBytes, "catalog accounting should stay within its hard cap");
		assertTrue(stats.evictions == 1 && stats.quarantines == 1 && stats.activeLeases == 0,
			"eviction, quarantine, and lease counters should explain catalog state");
	}

	static function testCapsNamespaceResetAndRealm():Void {
		final catalog = new TargetReuseCatalog(100, 60);
		final oversized = catalog.admit(NAMESPACE, revision("oversized"), payload("x", 61), 0);
		assertTrue(!oversized.admitted
			&& oversized.reason == "entry-budget-exceeded", "single-entry cap should reject oversized payloads");
		catalog.admit(NAMESPACE, revision("one"), payload("1", 20), 4);
		catalog.admit("other.target/v1", revision("two"), payload("2", 20), 4);
		catalog.resetNamespace(NAMESPACE);
		assertTrue(catalog.snapshotStats().entryCount == 1, "namespace reset should preserve unrelated entries");
		catalog.resetAll();
		assertTrue(catalog.snapshotStats().entryCount == 0
			&& catalog.snapshotStats().payloadBytes == 0, "full reset should clear entries and payload bytes");

		TargetReuseCatalog.resetShared("fixture-start");
		final first = TargetReuseCatalog.beginSharedRequest();
		final second = TargetReuseCatalog.beginSharedRequest();
		assertTrue(first.identityRevision == second.identityRevision && !first.survivedPriorRequest && second.survivedPriorRequest,
			"one macro realm should retain its identity across requests");
		TargetReuseCatalog.resetShared("fixture-explicit-reset");
		final afterReset = TargetReuseCatalog.beginSharedRequest();
		assertTrue(afterReset.identityRevision == first.identityRevision
			&& afterReset.resetGeneration == first.resetGeneration + 1
			&& afterReset.lastResetCause == "fixture-explicit-reset",
			"explicit reset should clear catalog state without pretending to replace the realm");
	}

	static function main():Void {
		testAdmissionLeaseAndEviction();
		testCapsNamespaceResetAndRealm();
		Sys.println("REFLAXE_TARGET_REUSE_CATALOG:PASS");
	}
}
