///|
/// A single parsed .gitignore rule.
priv struct Rule {
  pattern : String
  negated : Bool
  dir_only : Bool
  anchored : Bool
  base : String // relative directory containing the .gitignore, "" for root
}

///|
/// One parsed .gitignore file (rules in original order; later wins).
struct RuleSet {
  rules : Array[Rule]
}

///|
/// Stack of rule sets, one per directory level (outermost first).
/// The innermost matching rule (deepest file, latest line) wins,
/// following Git semantics.
pub(all) struct IgnoreStack {
  sets : Array[(String, RuleSet)] // (dir path, rules)
}

///|
pub fn IgnoreStack::new() -> IgnoreStack {
  { sets: [], }
}

///|
fn parse_line(line : String, base : String) -> Rule? {
  if line.length() == 0 {
    return None
  }
  if starts_at(line, 0, "#") {
    return None
  }
  let mut s = line
  let mut negated = false
  if starts_at(s, 0, "!") {
    negated = true
    s = s[1:].to_owned()
  }
  if s.length() == 0 {
    return None
  }
  // Git removes unescaped trailing spaces before interpreting the pattern.
  // In particular, "build/ " is still a directory rule, while "name\\ "
  // matches a file whose name ends in a space.
  let mut trimmed = s
  while trimmed.length() > 0 &&
        ends_with(trimmed, " ") &&
        !is_escaped_at(trimmed, trimmed.length() - 1) {
    trimmed = trimmed[0:trimmed.length() - 1].to_owned()
  }
  if trimmed.length() == 0 {
    return None
  }
  s = trimmed
  let mut dir_only = false
  if ends_with(s, "/") {
    dir_only = true
    s = s[0:s.length() - 1].to_owned()
    if s.length() == 0 {
      return None
    }
  }
  let anchored = contains_str(s, "/")
  Some({ pattern: s, negated, dir_only, anchored, base, })
}

///|
fn is_escaped_at(s : String, pos : Int32) -> Bool {
  let mut backslashes = 0
  let mut i = pos - 1
  while i >= 0 && s.at(i).to_int() == 0x5C {
    backslashes += 1
    i -= 1
  }
  backslashes % 2 == 1
}

///|
fn ends_with(s : String, suffix : String) -> Bool {
  let n = s.length()
  let m = suffix.length()
  if m > n {
    return false
  }
  let mut i = 0
  while i < m {
    if s.at(n - m + i).to_int() != suffix.at(i).to_int() {
      return false
    }
    i += 1
  }
  true
}

///|
fn starts_at(s : String, pos : Int32, needle : String) -> Bool {
  let n = s.length()
  let m = needle.length()
  if pos < 0 || pos + m > n {
    return false
  }
  let mut i = 0
  while i < m {
    if s.at(pos + i).to_int() != needle.at(i).to_int() {
      return false
    }
    i += 1
  }
  true
}

///|
fn contains_str(s : String, needle : String) -> Bool {
  find_from(s, 0, needle) >= 0
}

///|
fn find_from(s : String, from : Int32, needle : String) -> Int32 {
  let n = s.length()
  let m = needle.length()
  if m == 0 {
    return from
  }
  let first = needle.at(0).to_int()
  let mut i = from
  while i + m <= n {
    if s.at(i).to_int() == first && starts_at(s, i, needle) {
      return i
    }
    i += 1
  }
  -1
}

///|
/// Load a .gitignore file located in directory `dir` and push it on the
/// stack. `dir` is the relative path ("" for the scan root).
pub fn IgnoreStack::push_file(
  self : IgnoreStack,
  dir : String,
  content : String,
) -> Unit {
  let rules : Array[Rule] = []
  let lines = split_lines(content)
  for line in lines {
    match parse_line(line, dir) {
      Some(r) => rules.push(r)
      None => ()
    }
  }
  self.sets.push((dir, { rules, }))
}

///|
pub fn IgnoreStack::pop(self : IgnoreStack) -> Unit {
  let _ = self.sets.pop()
}

