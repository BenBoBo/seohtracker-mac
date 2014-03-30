import supernake, parseutils, xmlparser, streams, xmltree

const
  build_dir = "build"
  doc_build_dir = build_dir/"html"
  gfx_build_dir = build_dir/"graphics"
  resource_dir = "resources"
  icons_dir = resource_dir/"icons"
  mac_html_config = resource_dir/"html"/"mac.cfg"
  credits_html_config = resource_dir/"html"/"credits.cfg"
  info_plist = "Info.plist"
  help_contents_dir = "Contents"
  help_resources_dir = help_contents_dir/"Resources"
  help_generic_cfg = "default.cfg"
  help_caches = "Library"/"Caches"/"com.apple.help*"
  help_include = build_dir/"help_defines.h"
  changelog_define = "EMBEDDED_CHANGELOG_VERSION"

let
  rst_build_files = glob_rst(resource_dir/"html")
  normal_rst_files = concat(glob_rst("."), glob_rst("docs"),
    glob_rst(resource_dir/"html"))
  help_insert_files = concat(mapIt(["appstore_changes", "full_changes"],
    string, resource_dir/"html"/(it & ".rst")), @["LICENSE.rst"])
  # Use correct path concat, wait for https://github.com/Araq/Nimrod/issues/871.
  changelog_version: In_out = ("resources/html/appstore_changes.rst",
    "build/nimcache/appstore_changes.h", nil)


proc icon_needs_refresh(dest, src_dir: string): bool =
  ## Wrapper around the normal needs_refresh expanding the src directory.
  result = dest.needs_refresh(to_seq(walk_files(src_dir/"icon*png")))


proc find_first_version_header(node: PRstNode): float =
  ## Returns greater than zero if a header node with version was found.
  if node.kind == rnHeadline:
    var headline = ""
    for son in node.sons:
      if (not son.isNil) and (not son.text.isNil):
        headline.add(son.text)

    if headline.len > 0 and headline[0] == 'v':
      # Looks like the proper headline, parse it!
      if parseFloat(headline, result, start = 1) > 0:
        return
      else:
        result = 0

  # Keep traversing the hierarchy.
  for son in node.sons:
    if not son.isNil():
      result = find_first_version_header(son)
      if result > 0: return


proc generate_version_constant(target: In_out) =
  ## Scans the src rst file and generates an output C header with a version.
  ##
  ## The version is extracted as the first "vDDD" value from section titles.
  let text = target.src.readFile
  var
    hasToc = false
    ast = rstParse(text, target.src, 0, 0, hasToc, {})
  let
    version_float = ast.find_first_version_header
    version_str = version_float.formatFloat(ffDecimal, precision = 1)

  target.dest.writeFile(format("""#ifndef $1_H
#define $1_H

#define $1 ($2f)
#define $1_STR @"$2"

#endif // $1_H
""", changelog_define, version_str))
  echo "Updated ", target.dest, " with ", changelog_define, " ", version_str


iterator all_rst_files(): In_out =
  ## Iterates over all the rst files.
  ##
  ## Returns In_out tuples, since different rst files have special output
  ## directory rules, it's not as easy as changing just the extension.
  var x: In_out

  for rst_path in rst_build_files:
    let filename = rst_path.extract_filename
    x.src = rst_path
    # Special case for the Credits file, put it one level up.
    if filename == "Credits.rst":
      x.dest = doc_build_dir/".."/filename.changeFileExt("html")
      x.options = credits_html_config
    else:
      x.dest = doc_build_dir/filename.changeFileExt("html")
      x.options = mac_html_config
    yield x
    # Now generate another normal version where path is not changed.
    x.dest = rst_path.changeFileExt("html")
    x.options = nil
    yield x

  for plain_rst in normal_rst_files:
    x.src = plain_rst
    x.dest = plain_rst.changeFileExt("html")
    x.options = nil
    yield x


proc build_all_rst_files(): seq[In_out] =
  ## Wraps iterator to avoid https://github.com/Araq/Nimrod/issues/866.
  ##
  ## The wrapping forces `for` loops to use a single variable and an extra
  ## `let` line to unpack the tuple.
  result = to_seq(all_rst_files())


iterator walk_dirs(dir: string): string =
  ## Similar to walkDirRec but returns directory paths, not file paths.
  ##
  ## Also, the returned paths are relative to `dir`.
  var stack = @[dir]
  while stack.len > 0:
    for k,p in walkDir(stack.pop()):
      case k
      of pcFile, pcLinkToFile: discard
      of pcDir, pcLinkToDir:
        yield p[1 + dir.len .. <p.len]
        stack.add(p)


