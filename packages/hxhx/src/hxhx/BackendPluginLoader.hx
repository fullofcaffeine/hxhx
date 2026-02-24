package hxhx;

import backend.BackendRegistrationSpec;

private typedef LoadedPluginSpec = {
	final spec:BackendRegistrationSpec;
	final source:BackendPluginSource;
	final origin:String;
}

/**
	Loads plugin provider registrations with deterministic source precedence.

	Why
	- Stage3 can now receive plugin providers from multiple sources in one request
	  (bundled manifests/providers and explicit user manifests/providers).
	- The registry already resolves by descriptor priority, but source precedence must be
	  deterministic even when plugins reuse the same `implId`.

	Policy
	- Source precedence: `explicit` > `bundled` > builtin baseline.
	- Source precedence is applied by reserving high priority bands per source tier.
	- Duplicate `implId` declarations within the same source tier fail fast.
**/
class BackendPluginLoader {
	public static inline var SOURCE_PRIORITY_STEP:Int = 1000000;

	static inline function trim(value:String):String {
		return value == null ? "" : StringTools.trim(value);
	}

	static inline function sourceRank(source:BackendPluginSource):Int {
		return switch (source) {
			case Explicit: 2;
			case Bundled: 1;
			case _: 0;
		}
	}

	static inline function sourcePriorityBase(source:BackendPluginSource):Int {
		return sourceRank(source) * SOURCE_PRIORITY_STEP;
	}

	static inline function sourceLabel(source:BackendPluginSource):String {
		return switch (source) {
			case Explicit: "explicit";
			case Bundled: "bundled";
			case _: Std.string(source);
		}
	}

	static function normalizeRequest(request:BackendPluginLoadRequest, index:Int):BackendPluginLoadRequest {
		if (request == null)
			throw "invalid plugin load request at index " + index + ": request is required";

		final providerType = trim(request.providerType);
		if (providerType.length == 0)
			throw "invalid plugin load request at index " + index + ": providerType is required";

		final origin = trim(request.origin);
		return {
			source: request.source,
			providerType: providerType,
			origin: origin.length == 0 ? providerType : origin
		};
	}

	static function withSourcePriority(spec:BackendRegistrationSpec, source:BackendPluginSource):BackendRegistrationSpec {
		if (spec == null || spec.descriptor == null || spec.create == null) {
			throw "invalid plugin registration from " + sourceLabel(source) + " source (descriptor/create required)";
		}

		final descriptor = spec.descriptor;
		final effectivePriority = sourcePriorityBase(source) + descriptor.priority;
		final withPriority:backend.TargetDescriptor = {
			id: descriptor.id,
			implId: descriptor.implId,
			abiVersion: descriptor.abiVersion,
			priority: effectivePriority,
			description: descriptor.description,
			capabilities: descriptor.capabilities,
			requires: descriptor.requires
		};

		return {
			descriptor: withPriority,
			create: spec.create
		};
	}

	static function selectWinning(existing:LoadedPluginSpec, incoming:LoadedPluginSpec):LoadedPluginSpec {
		final incomingRank = sourceRank(incoming.source);
		final existingRank = sourceRank(existing.source);
		if (incomingRank > existingRank)
			return incoming;
		if (incomingRank < existingRank)
			return existing;

		throw "duplicate backend plugin implementation id `" + incoming.spec.descriptor.implId + "` for source " + sourceLabel(incoming.source)
			+ " (origins: " + existing.origin + ", " + incoming.origin + ")";
	}

	/**
		Load backend registrations for the current request.

		Returns source-normalized specs ready for `BackendRegistry.registerProvider(...)`.
	**/
	public static function registrationsForRequests(requests:Array<BackendPluginLoadRequest>):Array<BackendRegistrationSpec> {
		if (requests == null || requests.length == 0)
			return [];

		final winnersByImplId = new haxe.ds.StringMap<LoadedPluginSpec>();
		var index = 0;
		for (request in requests) {
			final normalizedRequest = normalizeRequest(request, index);
			final specs = BackendProviderResolver.registrationsForType(normalizedRequest.providerType);
			for (rawSpec in specs) {
				final normalizedSpec = withSourcePriority(rawSpec, normalizedRequest.source);
				final implId = trim(normalizedSpec.descriptor.implId);
				if (implId.length == 0) {
					throw "invalid backend registration from " + normalizedRequest.origin + ": descriptor.implId is required";
				}

				final incoming:LoadedPluginSpec = {
					spec: normalizedSpec,
					source: normalizedRequest.source,
					origin: normalizedRequest.origin
				};

				final existing = winnersByImplId.get(implId);
				if (existing == null) {
					winnersByImplId.set(implId, incoming);
				} else {
					winnersByImplId.set(implId, selectWinning(existing, incoming));
				}
			}
			index++;
		}

		final out = new Array<BackendRegistrationSpec>();
		for (winner in winnersByImplId)
			out.push(winner.spec);

		out.sort(function(a, b) {
			if (a.descriptor.priority != b.descriptor.priority)
				return b.descriptor.priority - a.descriptor.priority;
			return a.descriptor.implId < b.descriptor.implId ? -1 : (a.descriptor.implId > b.descriptor.implId ? 1 : 0);
		});
		return out;
	}
}
