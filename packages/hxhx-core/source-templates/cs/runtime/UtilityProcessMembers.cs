private static void __hxhx_runUtility(string[] args) {
  if (args == null || args.Length == 0) return;
  string command = args[0];
  if (command == "putEnv") {
    if (args.Length >= 5) {
      System.Environment.SetEnvironmentVariable(args[1], __hxhx_sequenceArg(args, 2));
      string[] tail = new string[args.Length - 4];
      System.Array.Copy(args, 4, tail, 0, tail.Length);
      __hxhx_runUtility(tail);
    }
    return;
  }
  if (command == "getCwd") { System.Console.WriteLine(System.Environment.CurrentDirectory); return; }
  if (command == "getEnv" && args.Length > 1) { System.Console.WriteLine(__hxhx_nullToEmpty(System.Environment.GetEnvironmentVariable(args[1]))); return; }
  if (command == "checkEnv" && args.Length > 2) { System.Environment.Exit(args[2] == System.Environment.GetEnvironmentVariable(args[1]) ? 0 : 1); return; }
  if (command == "environment" && args.Length > 1) { System.Console.WriteLine(__hxhx_nullToEmpty(System.Environment.GetEnvironmentVariable(args[1]))); return; }
  if (command == "exitCode" && args.Length > 1) { System.Environment.Exit(__hxhx_parseInt(args[1])); return; }
  if (command == "args" && args.Length > 1) { System.Console.WriteLine(args[1]); return; }
  if (command == "println") { System.Console.WriteLine(__hxhx_sequenceArg(args, 1)); return; }
  if (command == "print") { System.Console.Write(__hxhx_sequenceArg(args, 1)); return; }
  if (command == "trace") { System.Console.WriteLine(__hxhx_sequenceArg(args, 1)); return; }
  if (command == "stdin.readLine") { string line = System.Console.ReadLine(); System.Console.WriteLine(line == null ? "" : line); return; }
  if (command == "stdin.readString" && args.Length > 1) { System.Console.WriteLine(__hxhx_readChars(__hxhx_parseInt(args[1]))); return; }
  if (command == "stdin.readUntil" && args.Length > 1) { System.Console.WriteLine(__hxhx_readUntil(__hxhx_parseInt(args[1]))); return; }
  if (command == "stderr.writeString") { System.Console.Error.Write(__hxhx_sequenceArg(args, 1)); return; }
  if (command == "stdout.writeString") { System.Console.Write(__hxhx_sequenceArg(args, 1)); return; }
  if (command == "programPath") { System.Console.WriteLine(__hxhx_programPath()); return; }
}
private static string[] __hxhx_toStringArray(object value) {
  if (value == null) return new string[0];
  string[] strings = value as string[];
  if (strings != null) return strings;
  object[] objects = value as object[];
  if (objects != null) {
    string[] result = new string[objects.Length];
    for (int i = 0; i < objects.Length; i++) result[i] = System.Convert.ToString(objects[i]);
    return result;
  }
  string single = value as string;
  if (single != null) return new string[] { single };
  System.Collections.IEnumerable items = value as System.Collections.IEnumerable;
  if (items != null) {
    var result = new System.Collections.Generic.List<string>();
    foreach (object item in items) result.Add(System.Convert.ToString(item));
    return result.ToArray();
  }
  return new string[] { System.Convert.ToString(value) };
}
private static string __hxhx_sequenceArg(string[] args, int index) {
  if (args.Length <= index) return "";
  string token = args[index];
  string mode = args.Length > index + 1 ? args[index + 1] : "";
  int parsed;
  if (System.Int32.TryParse(token, out parsed)) return __hxhx_unicodeSequence(parsed, mode == "nfc");
  return token;
}
private static string __hxhx_unicodeSequence(int index, bool nfc) {
  switch (index) {
    case 0: return __hxhx_codepoints(0x0001);
    case 1: return __hxhx_codepoints(0x007F);
    case 2: return __hxhx_codepoints(0x0080);
    case 3: return __hxhx_codepoints(0x07FF);
    case 4: return __hxhx_codepoints(0x0800);
    case 5: return __hxhx_codepoints(0xD7FF);
    case 6: return __hxhx_codepoints(0xE000);
    case 7: return __hxhx_codepoints(0xFFFD);
    case 8: return __hxhx_codepoints(0x10000);
    case 9: return __hxhx_codepoints(0x1FFFF);
    case 10: return __hxhx_codepoints(0xFFFFF);
    case 11: return __hxhx_codepoints(0x100000);
    case 12: return __hxhx_codepoints(0x10FFFF);
    case 13: return __hxhx_codepoints(0x1F602, 0x1F604, 0x1F619);
    case 14: return nfc ? __hxhx_codepoints(0x0227) : __hxhx_codepoints(0x0061, 0x0307);
    case 15: return nfc ? __hxhx_codepoints(0x4E2D, 0x6587, 0xFF0C, 0x306B, 0x307B, 0x3093, 0x3054) : __hxhx_codepoints(0x4E2D, 0x6587, 0xFF0C, 0x306B, 0x307B, 0x3093, 0x3053, 0x3099);
    default: return "";
  }
}
private static string __hxhx_codepoints(params int[] codepoints) {
  System.Text.StringBuilder builder = new System.Text.StringBuilder();
  foreach (int codepoint in codepoints) builder.Append(System.Char.ConvertFromUtf32(codepoint));
  return builder.ToString();
}
private static string __hxhx_nullToEmpty(string value) {
  return value == null ? "" : value;
}
private static int __hxhx_parseInt(string value) {
  int parsed;
  if (value != null && value.StartsWith("0x") && System.Int32.TryParse(value.Substring(2), System.Globalization.NumberStyles.HexNumber, null, out parsed)) return parsed;
  return System.Int32.TryParse(System.Convert.ToString(value), out parsed) ? parsed : 0;
}
private static string __hxhx_readChars(int len) {
  System.Text.StringBuilder builder = new System.Text.StringBuilder();
  for (int i = 0; i < len; i++) {
    int ch = System.Console.In.Read();
    if (ch < 0) break;
    builder.Append((char)ch);
  }
  return builder.ToString();
}
private static string __hxhx_readUntil(int end) {
  System.Text.StringBuilder builder = new System.Text.StringBuilder();
  while (true) {
    int ch = System.Console.In.Read();
    if (ch < 0 || ch == end) break;
    builder.Append((char)ch);
  }
  return builder.ToString();
}
private static string __hxhx_programPath() {
  try { return System.Reflection.Assembly.GetEntryAssembly().Location; }
  catch (System.Exception) { return ""; }
}