///|
/// Whether `rel_path` (relative to scan root, e.g. "src/sub/a.rs") with
/// `is_dir` flag is ignored. Follows Git semantics: the last matching rule
/// (scanning from the deepest rule set, bottom-most line) wins.
pub fn IgnoreStack::is_ignored(
  self : IgnoreStack,
  rel_path : String,
  is_dir : Bool,
) -> Bool {
  // Skip Git internals always.
  let mut seg_start = 0
  let n = rel_path.length()
  let mut i = 0
  while i <= n {
    let at_end = i == n
    let is_sep = !at_end && rel_path.at(i).to_int() == 0x2F
    if is_sep || at_end {
      let seg = rel_path[seg_start:i].to_owned()
      if seg == ".git" {
        return true
      }
      seg_start = i + 1
    }
    i += 1
  }
  // Scan rule sets from deepest (last pushed) to shallowest.
  let len = self.sets.length()
  let mut k = len - 1
  while k >= 0 {
    let set = self.sets[k].1
    let rcount = set.rules.length()
    let mut r = rcount - 1
    while r >= 0 {
      let rule = set.rules[r]
      // Rule applies only under its base directory.
      if rule.base.length() == 0 {
        // root or any: matches anywhere (base "" = scan root)
      } else if rule.base.length() > 0 &&
        rel_path.length() > rule.base.length() &&
        starts_at(rel_path, 0, rule.base + "/") {
        // under base
      } else {
        r -= 1
        continue
      }
      // Path relative to the rule's base for anchored matching.
      let rel = if rule.base.length() == 0 {
        rel_path
      } else {
        rel_path[rule.base.length() + 1:].to_owned()
      }
      if rule.dir_only && !is_dir {
        // A dir-only rule can still ignore files *inside* the dir;
        // that is handled when we match an ancestor dir. Here skip.
        r -= 1
        continue
      }
      if match_rule(rule, rel, is_dir) {
        return !rule.negated
      }
      r -= 1
    }
    k -= 1
  }
  false
}

///|
fn match_rule(rule : Rule, rel : String, is_dir : Bool) -> Bool {
  if rule.anchored {
    return glob_match_path(rule.pattern, rel, rule.dir_only, is_dir)
  }
  // Unanchored: try every contiguous window of path segments, so the
  // rule "target" matches "target", "a/target" and "target/cargo.exe"
  // (ancestor directories count), and "docs/*.md" matches "docs/x.md".
  window_match(rule.pattern, rel, rule.dir_only, is_dir)
}

///|
/// Try glob-matching the pattern against every contiguous window of
/// segments of `path` (window size equals the number of pattern segments,
/// or fewer when the pattern contains "**").
fn window_match(
  pattern : String,
  path : String,
  dir_only : Bool,
  is_dir : Bool,
) -> Bool {
  let psegs = split_seg(pattern)
  let ssegs = split_seg(path)
  let pn = psegs.length()
  let sn = ssegs.length()
  // If the pattern has no "**", the window size is exactly pn.
  let mut has_dstar = false
  for seg in psegs {
    if seg == "**" {
      has_dstar = true
      break
    }
  }
  let mut i = 0
  while i <= sn {
    if has_dstar {
      // "**" can span segments: try every suffix start.
      let sub = join_segs(ssegs, i, sn)
      if glob_match_path(pattern, sub, dir_only, is_dir) {
        return true
      }
    } else if i + pn <= sn {
      let sub = join_segs(ssegs, i, i + pn)
      if glob_match_path(pattern, sub, dir_only, is_dir) {
        return true
      }
    }
    i += 1
  }
  false
}

///|
fn join_segs(segs : Array[String], lo : Int32, hi : Int32) -> String {
  let buf = StringBuilder()
  let mut i = lo
  while i < hi {
    if i > lo {
      buf.write_char('/')
    }
    buf.write_string(segs[i])
    i += 1
  }
  buf.to_string()
}

///|
/// Full-path glob match with `**` support (pattern may span directories).
fn glob_match_path(
  pattern : String,
  path : String,
  dir_only : Bool,
  is_dir : Bool,
) -> Bool {
  // A dir-only rule (trailing "/") only matches directories;
  // files inside are pruned when the directory itself is ignored.
  if dir_only && !is_dir {
    return false
  }
  let psegs = split_seg(pattern)
  let ssegs = split_seg(path)
  match_seg_list(psegs, ssegs, 0, 0)
}

///|
fn split_seg(s : String) -> Array[String] {
  let out : Array[String] = []
  let n = s.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if s.at(i).to_int() == 0x2F {
      if i > start {
        out.push(s[start:i].to_owned())
      }
      i += 1
      start = i
    } else {
      i += 1
    }
  }
  if n > start {
    out.push(s[start:n].to_owned())
  }
  out
}

