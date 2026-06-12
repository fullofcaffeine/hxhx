public static string getContent(object path) {
  return System.IO.File.ReadAllText(System.Convert.ToString(path));
}
public static void saveContent(object path, object content) {
  System.IO.File.WriteAllText(System.Convert.ToString(path), System.Convert.ToString(content));
}
public static void copy(object src, object dst) {
  System.IO.File.Copy(System.Convert.ToString(src), System.Convert.ToString(dst), true);
}
