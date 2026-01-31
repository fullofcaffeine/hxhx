import sys.FileSystem;
import sys.io.File;
import Ast;
import Module;
import CompileResult;
import CompileStats;

/**
	A “project compiler” that:

	- reads modules from a directory
	- parses them
	- type checks them
	- supports an incremental cache keyed by `FileSystem.stat(path).mtime`
**/
class ProjectCompiler {
	final cacheByPath = new haxe.ds.StringMap<Module>();
	final mtimeByPath = new haxe.ds.StringMap<Float>();

	public function new() {}

	public function compileProject(dir:String):CompileResult {
		final stats = new CompileStats();
		final modules:Array<Module> = [];

		final entries = FileSystem.readDirectory(dir);
		entries.sort((a, b) -> (a < b) ? -1 : ((a > b) ? 1 : 0));
		Sys.println("pc.entries=" + entries.length);
		stats.files = entries.length;

		var idx = 0;
		while (idx < entries.length) {
			final name = entries[idx];
			idx++;
			if (name.length < 4 || name.substr(name.length - 4) != ".mhx") continue;
			Sys.println("pc.file=" + name);

			final path = dir + "/" + name;
			Sys.println("pc.stat");
			final st = FileSystem.stat(path);
			final mt = st.mtime.getTime();
			if (!(mt > 0)) stats.mtimePositive = false;

			final prev = mtimeByPath.get(path);
			if (prev != null && prev == mt && cacheByPath.exists(path)) {
				stats.cached = stats.cached + 1;
				modules.push(cacheByPath.get(path));
				continue;
			}

			Sys.println("pc.read");
			final src = File.getContent(path);
			final modName = name.substring(0, name.length - 4);
			Sys.println("pc.parse=" + modName);
			final m = new Parser(src).parseModule(modName);
			Sys.println("pc.typecheck=" + modName);
			TypeChecker.checkModule(m);

			stats.parsed = stats.parsed + 1;
			mtimeByPath.set(path, mt);
			cacheByPath.set(path, m);
			modules.push(m);
		}

		return new CompileResult(stats, modules);
	}
}