iterator walk_iconset_dirs(): In_out =
  ## Wrapper over walk_dirs to get only .iconset source directories.
  ##
  ## Returns tuples in the form (src:dir.iconset, dest:file.icns).
  var x: In_out
  for path in walk_dirs(icons_dir):
    if not (path.split_file.ext == ".iconset"): continue
    x.src = icons_dir/path
    x.dest = gfx_build_dir/path.changeFileExt("icns")
    yield x


proc build_iconset_dirs(): seq[In_out] =
  ## Wrapper to avoid iterator limitations.
  result = to_seq(walk_iconset_dirs())


iterator walk_help_dir_contents(dir: string): tuple[src, rel_path: string] =
  ## This is a wrapper over walk_dirs to add special files to all help dirs.
  ##
  ## The proc will process the files as usual, then insert the brief and full
  ## change logs into the returned list. The proc returns two elements, the
  ## first is the absolute path to the source file. The second element is a
  ## concatenation of the input `dir` parameter with the *relative* path to
  ## src. This is required due to the inserted files being from directories
  ## other than `dir`, which breaks normal path composing.
  let offset = 1 + dir.len
  assert offset > 1
  var x: tuple[src, rel_path: string]
  for src in dir.walk_dir_rec:
    x.src = src
    x.rel_path = src[offset .. <src.len]
    yield x

  # Now insert the changes logs.
  for path in help_insert_files:
    x.src = path
    x.rel_path = path.extract_filename
    yield x


iterator find_help_directories(): string =
  ## Returns valid help paths for further processing.
  ##
  ## A valid path is a directory ending in '.help' and containing an XML
  ## info.plist file.
  for path in resource_dir.walk_dirs:
    if not (path.split_file.ext == ".help"): continue
    let info_path = resource_dir/path/info_plist
    discard info_path.load_xml
    yield resource_dir/path


proc process_help_rst(src, dest_dir, base_dir: string): bool =
  ## Processes `src` and generates an html file in `dest_dir`.
  ##
  ## Returns true if a file was generated/updated, false otherwise. For the
  ## options the proc will look for a .cfg file in the same directory as the
  ## input src. Failing that, repeats changing the name to help_generic_cfg.
  ## Failing that too, looks for the default configuration file in base_dir
  ## (which can be a completely different path from src).
  dest_dir.create_dir
  var rst: In_out
  rst.dest = changeFileExt(dest_dir / src.extract_filename, "html")
  rst.src = src
  # Find out if this file uses some sort of configuration file, global or local.
  let specific_cfg = src.changeFileExt("cfg")
  if specific_cfg.exists_file:
    rst.options = specific_cfg
  else:
    let generic_cfg = src.split_file.dir/help_generic_cfg
    if generic_cfg.exists_file:
      rst.options = generic_cfg
    else:
      let base_cfg = base_dir/help_generic_cfg
      if base_cfg.exists_file:
        rst.options = base_cfg

  if not rst.needs_refresh:
    return
  rst2html(rst)
  result = true


proc trash_apple_help_cache_directories() =
  ## Removes all directories with pattern help_caches.
  ##
  ## See http://stackoverflow.com/a/13547810/172690, looks like the OS only
  ## ackhowledges new versions if the previous ones are uninstalled or you
  ## remove the caches. So we remove the caches here.
  for path in walk_files(get_home_dir()/help_caches): path.remove_dir


proc anchor_encode(s: string): string =
  ## Like cgi.URL_encode but spaces are also encoded in hex.
  result = newStringOfCap(s.len + s.len shr 2) # assume 12% non-alnum-chars
  for i in 0..s.len-1:
    case s[i]
    of 'a'..'z', 'A'..'Z', '0'..'9', '_', '/', ':': add(result, s[i])
    else:
      add(result, '%')
      add(result, toHex(ord(s[i]), 2))


proc build_define(key, value: string): string =
  ## Returns a C #define for the key/value, mangling them.
  let value = value.change_file_ext("").anchor_encode
  result = "#define help_anchor_" & value & " @\"" & key.anchor_encode & "\"\n"


