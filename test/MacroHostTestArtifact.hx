import haxe.crypto.Sha256;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/**
	Resolves the macro host used by the expensive integration fixtures.

	A direct test invocation builds the smallest host needed by that one test.
	The Core CI shard may instead provide one shared host. Shared mode is
	fail-closed: the candidate commit, reviewed plan digest, exact executable,
	entrypoint set, byte count, and SHA-256 digest must all match before the
	caller can begin its semantic assertions.
**/
class MacroHostTestArtifact {
	static final PLAN_PATH = "scripts/ci/macro-host-integration-plan.json";
	static final PLAN_SCHEMA = "hxhx.macro-host-integration-plan.v1";
	static final ARTIFACT_SCHEMA = "hxhx.macro-host-test-artifact.v1";

	static function fail(message:String):Dynamic {
		throw "shared macro-host artifact: " + message;
	}

	static function requiredField(value:Dynamic, field:String, owner:String):Dynamic {
		if (value == null || !Reflect.hasField(value, field))
			return fail(owner + "." + field + " is missing");
		return Reflect.field(value, field);
	}

	static function requiredString(value:Dynamic, field:String, owner:String):String {
		final result = requiredField(value, field, owner);
		if (!Std.isOfType(result, String) || StringTools.trim(result).length == 0)
			return fail(owner + "." + field + " must be a non-empty string");
		return cast result;
	}

	static function stringArray(value:Dynamic, owner:String):Array<String> {
		if (!Std.isOfType(value, Array))
			return fail(owner + " must be an array");
		final result = new Array<String>();
		for (item in (cast value : Array<Dynamic>)) {
			if (!Std.isOfType(item, String) || StringTools.trim(cast item).length == 0)
				return fail(owner + " contains an invalid value");
			result.push(cast item);
		}
		return result;
	}

	static function readJson(path:String, owner:String):{raw:String, value:Dynamic} {
		if (!FileSystem.exists(path) || FileSystem.isDirectory(path))
			return fail(owner + " is missing: " + path);
		final raw = File.getContent(path);
		try {
			return {raw: raw, value: haxe.Json.parse(raw)};
		} catch (error:Dynamic) {
			return fail(owner + " is not valid JSON: " + Std.string(error));
		}
	}

	static function planFor(consumerId:String):{
		entrypoints:Array<String>,
		entrypointUnion:Array<String>,
		extraClassPaths:Array<String>,
		sha256:String
	} {
		final parsed = readJson(PLAN_PATH, "integration plan");
		final plan = parsed.value;
		if (requiredString(plan, "schema", "plan") != PLAN_SCHEMA)
			return fail("plan schema changed");
		final consumers = requiredField(plan, "consumers", "plan");
		if (!Reflect.hasField(consumers, consumerId))
			return fail("plan has no consumer " + consumerId);
		final entrypointUnion = new Array<String>();
		for (candidateId in Reflect.fields(consumers))
			for (entrypoint in stringArray(Reflect.field(consumers, candidateId), "plan consumer " + candidateId))
				if (entrypointUnion.indexOf(entrypoint) < 0)
					entrypointUnion.push(entrypoint);
		return {
			entrypoints: stringArray(Reflect.field(consumers, consumerId), "plan consumer " + consumerId),
			entrypointUnion: entrypointUnion,
			extraClassPaths: stringArray(requiredField(plan, "extraClassPaths", "plan"), "plan.extraClassPaths"),
			sha256: Sha256.encode(parsed.raw).toLowerCase()
		};
	}

	static function lastNonEmptyLine(text:String):String {
		final lines = text == null ? [] : text.split("\n");
		var index = lines.length - 1;
		while (index >= 0) {
			final line = StringTools.trim(lines[index]);
			if (line.length > 0)
				return line;
			index -= 1;
		}
		return "";
	}

	/** Builds the consumer-specific host used by ordinary direct test runs. **/
	static function buildStandalone(entrypoints:Array<String>, extraClassPaths:Array<String>):String {
		final originalEntrypoints = Sys.getEnv("HXHX_MACRO_HOST_ENTRYPOINTS");
		final originalExtraClassPaths = Sys.getEnv("HXHX_MACRO_HOST_EXTRA_CP");
		final originalForceStage0 = Sys.getEnv("HXHX_MACRO_HOST_FORCE_STAGE0");
		Sys.putEnv("HXHX_MACRO_HOST_ENTRYPOINTS", entrypoints.join(";"));
		Sys.putEnv("HXHX_MACRO_HOST_EXTRA_CP", extraClassPaths.join(":"));
		Sys.putEnv("HXHX_MACRO_HOST_FORCE_STAGE0", "1");

		var process:Null<Process> = null;
		var stdout = "";
		var stderr = "";
		var code = -1;
		try {
			// Merge stderr before reading so a verbose compiler cannot fill one
			// pipe while this process is waiting on the other. The child shell can
			// also expose this Haxe process as the workspace lease owner without
			// relying on a newer Haxe API for reading the current process ID.
			final dollar = "$";
			final command = 'if [ -z "' + dollar + '{HXHX_MACRO_HOST_LEASE_PID:-}" ]; then ' + 'export HXHX_MACRO_HOST_LEASE_PID="' + dollar + 'PPID"; fi; '
				+ "exec bash scripts/hxhx/build-hxhx-macro-host.sh 2>&1";
			process = new Process("sh", ["-lc", command]);
			stdout = process.stdout.readAll().toString();
			stderr = process.stderr.readAll().toString();
			code = process.exitCode();
			process.close();
		} catch (error:Dynamic) {
			if (process != null)
				try
					process.close()
				catch (_:Dynamic) {};
			restoreBuildEnvironment(originalEntrypoints, originalExtraClassPaths, originalForceStage0);
			return fail("standalone build could not run: " + Std.string(error));
		}

		restoreBuildEnvironment(originalEntrypoints, originalExtraClassPaths, originalForceStage0);

		if (code != 0)
			return fail("standalone build failed: " + stdout + stderr);
		final executable = lastNonEmptyLine(stdout);
		if (executable.length == 0)
			return fail("standalone build produced no executable path: " + stdout);
		return executable;
	}

