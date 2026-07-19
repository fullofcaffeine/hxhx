# Classify only process-table rows whose executable and arguments describe a
# Haxe compilation server. Input rows must use:
#
#   pid comm command
#
# Native Haxe binaries are direct owners. Node processes count only when an
# earlier argument identifies the Haxe/Haxeshim launcher. This prevents a
# shell, test runner, or cleanup command from becoming a false match merely
# because its command text mentions "haxe --wait".

function basename(path, parts, count) {
	count = split(path, parts, "/")
	return parts[count]
}

function is_native_haxe(executable) {
	return executable == "haxe" || executable == "haxe.exe"
}

function is_node(executable) {
	return executable == "node" || executable == "node.exe"
}

function is_haxe_launcher(argument, name) {
	name = tolower(basename(argument))
	return name == "haxe" || name == "haxe.js" || name == "haxeshim" || name == "haxeshim.js"
}

{
	pid = $1
	executable = tolower(basename($2))
	server_flag_index = 0

	for (i = 3; i <= NF; i++) {
		if ($i == "--wait" || $i == "--server-connect") {
			server_flag_index = i
			break
		}
	}

	if (server_flag_index == 0)
		next

	if (is_native_haxe(executable)) {
		print pid
		next
	}

	if (!is_node(executable))
		next

	for (i = 3; i < server_flag_index; i++) {
		if (is_haxe_launcher($i)) {
			print pid
			next
		}
	}
}
