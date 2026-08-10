package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.ast.OcamlCodeIdentifierScanner;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

private enum OcamlGeneratedTextChunk {
	Literal(value:String);
	RuntimeUse(reference:OcamlRuntimeReference, marker:String);
	LegacyRuntimeUse(id:String, exactSymbol:String, marker:String);
	ProgramIdentifier(id:String, exactIdentifier:String, marker:String);
}

/**
	Immutable-by-contract output from one checked compiler-generated text plan.

	The content hash covers the exact bytes written to the generated OCaml file.
	Callers verify this record immediately before publication so a stale or changed
	buffer cannot silently reuse the original plan receipt.
**/
@:allow(reflaxe.ocaml.runtimegen.OcamlCheckedGeneratedText)
class OcamlCheckedGeneratedTextRecord {
	public final ownerId:String;
	public final planRevision:String;
	public var orderedUseIds(get, never):Array<String>;
	public var runtimeReferences(get, never):Array<OcamlRuntimeReference>;
	public var legacyUseIds(get, never):Array<String>;
	public var programIdentifierIds(get, never):Array<String>;
	public final content:String;
	public final contentHash:String;

	final orderedUseIdsValue:Array<String>;
	final runtimeReferencesValue:Array<OcamlRuntimeReference>;
	final legacyUseIdsValue:Array<String>;
	final programIdentifierIdsValue:Array<String>;

	private function new(ownerId:String, planRevision:String, orderedUseIds:Array<String>, runtimeReferences:Array<OcamlRuntimeReference>,
			legacyUseIds:Array<String>, programIdentifierIds:Array<String>, content:String, contentHash:String) {
		this.ownerId = ownerId;
		this.planRevision = planRevision;
		this.orderedUseIdsValue = orderedUseIds.copy();
		this.runtimeReferencesValue = runtimeReferences.copy();
		this.legacyUseIdsValue = legacyUseIds.copy();
		this.programIdentifierIdsValue = programIdentifierIds.copy();
		this.content = content;
		this.contentHash = contentHash;
	}

	function get_orderedUseIds():Array<String> {
		return orderedUseIdsValue.copy();
	}

	function get_runtimeReferences():Array<OcamlRuntimeReference> {
		return runtimeReferencesValue.copy();
	}

	function get_legacyUseIds():Array<String> {
		return legacyUseIdsValue.copy();
	}

	function get_programIdentifierIds():Array<String> {
		return programIdentifierIdsValue.copy();
	}
}

/**
	Builds compiler-generated OCaml text from ordinary literals and checked
	private-runtime placeholders.

	For example, a plugin entry may add `"  "`, then one authorized placeholder
	for `HxHxBackendPluginHost.register_provider_type`, then the escaped string
	arguments. The final scanner sees the whole file at once. It rejects a private
	runtime name hidden in literal code and proves that every placeholder occupies
	a real OCaml identifier position rather than a string or comment.
**/
class OcamlCheckedGeneratedText {
	static inline final MARKER_PREFIX = "ReflaxeCheckedRuntimeUse";
	static inline final LEGACY_MARKER_PREFIX = "ReflaxeLegacyRuntimeUse";
	static inline final PROGRAM_IDENTIFIER_MARKER_PREFIX = "ReflaxeProgramIdentifier";

	final ownerId:String;
	final planRevision:String;
	final authority:OcamlRuntimeUseAuthority;
	final chunks:Array<OcamlGeneratedTextChunk> = [];
	final runtimeReferences:Array<OcamlRuntimeReference> = [];
	final legacyUseIds:Array<String> = [];
	final programIdentifierIds:Array<String> = [];
	var sealed:Bool = false;

	public function new(ownerId:String, planRevision:String, activeProfile:String, requirements:Array<OcamlRuntimeRequirement>,
			occurrences:Array<OcamlRuntimeUseOccurrence>, ?finalOutputAuthority:OcamlFinalRuntimeUseAuthority) {
		this.ownerId = requiredLogicalId(ownerId, "generated-text owner");
		this.planRevision = requiredLogicalId(planRevision, "generated-text plan revision");
		for (occurrence in occurrences)
			if (occurrence.ownerId != this.ownerId)
				throw 'Checked generated text use ${occurrence.id} belongs to ${occurrence.ownerId}; expected ${this.ownerId}.';
		this.authority = new OcamlRuntimeUseAuthority(planRevision, activeProfile, requirements, occurrences, finalOutputAuthority);
	}