	static function restoreBuildEnvironment(entrypoints:Null<String>, extraClassPaths:Null<String>, forceStage0:Null<String>):Void {
		Sys.putEnv("HXHX_MACRO_HOST_ENTRYPOINTS", entrypoints);
		Sys.putEnv("HXHX_MACRO_HOST_EXTRA_CP", extraClassPaths);
		Sys.putEnv("HXHX_MACRO_HOST_FORCE_STAGE0", forceStage0);
	}

	/** Authenticates and returns the shared host, or builds a direct-run host. **/
	public static function resolve(consumerId:String):String {
		final plan = planFor(consumerId);
		final manifestPath = Sys.getEnv("HXHX_TEST_MACRO_HOST_MANIFEST");
		if (manifestPath == null || StringTools.trim(manifestPath).length == 0)
			return buildStandalone(plan.entrypoints, plan.extraClassPaths);

		final expectedCandidate = Sys.getEnv("HXHX_TEST_MACRO_HOST_CANDIDATE");
		final expectedPlanSha256 = Sys.getEnv("HXHX_TEST_MACRO_HOST_PLAN_SHA256");
		final expectedExecutable = Sys.getEnv("HXHX_MACRO_HOST_EXE");
		if (expectedCandidate == null || !~/^[0-9a-f]{40}$/.match(expectedCandidate))
			return fail("expected candidate is missing or invalid");
		if (expectedPlanSha256 == null || !~/^[0-9a-f]{64}$/.match(expectedPlanSha256))
			return fail("expected plan digest is missing or invalid");
		if (expectedPlanSha256 != plan.sha256)
			return fail("expected plan digest does not match the checked-out plan");
		if (expectedExecutable == null || StringTools.trim(expectedExecutable).length == 0)
			return fail("expected executable path is missing");

		final manifest = readJson(manifestPath, "manifest").value;
		if (requiredString(manifest, "schema", "manifest") != ARTIFACT_SCHEMA)
			return fail("manifest schema changed");
		final candidate = requiredField(manifest, "candidate", "manifest");
		if (requiredString(candidate, "commit", "manifest.candidate") != expectedCandidate)
			return fail("candidate is stale");
		if (!Std.isOfType(requiredField(candidate, "workingTreeDirty", "manifest.candidate"), Bool))
			return fail("candidate working-tree state is invalid");
		if (!~/^[0-9a-f]{64}$/.match(requiredString(candidate, "statusSha256", "manifest.candidate")))
			return fail("candidate status digest is invalid");
		final manifestPlan = requiredField(manifest, "plan", "manifest");
		if (requiredString(manifestPlan, "sha256", "manifest.plan") != expectedPlanSha256)
			return fail("plan is stale");

		final build = requiredField(manifest, "build", "manifest");
		if (requiredField(build, "invocationCount", "manifest.build") != 1)
			return fail("build count must be exactly one");
		final availableEntrypoints = stringArray(requiredField(build, "entrypoints", "manifest.build"), "manifest.build.entrypoints");
		if (availableEntrypoints.length != plan.entrypointUnion.length)
			return fail("entrypoint union disagrees with the checked-out plan");
		for (entrypoint in availableEntrypoints)
			if (plan.entrypointUnion.indexOf(entrypoint) < 0)
				return fail("entrypoint union contains unplanned entrypoint " + entrypoint);
		final availableClassPaths = stringArray(requiredField(build, "extraClassPaths", "manifest.build"), "manifest.build.extraClassPaths");
		if (availableClassPaths.length != plan.extraClassPaths.length)
			return fail("classpaths disagree with the checked-out plan");
		for (classPath in availableClassPaths)
			if (plan.extraClassPaths.indexOf(classPath) < 0)
				return fail("manifest contains unplanned classpath " + classPath);
		for (entrypoint in plan.entrypoints)
			if (availableEntrypoints.indexOf(entrypoint) < 0)
				return fail("consumer " + consumerId + " is missing entrypoint " + entrypoint);

		final artifact = requiredField(manifest, "artifact", "manifest");
		final executable = Path.normalize(requiredString(artifact, "path", "manifest.artifact"));
		if (executable != Path.normalize(expectedExecutable))
			return fail("executable path disagrees with the manifest");
		if (!FileSystem.exists(executable) || FileSystem.isDirectory(executable))
			return fail("executable is missing: " + executable);
		final expectedDigest = requiredString(artifact, "sha256", "manifest.artifact").toLowerCase();
		if (!~/^[0-9a-f]{64}$/.match(expectedDigest))
			return fail("executable digest is invalid");
		final actualDigest = Sha256.make(File.getBytes(executable)).toHex().toLowerCase();
		if (actualDigest != expectedDigest)
			return fail("executable was modified: expected " + expectedDigest + ", got " + actualDigest);
		if (FileSystem.stat(executable).size != Std.int(requiredField(artifact, "bytes", "manifest.artifact")))
			return fail("executable byte count changed");
		return executable;
	}
}
