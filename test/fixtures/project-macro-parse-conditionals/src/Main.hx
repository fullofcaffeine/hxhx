class Main {
	static function main():Void {
		Sys.println("defined " + Parsed.pick('#if probe_flag "on" #else "off" #end'));
		Sys.println("undefined " + Parsed.pick('#if missing_flag "on" #else "off" #end'));
		Sys.println("unicode " + Parsed.pick('#if target.unicode "yes" #else "no" #end'));
		Sys.println("block " + Parsed.pick('{\n#if missing_flag\n1;\n#elseif probe_flag\n2;\n#else\n3;\n#end\n}'));
		Sys.println("macro " + Parsed.pick('#if macro "macro" #else "target" #end'));
		Sys.println("value " + Parsed.pick('#if (probe_value == "forty-two") "valued" #else "plain" #end'));
	}
}