proc generate_include_from_help_search_index(input: string): string =
  var s = newStringStream(input)
  finally: s.close
  let
    xml = s.parse_xml
    root_dict = xml[0]

  result = """#ifndef __HELP_SEARCH_DEFINES__
#define __HELP_SEARCH_DEFINES__
"""
  var key, value = ""
  for i in items(root_dict):
    case i.tag
    of "key": key = i.innerText
    of "array":
      assert i[0].tag == "string"
      value = i[0].innerText
      if value[0] == '/': value = value[1..high(value)]

      result.add(build_define(key, value))
    else: discard

  result.add("""#endif""")


task "doc", "Generates documentation in HTML and applehelp formats":
  doc_build_dir.create_dir
  # Generate html files from the rst docs.
  for f in build_all_rst_files():
    if f.needs_refresh:
      rst2html(f)
      doc_build_dir.update_timestamp

  # Generate Apple .help directories.
  for help_dir in find_help_directories():
    let basename = help_dir.extract_filename
    var
      dest = build_dir/basename/help_contents_dir/info_plist
      src = help_dir/info_plist
      did_change = false
    dest.split_file.dir.create_dir
    if dest.needs_refresh(src) or help_include.needs_refresh(src):
      src.copyFileWithPermissions(dest)
      did_change = true

    # Now copy/process the resources.
    let r_dir = build_dir/basename/help_resources_dir
    for file_tuple in to_seq(help_dir.walk_help_dir_contents):
      let
        (src, rel_path) = file_tuple
        (src_dir, src_name, src_ext) = src.split_file
      # Ignore emtpy filenames or unix hidden files.
      if src_name.len < 1 or src_name[0] == '.': continue

      # Build destination directory.
      let
        dest_file = r_dir/rel_path
        dest_dir = dest_file.split_file.dir

      # Process extension and handle appropriately.
      case src_ext.to_lower
      of ".cfg", ".plist":
        ## Config files are not copied to the help bundle.
        discard
      of ".rst":
        if process_help_rst(src, dest_dir, help_dir):
          did_change = true
      else:
        # Normal file, just copy.
        if dest_file.needs_refresh(src):
          dest_dir.create_dir
          src.copyFileWithPermissions(dest_file)
          echo src, " -> ", dest_file
          did_change = true

    # Refresh the index search and base directory for Xcode to update files.
    if did_change:
      let
        index_dir = build_dir/basename/help_resources_dir
        out_index = index_dir/"search.helpindex"
      if not shell("hiutil -C -a -f", out_index, index_dir):
        quit("Could not run Apple's hiutil help indexing tool!")
      trash_apple_help_cache_directories()
      echo "Updated ", out_index

      # Generate C defines from the search terms to avoid broken links.
      let (xml, list_error) = execCmdEx("hiutil -D -f " & out_index)
      assert list_error == 0
      write_file(help_include, generate_include_from_help_search_index(xml))
      echo "Generated ", help_include

      update_timestamp(build_dir/basename)

  # Generate the version number header for embedded changelog docs.
  if changelog_version.needs_refresh:
    changelog_version.dest.split_path.head.create_dir
    generate_version_constant(changelog_version)

  echo "All docs generated"

task "check_doc", "Validates rst format for a subset of documentation":
  for f in build_all_rst_files():
    test_rst(f.src)

task "clean", "Removes temporal files, mainly":
  # Remove generated html files.
  for f in build_all_rst_files():
    if f.dest.exists_file:
      echo "Removing ", f.dest
      f.dest.remove_file

  # Remove generated iconset files.
  for iconset in build_iconset_dirs():
    if iconset.dest.exists_file:
      echo "Removing ", iconset.dest
      iconset.dest.remove_file

  # Remove generated help directories.
  for path in walk_dirs(build_dir):
    if not (path.split_file.ext == ".help"): continue
    let target = build_dir/path
    echo "Removing ", target
    target.remove_dir

  if help_include.exists_file:
    echo "Removing ", help_include
    help_include.remove_file

  echo "All clean"

task "icons", "Generates icons from the source png files":
  gfx_build_dir.create_dir
  for iconset in build_iconset_dirs():
    let dir = iconset.dest.split_file.dir
    dir.create_dir
    if not iconset.dest.icon_needs_refresh(iconset.src): continue
    if not shell("iconutil --convert icns --output", iconset.dest, iconset.src):
      quit("Error generating icon from " & iconset.src)
    else:
      echo iconset.src, " -> ", iconset.dest
  echo "All icons generated"