	/** Creates a deterministic plan identity from logical, path-safe inputs. */
	public static function revision(ownerId:String, inputs:Array<String>):String {
		final owner = requiredLogicalId(ownerId, "generated-text owner");
		final values = ["ocaml-checked-generated-text-v1", owner].concat(inputs == null ? [] : inputs.map(value -> value == null ? "" : value));
		return "sha256:" + Sha256.encode(values.map(value -> value.length + ":" + value).join("|"));
	}

	/** Adds ordinary generated OCaml text. Private runtime names are checked at seal time. */
	public function addLiteral(value:String):Void {
		ensureOpen();
		if (value == null)
			throw "Checked generated text cannot add a null literal chunk.";
		chunks.push(Literal(value));
	}

	/** Adds one private-runtime name after consuming its sealed use occurrence. */
	public function addRuntimeUse(id:String, requestedPlanRevision:String, exactSymbol:String):Void {
		ensureOpen();
		final reference = authority.generatedTextIdentifier(id, requestedPlanRevision, exactSymbol);
		final marker = MARKER_PREFIX + Std.string(runtimeReferences.length);
		runtimeReferences.push(reference);
		chunks.push(RuntimeUse(reference, marker));
	}

	/**
		Adds one still-unmigrated private-runtime name without granting it semantic
		authority.

		This is a temporary bridge for a generated file whose checked and unchecked
		sections cannot be published separately. The marker proves that the name is
		an OCaml code identifier in the complete file, while `legacyUseIds` keeps the
		remaining debt visible to tests and the migration inventory. Callers must not
		interpret this as a checked runtime use.
	**/
	public function addLegacyRuntimeUse(id:String, exactSymbol:String):Void {
		ensureOpen();
		final stableId = requiredLogicalId(id, "legacy generated-text runtime use identity");
		if (!~/^Hx[A-Z][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_']*$/.match(exactSymbol))
			throw 'Legacy generated-text runtime use $stableId requires one exact private runtime symbol, received $exactSymbol.';
		if (legacyUseIds.contains(stableId))
			throw 'Legacy generated-text runtime use $stableId was constructed more than once.';
		for (reference in runtimeReferences)
			if (reference.id == stableId)
				throw 'Generated-text runtime use $stableId cannot be both checked and legacy.';
		final marker = LEGACY_MARKER_PREFIX + Std.string(legacyUseIds.length);
		legacyUseIds.push(stableId);
		chunks.push(LegacyRuntimeUse(stableId, exactSymbol, marker));
	}

	/**
		Adds a compiler-provided program identifier that only resembles a private
		runtime name.

		For example, a user class named `HxProgramOwned` may produce an OCaml module
		with that exact name. This placeholder proves its code position but does not
		create a runtime-use receipt. Access is restricted to the type-registry
		emitter, which receives these names from the current typed program snapshot.
	**/
	@:allow(reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter)
	private function addProgramIdentifier(id:String, exactIdentifier:String):Void {
		ensureOpen();
		final stableId = requiredLogicalId(id, "generated-text program identifier identity");
		if (!~/^[A-Za-z_][A-Za-z0-9_']*$/.match(exactIdentifier))
			throw 'Generated-text program identifier $stableId is not one exact OCaml identifier: $exactIdentifier.';
		if (programIdentifierIds.contains(stableId))
			throw 'Generated-text program identifier $stableId was constructed more than once.';
		final marker = PROGRAM_IDENTIFIER_MARKER_PREFIX + Std.string(programIdentifierIds.length);
		programIdentifierIds.push(stableId);
		chunks.push(ProgramIdentifier(stableId, exactIdentifier, marker));
	}

	/** Seals, reconciles, renders, hashes, and verifies the complete generated file. */
	public function seal():OcamlCheckedGeneratedTextRecord {
		ensureOpen();
		sealed = true;
		authority.reconcileGeneratedText(runtimeReferences);

		final content = new StringBuf();
		final sanitized = new StringBuf();
		final literalsOnly = new StringBuf();
		final markerIds:Array<String> = [];
		for (chunk in chunks) {
			switch (chunk) {
				case Literal(value):
					content.add(value);
					sanitized.add(value);
					literalsOnly.add(value);
				case RuntimeUse(reference, marker):
					content.add(reference.exactSymbol);
					sanitized.add(marker);
					// A space prevents surrounding literal chunks from forming one
					// marker-shaped identifier across this checked placeholder.
					literalsOnly.add(" ");
					markerIds.push(marker);
				case LegacyRuntimeUse(_, exactSymbol, marker):
					content.add(exactSymbol);
					sanitized.add(marker);
					literalsOnly.add(" ");
					markerIds.push(marker);
				case ProgramIdentifier(_, exactIdentifier, marker):
					content.add(exactIdentifier);
					sanitized.add(marker);
					literalsOnly.add(" ");
					markerIds.push(marker);
			}
		}

		final forgedMarkers = OcamlCodeIdentifierScanner.scan(literalsOnly.toString())
			.filter(identifier -> identifier.startsWith(MARKER_PREFIX)
				|| identifier.startsWith(LEGACY_MARKER_PREFIX)
				|| identifier.startsWith(PROGRAM_IDENTIFIER_MARKER_PREFIX));
		if (forgedMarkers.length > 0)
			throw 'Checked generated text for $ownerId contains reserved generated-text placeholder ${forgedMarkers[0]} in an unchecked literal.';
		final codeIdentifiers = OcamlCodeIdentifierScanner.scan(sanitized.toString());
		final privateNames = codeIdentifiers.filter(OcamlCodeIdentifierScanner.isPrivateRuntimeIdentifier);
		if (privateNames.length > 0)
			throw 'Checked generated text for $ownerId contains private runtime name ${privateNames[0]} in an unchecked literal.';
		final observedMarkers = codeIdentifiers.filter(identifier -> markerIds.contains(identifier));
		if (observedMarkers.join("|") != markerIds.join("|"))
			throw 'Checked generated text placeholder is not an OCaml code identifier in planned order for $ownerId.';

		final exactContent = content.toString();
		final orderedUseIds = runtimeReferences.map(reference -> reference.id);
		final record = new OcamlCheckedGeneratedTextRecord(ownerId, planRevision, orderedUseIds, runtimeReferences, legacyUseIds, programIdentifierIds,
			exactContent, "sha256:" + Sha256.encode(exactContent));
		verify(record);
		return record;
	}

	/** Rechecks the exact bytes immediately before an output transaction writes them. */
	public static function verify(record:OcamlCheckedGeneratedTextRecord):Void {
		if (record == null)
			throw "Checked generated text record is missing.";
		requiredLogicalId(record.ownerId, "generated-text record owner");
		requiredLogicalId(record.planRevision, "generated-text record plan revision");
		final expectedHash = "sha256:" + Sha256.encode(record.content);
		if (record.contentHash != expectedHash)
			throw 'Checked generated text content hash mismatch for ${record.ownerId}: expected $expectedHash, received ${record.contentHash}.';
		final seen:Map<String, Bool> = [];
		final orderedUseIds = record.orderedUseIds;
		final runtimeReferences = record.runtimeReferences;
		if (runtimeReferences.length != orderedUseIds.length)
			throw 'Checked generated text record ${record.ownerId} lost hidden runtime reference facts.';
		for (index in 0...orderedUseIds.length) {
			final id = orderedUseIds[index];
			final stableId = requiredLogicalId(id, "generated-text runtime use identity");
			if (seen.exists(stableId))
				throw 'Checked generated text record ${record.ownerId} repeats runtime use $stableId.';
			final reference = runtimeReferences[index];
			if (reference.id != stableId || reference.planRevision != record.planRevision || reference.ownerId != record.ownerId)
				throw 'Checked generated text record ${record.ownerId} has stale hidden runtime reference $stableId.';
			seen.set(stableId, true);
		}
		for (id in record.legacyUseIds) {
			final stableId = requiredLogicalId(id, "legacy generated-text runtime use identity");
			if (seen.exists(stableId))
				throw 'Checked generated text record ${record.ownerId} repeats or launders legacy runtime use $stableId.';
			seen.set(stableId, true);
		}
		for (id in record.programIdentifierIds) {
			final stableId = requiredLogicalId(id, "generated-text program identifier identity");
			if (seen.exists(stableId))
				throw 'Checked generated text record ${record.ownerId} repeats program identifier $stableId.';
			seen.set(stableId, true);
		}
	}

	function ensureOpen():Void {
		if (sealed)
			throw 'Checked generated text for $ownerId is already sealed.';
	}

	static function requiredLogicalId(value:String, label:String):String {
		final normalized = value == null ? "" : value.trim();
		if (normalized.length == 0)
			throw 'Checked generated text requires a non-empty $label.';
		if (normalized.startsWith("/")
			|| ~/^[A-Za-z]:[\\\/]/.match(normalized)
			|| normalized.indexOf("\\") >= 0
			|| normalized.indexOf("../") >= 0)
			throw 'Checked generated text $label must be a logical identity, not a machine-local path.';
		return normalized;
	}
}
#end
