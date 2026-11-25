/**
	Line starts of one source file, to turn code-point offsets into lines, columns, and the
	position text upstream Haxe 4.3.7 prints.

	Why
	- `HxSourceRange` stores offsets only. Diagnostics and macros need upstream's line and
	  column text, such as `A.hx:3: characters 23-27` or `G.hx:3: lines 3-5`.

	What
	- Offsets count Unicode code points (see `HxSourceRange`). hxhx's hosts index `String` by
	  code point, so `charCodeAt(i)` walks code points here.
	- Line breaks follow the lexer's `newline` for `.hx` files (`src/syntax/lexer.ml`,
	  lines 180-183 and 385-386): `\r\n` is one break of two code points, and a lone `\n` or a
	  lone `\r` is one break. Upstream's `resolve_pos` (lines 213-245) is used only for files the
	  lexer never read, and it is not reproduced.
	- `line` finds the last line start at or before the offset, as `find_line` does
	  (lines 185-210), so a negative offset is on line 1. Columns are 1-based, as
	  `get_pos_coords` prints them (lines 270-277).
	- `describe` gives `get_error_pos` (lines 279-290): `(unknown)` when `min == -1`,
	  `<file>:<line>: character <c>` for a zero-width range, `<file>:<line>: characters <a>-<b>`
	  on one line, and `<file>:<line>: lines <a>-<b>` across lines.
	- A file that cannot be read has one line starting at 0, as upstream reports line 1 for it.
**/
class HxLineTable {
	/** Code-point offset where each line starts; the first line starts at 0. */
	final starts:Array<Int>;

	function new(starts:Array<Int>) {
		this.starts = starts;
	}

	/** The table for this source text; `null` gives the table of an unreadable file. */
	public static function fromText(text:Null<String>):HxLineTable {
		final starts = [0];
		if (text != null) {
			var index = 0;
			final length = text.length;
			while (index < length) {
				final code = text.charCodeAt(index);
				if (code == "\r".code && index + 1 < length && text.charCodeAt(index + 1) == "\n".code) {
					index += 2;
					starts.push(index);
				} else if (code == "\n".code || code == "\r".code) {
					index++;
					starts.push(index);
				} else {
					index++;
				}
			}
		}
		return new HxLineTable(starts);
	}

	/** The table of the file at `path`, or the one-line table when it cannot be read. */
	public static function forFile(path:String):HxLineTable {
		var text:Null<String> = null;
		try {
			if (path != null && path.length > 0 && sys.FileSystem.exists(path) && !sys.FileSystem.isDirectory(path))
				text = sys.io.File.getContent(path);
		} catch (_:haxe.io.Error) {
			text = null;
		} catch (_:String) {
			text = null;
		} catch (_:haxe.Exception) {
			text = null;
		}
		return fromText(text);
	}

	/** The 1-based line of `offset`. */
	public function line(offset:Int):Int
		return startIndex(offset) + 1;

	/** The 1-based column of `offset` on its line, counted in code points. */
	public function column(offset:Int):Int
		return offset - starts[startIndex(offset)] + 1;

	/** Upstream's position text for `range`, as `get_error_pos` prints it. */
	public function describe(range:HxSourceRange):String {
		if (range.isUnknown())
			return "(unknown)";
		final startLine = line(range.min);
		final endLine = line(range.max);
		final prefix = range.file + ":" + startLine + ":";
		if (startLine != endLine)
			return prefix + " lines " + startLine + "-" + endLine;
		final startColumn = column(range.min);
		final endColumn = column(range.max);
		return startColumn == endColumn ? prefix + " character " + startColumn : prefix
			+ " characters "
			+ startColumn
			+ "-"
			+ endColumn;
	}

	/** The index of the last line start at or before `offset`; 0 for an offset before the first. */
	function startIndex(offset:Int):Int {
		var low = 0;
		var high = starts.length - 1;
		while (low < high) {
			final middle = (low + high + 1) >> 1;
			if (starts[middle] <= offset)
				low = middle
			else
				high = middle - 1;
		}
		return low;
	}
}
