package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

private enum OcamlGeneratedTextChunk {
	Literal(value:String);
	RuntimeUse(reference:OcamlRuntimeReference, marker:String);
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
	public final content:String;
	public final contentHash:String;

	final orderedUseIdsValue:Array<String>;

	private function new(ownerId:String, planRevision:String, orderedUseIds:Array<String>, content:String, contentHash:String) {
		this.ownerId = ownerId;
		this.planRevision = planRevision;
		this.orderedUseIdsValue = orderedUseIds.copy();
		this.content = content;
		this.contentHash = contentHash;
	}

	function get_orderedUseIds():Array<String> {
		return orderedUseIdsValue.copy();
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

	final ownerId:String;
	final planRevision:String;
	final authority:OcamlRuntimeUseAuthority;
	final chunks:Array<OcamlGeneratedTextChunk> = [];
	final runtimeReferences:Array<OcamlRuntimeReference> = [];
	var sealed:Bool = false;

	public function new(ownerId:String, planRevision:String, activeProfile:String, requirements:Array<OcamlRuntimeRequirement>,
			occurrences:Array<OcamlRuntimeUseOccurrence>) {
		this.ownerId = requiredLogicalId(ownerId, "generated-text owner");
		this.planRevision = requiredLogicalId(planRevision, "generated-text plan revision");
		for (occurrence in occurrences)
			if (occurrence.ownerId != this.ownerId)
				throw 'Checked generated text use ${occurrence.id} belongs to ${occurrence.ownerId}; expected ${this.ownerId}.';
		this.authority = new OcamlRuntimeUseAuthority(planRevision, activeProfile, requirements, occurrences);
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
			}
		}

		final forgedMarkers = scanCodeIdentifiers(literalsOnly.toString()).filter(identifier -> identifier.startsWith(MARKER_PREFIX));
		if (forgedMarkers.length > 0)
			throw 'Checked generated text for $ownerId contains reserved runtime placeholder ${forgedMarkers[0]} in an unchecked literal.';
		final codeIdentifiers = scanCodeIdentifiers(sanitized.toString());
		final privateNames = codeIdentifiers.filter(isPrivateRuntimeName);
		if (privateNames.length > 0)
			throw 'Checked generated text for $ownerId contains private runtime name ${privateNames[0]} in an unchecked literal.';
		final observedMarkers = codeIdentifiers.filter(identifier -> markerIds.contains(identifier));
		if (observedMarkers.join("|") != markerIds.join("|"))
			throw 'Checked generated text runtime placeholder is not an OCaml code identifier in planned order for $ownerId.';

		final exactContent = content.toString();
		final orderedUseIds = runtimeReferences.map(reference -> reference.id);
		final record = new OcamlCheckedGeneratedTextRecord(ownerId, planRevision, orderedUseIds, exactContent, "sha256:" + Sha256.encode(exactContent));
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
		for (id in record.orderedUseIds) {
			final stableId = requiredLogicalId(id, "generated-text runtime use identity");
			if (seen.exists(stableId))
				throw 'Checked generated text record ${record.ownerId} repeats runtime use $stableId.';
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

	static function isIdentifierStart(code:Int):Bool {
		return (code >= "A".code && code <= "Z".code) || (code >= "a".code && code <= "z".code) || code == "_".code;
	}

	static function isIdentifierPart(code:Int):Bool {
		return isIdentifierStart(code) || (code >= "0".code && code <= "9".code) || code == "'".code;
	}

	static function isPrivateRuntimeName(identifier:String):Bool {
		if (identifier.length < 3 || !identifier.startsWith("Hx"))
			return false;
		final third = identifier.fastCodeAt(2);
		return third >= "A".code && third <= "Z".code;
	}

	/** Returns identifiers that occur in OCaml code, excluding strings and nested comments. */
	static function scanCodeIdentifiers(text:String):Array<String> {
		final out:Array<String> = [];
		var index = 0;
		var inString = false;
		var commentDepth = 0;
		while (index < text.length) {
			final code = text.fastCodeAt(index);
			final next = index + 1 < text.length ? text.fastCodeAt(index + 1) : -1;
			if (commentDepth > 0) {
				if (code == "(".code && next == "*".code) {
					commentDepth++;
					index += 2;
				} else if (code == "*".code && next == ")".code) {
					commentDepth--;
					index += 2;
				} else {
					index++;
				}
				continue;
			}
			if (inString) {
				if (code == "\\".code) {
					index += 2;
				} else {
					if (code == '"'.code)
						inString = false;
					index++;
				}
				continue;
			}
			if (code == "(".code && next == "*".code) {
				commentDepth = 1;
				index += 2;
				continue;
			}
			if (code == '"'.code) {
				inString = true;
				index++;
				continue;
			}
			if (isIdentifierStart(code)) {
				final start = index;
				index++;
				while (index < text.length && isIdentifierPart(text.fastCodeAt(index)))
					index++;
				out.push(text.substring(start, index));
				continue;
			}
			index++;
		}
		return out;
	}
}
#end
