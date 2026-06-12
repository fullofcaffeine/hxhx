public static string join(object paths) {
  var parts = __hxhx_toStringArray(paths);
  return parts.Length == 0 ? "" : System.IO.Path.Combine(parts);
}
public static string normalize(object path) {
  return System.IO.Path.GetFullPath(System.Convert.ToString(path));
}
public static string directory(object path) {
  return System.IO.Path.GetDirectoryName(System.Convert.ToString(path));
}
public static string withoutDirectory(object path) {
  return System.IO.Path.GetFileName(System.Convert.ToString(path));
}
public static string withoutExtension(object path) {
  var value = System.Convert.ToString(path);
  var dir = System.IO.Path.GetDirectoryName(value);
  var file = System.IO.Path.GetFileNameWithoutExtension(value);
  return string.IsNullOrEmpty(dir) ? file : System.IO.Path.Combine(dir, file);
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
