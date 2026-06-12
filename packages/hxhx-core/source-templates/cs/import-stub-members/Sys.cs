public static string systemName() {
  var platform = (int)System.Environment.OSVersion.Platform;
  if (platform == 2) return "Windows";
  if (System.IO.Directory.Exists("/Applications") && System.IO.Directory.Exists("/System")) return "Mac";
  return "Linux";
}
public static int command(object command, object args = null) {
  var process = new System.Diagnostics.Process();
  process.StartInfo.FileName = System.Convert.ToString(command);
  process.StartInfo.Arguments = __hxhx_joinArgs(args);
  process.StartInfo.UseShellExecute = false;
  process.Start();
  process.WaitForExit();
  return process.ExitCode;
}
public static string programPath() {
  return System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
}
public static string getCwd() {
  return System.IO.Directory.GetCurrentDirectory();
}
public static void exit(object code) {
  System.Environment.Exit(System.Convert.ToInt32(code));
}
private static string __hxhx_joinArgs(object values) {
  var parts = __hxhx_toStringArray(values);
  for (int i = 0; i < parts.Length; i++) parts[i] = __hxhx_quoteArg(parts[i]);
  return string.Join(" ", parts);
}
private static string[] __hxhx_toStringArray(object values) {
  if (values == null) return new string[0];
  if (values is string) return new string[] { System.Convert.ToString(values) };
  var list = new System.Collections.Generic.List<string>();
  var enumerable = values as System.Collections.IEnumerable;
  if (enumerable != null) {
    foreach (object item in enumerable) list.Add(System.Convert.ToString(item));
    return list.ToArray();
  }
  return new string[] { System.Convert.ToString(values) };
}
private static string __hxhx_quoteArg(string value) {
  if (value == null) return "\"\"";
  if (value.IndexOfAny(new char[] { ' ', '\t', '\n', '\r', '\"' }) < 0) return value;
  return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
}
