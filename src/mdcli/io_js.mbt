///|
/// The file and process layer for js.
///
/// The js backend emits CommonJS and runs under Node, so Node's own file
/// system and process modules are the layer: `fs` for the files, and
/// `child_process` for the browser. Node has synchronous calls for both,
/// which is what this contract asks for.
///
/// The one thing that needs care is the size of the output that comes back:
/// the browser's DOM is megabytes, and Node refuses to buffer more than a
/// megabyte by default. The limit is raised here rather than left to
/// Node's default, because the default would fail exactly where the tool
/// needs to work.

///|
extern "js" fn js_exists(path : String) -> Bool =
  #| function(path) {
  #|   try {
  #|     return require("fs").existsSync(path);
  #|   } catch (e) {
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn js_first_existing(
  paths : FixedArray[String],
) -> FixedArray[String] =
  #| function(paths) {
  #|   try {
  #|     const fs = require("fs");
  #|     for (const p of paths) {
  #|       if (fs.existsSync(p)) { return [p]; }
  #|     }
  #|   } catch (e) {
  #|     // no path was found
  #|   }
  #|   return [];
  #| }

///|
extern "js" fn js_read_text(path : String) -> FixedArray[String] =
  #| function(path) {
  #|   try {
  #|     return [require("fs").readFileSync(path, "utf8")];
  #|   } catch (e) {
  #|     return [];
  #|   }
  #| }

///|
extern "js" fn js_write_text(path : String, content : String) -> Bool =
  #| function(path, content) {
  #|   try {
  #|     require("fs").writeFileSync(path, content, "utf8");
  #|     return true;
  #|   } catch (e) {
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn js_remove(path : String) -> Bool =
  #| function(path) {
  #|   try {
  #|     require("fs").unlinkSync(path);
  #|     return true;
  #|   } catch (e) {
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn js_file_size(path : String) -> Int32 =
  #| function(path) {
  #|   try {
  #|     return require("fs").statSync(path).size;
  #|   } catch (e) {
  #|     return -1;
  #|   }
  #| }

///|
extern "js" fn js_run(
  program : String,
  args : FixedArray[String],
) -> FixedArray[String] =
  #| function(program, args) {
  #|   try {
  #|     const r = require("child_process").spawnSync(program, Array.from(args), {
  #|       encoding: "utf8",
  #|       maxBuffer: 512 * 1024 * 1024,
  #|     });
  #|     if (r.error) {
  #|       return ["-1", "", String(r.error.message)];
  #|     }
  #|     const code = (r.status === null || r.status === undefined) ? -1 : r.status;
  #|     return [String(code), r.stdout || "", r.stderr || ""];
  #|   } catch (e) {
  #|     return ["-1", "", String(e.message)];
  #|   }
  #| }

///|
/// The array as the fixed array the js interface takes.
///
/// There is no conversion between the two in the standard library, so the
/// copy is made here.
fn to_fixed(a : Array[String]) -> FixedArray[String] {
  FixedArray::makei(a.length(), fn(i) { a[i] })
}

///|
/// Whether a path is there.
fn io_exists(path : String) -> Bool {
  js_exists(path)
}

///|
/// The first path of the list that is there, or None when none of them is.
fn io_first_existing(paths : Array[String]) -> String? {
  let found = js_first_existing(to_fixed(paths))
  if found.length() == 0 {
    None
  } else {
    Some(found[0])
  }
}

///|
/// The content of a file, or None when it cannot be read.
fn io_read_text(path : String) -> String? {
  let got = js_read_text(path)
  if got.length() == 0 {
    None
  } else {
    Some(got[0])
  }
}

///|
/// Write a file, and say whether it was written.
fn io_write_text(path : String, content : String) -> Bool {
  js_write_text(path, content)
}

///|
/// Take a file away, and say whether it is gone afterwards.
fn io_remove(path : String) -> Bool {
  js_remove(path)
}

///|
/// The size of a file in bytes, or -1 when it cannot be told.
fn io_file_size(path : String) -> Int64 {
  js_file_size(path).to_int64()
}

///|
/// Run a program and wait for it, collecting what it said.
fn io_run(program : String, args : Array[String]) -> IoResult {
  let got = js_run(program, to_fixed(args))
  if got.length() < 3 {
    return { code: -1, out: "", err: "the program did not run", }
  }
  let code = @string.parse_int(got[0]) catch { _ => -1 }
  { code, out: got[1], err: got[2], }
}
