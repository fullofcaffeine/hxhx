public static bool exists(object path) {
  return System.IO.File.Exists(System.Convert.ToString(path)) || System.IO.Directory.Exists(System.Convert.ToString(path));
}
public static bool isDirectory(object path) {
  return System.IO.Directory.Exists(System.Convert.ToString(path));
}
public static void createDirectory(object path) {
  System.IO.Directory.CreateDirectory(System.Convert.ToString(path));
}
public static void deleteFile(object path) {
  if (System.IO.File.Exists(System.Convert.ToString(path))) System.IO.File.Delete(System.Convert.ToString(path));
}
public static void deleteDirectory(object path) {
  if (System.IO.Directory.Exists(System.Convert.ToString(path))) System.IO.Directory.Delete(System.Convert.ToString(path), true);
}
public static void rename(object from, object to) {
  var src = System.Convert.ToString(from);
  var dst = System.Convert.ToString(to);
  if (System.IO.Directory.Exists(src)) { if (System.IO.Directory.Exists(dst)) System.IO.Directory.Delete(dst, true); System.IO.Directory.Move(src, dst); }
  else { if (System.IO.File.Exists(dst)) System.IO.File.Delete(dst); System.IO.File.Move(src, dst); }
}
public static object stat(object path) {
  return exists(path) ? new object() : null;
}
public static string absolutePath(object path) {
  return System.IO.Path.GetFullPath(System.Convert.ToString(path));
}
public static string fullPath(object path) {
  return absolutePath(path);
}
