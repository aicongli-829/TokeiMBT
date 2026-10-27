///|
/// White-box tests for the gitignore engine.

///|
test "glob: star matches within segment" {
  assert_eq(glob_match_seg("*.log", "temp.log"), true)
  assert_eq(glob_match_seg("*.log", "a/temp.log"), false) // star does not cross /
  assert_eq(glob_match_seg("build", "build"), true)
  assert_eq(glob_match_seg("b?ild", "build"), true)
  assert_eq(glob_match_seg("b[a-c]ld", "bdld"), false)
  assert_eq(glob_match_seg("b[a-c]ld", "bald"), true)
}

///|
test "path glob: double star crosses segments" {
  assert_eq(glob_match_path("**/build", "a/b/build", false, true), true)
  assert_eq(glob_match_path("a/**/c", "a/b/c", false, false), true)
  assert_eq(glob_match_path("a/**/c", "a/c", false, false), true)
  assert_eq(glob_match_path("*.md", "docs/x.md", false, false), false)
}

///|
test "rule parsing: negation, dir-only, anchoring" {
  let r1 = parse_line("!keep.txt", "").unwrap()
  assert_eq(r1.negated, true)
  let r2 = parse_line("build/", "").unwrap()
  assert_eq(r2.dir_only, true)
  assert_eq(r2.pattern, "build")
  let r3 = parse_line("/root-only.txt", "").unwrap()
  assert_eq(r3.anchored, true)
  let r4 = parse_line("sub/x.txt", "").unwrap()
  assert_eq(r4.anchored, true) // contains slash
  let r5 = parse_line("# comment", "")
  match r5 {
    None => ()
    Some(_) => abort("expected None for comment line")
  }
}

///|
test "gitignore preserves escaped trailing spaces and trims ordinary ones" {
  let escaped = parse_line("report\\ ", "").unwrap()
  assert_eq(escaped.pattern, "report\\ ")
  assert_eq(glob_match_seg(escaped.pattern, "report "), true)
  assert_eq(glob_match_seg(escaped.pattern, "report"), false)
  let ordinary = parse_line("report  ", "").unwrap()
  assert_eq(ordinary.pattern, "report")
  let directory = parse_line("build/  ", "").unwrap()
  assert_eq(directory.pattern, "build")
  assert_eq(directory.dir_only, true)
  let doubled = parse_line("report\\\\ ", "").unwrap()
  assert_eq(doubled.pattern, "report\\\\")
}

///|
test "gitignore matches escaped leading punctuation literally" {
  let stack = IgnoreStack::new()
  stack.push_file("", "\\#draft.rs\n\\!important.rs\n")
  assert_eq(stack.is_ignored("#draft.rs", false), true)
  assert_eq(stack.is_ignored("!important.rs", false), true)
}

///|
test "ignore stack: gitignore semantics end to end" {
  let stack = IgnoreStack::new()
  stack.push_file("", "target\n*.log\n!important.log\n")
  assert_eq(stack.is_ignored("target/cargo.exe", false), true)
  assert_eq(stack.is_ignored("a.log", false), true)
  assert_eq(stack.is_ignored("important.log", false), false) // negation wins
  assert_eq(stack.is_ignored("src/main.rs", false), false)
  stack.push_file("docs", "*.tmp\n")
  assert_eq(stack.is_ignored("docs/x.tmp", false), true)
  assert_eq(stack.is_ignored("other/x.tmp", false), false) // scoped to docs
}

///|
test "exclude match for CLI globs" {
  assert_eq(exclude_match("*.log", "x/y.log"), true)
  assert_eq(exclude_match("node_modules", "a/node_modules"), true)
  assert_eq(exclude_match("src/gen", "src/gen/x.py"), true)
  assert_eq(exclude_match("src/gen", "other/gen/x.py"), false)
}