///|
/// Match segment lists with `**` semantics.
fn match_seg_list(
  p : Array[String],
  s : Array[String],
  pi : Int32,
  si : Int32,
) -> Bool {
  if pi == p.length() {
    return si == s.length()
  }
  if p[pi] == "**" {
    // "**" matches zero or more segments.
    let mut k = si
    while k <= s.length() {
      if match_seg_list(p, s, pi + 1, k) {
        return true
      }
      k += 1
    }
    return false
  }
  if si == s.length() {
    return false
  }
  if glob_match_seg(p[pi], s[si]) {
    return match_seg_list(p, s, pi + 1, si + 1)
  }
  false
}

///|
/// Single-segment glob: '*' (any run, no '/'), '?' (one char),
/// '[...]' character class.
fn glob_match_seg(pat : String, name : String) -> Bool {
  let m = pat.length()
  let n = name.length()
  fn helper(pi : Int32, ni : Int32) -> Bool {
    if pi == m {
      return ni == n
    }
    let pc = pat.at(pi).to_int()
    if pc == 0x2A {
      // '*': zero or more chars, never crossing '/'
      if helper(pi + 1, ni) {
        return true
      }
      let mut k = ni
      while k < n && name.at(k).to_int() != 0x2F {
        k += 1
        if helper(pi + 1, k) {
          return true
        }
      }
      return false
    }
    if ni >= n {
      return false
    }
    let nc = name.at(ni).to_int()
    if pc == 0x3F {
      return helper(pi + 1, ni + 1)
    }
    if pc == 0x5B {
      // [...]
      let mut j = pi + 1
      let mut negate = false
      if j < m && (pat.at(j).to_int() == 0x21 || pat.at(j).to_int() == 0x5E) {
        negate = true
        j += 1
      }
      let mut matched = false
      let mut first = true
      while j < m && (first || pat.at(j).to_int() != 0x5D) {
        first = false
        if j + 2 < m &&
          pat.at(j + 1).to_int() == 0x2D &&
          pat.at(j + 2).to_int() != 0x5D {
          if nc >= pat.at(j).to_int() && nc <= pat.at(j + 2).to_int() {
            matched = true
          }
          j += 3
        } else {
          if pat.at(j).to_int() == nc {
            matched = true
          }
          j += 1
        }
      }
      if j < m {
        j += 1 // skip ']'
      }
      if matched != negate {
        return helper(j, ni + 1)
      }
      return false
    }
    if pc == 0x5C && pi + 1 < m {
      // escaped char
      if name.at(ni).to_int() == pat.at(pi + 1).to_int() {
        return helper(pi + 2, ni + 1)
      }
      return false
    }
    if pc == nc {
      return helper(pi + 1, ni + 1)
    }
    false
  }

  helper(0, 0)
}

///|
fn split_lines(src : String) -> Array[String] {
  let out : Array[String] = []
  let n = src.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if src.at(i).to_int() == 0x0A {
      let mut end = i
      if end > start && src.at(end - 1).to_int() == 0x0D {
        end -= 1
      }
      out.push(src[start:end].to_owned())
      i += 1
      start = i
    } else {
      i += 1
    }
  }
  if start < n {
    let mut end = n
    if end > start && src.at(end - 1).to_int() == 0x0D {
      end -= 1
    }
    out.push(src[start:end].to_owned())
  }
  out
}

///|
/// Match a simple CLI exclude glob against a relative path:
/// - if the pattern contains '/', it is matched against the full path
/// - otherwise it matches any path segment (like gitignore unanchored)
pub fn exclude_match(pattern : String, rel_path : String) -> Bool {
  if contains_str(pattern, "/") {
    // Anchor at the root, but also accept a prefix window so that
    // "--exclude src/gen" ignores "src/gen/x.py".
    if glob_match_path(pattern, rel_path, false, false) {
      return true
    }
    if contains_str(pattern, "**") {
      return window_match(pattern, rel_path, false, false)
    }
    let psegs = split_seg(pattern)
    let ssegs = split_seg(rel_path)
    let pn = psegs.length()
    let sn = ssegs.length()
    let mut i = 0
    while i + pn <= sn {
      let sub = join_segs(ssegs, 0, i + pn)
      if glob_match_path(pattern, sub, false, false) {
        return true
      }
      i += 1
    }
    false
  } else {
    // Unanchored: match any single segment window.
    window_match(pattern, rel_path, false, false)
  }
}
