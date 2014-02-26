import nake, os, times, osproc, htmlparser, xmltree, strtabs, strutils,
  rester, sequtils, packages/docutils/rst, packages/docutils/rstast, posix,
  xmlparser

type
  In_out = tuple[src, dest, options: string]
    ## The tuple only contains file paths.

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

template glob_rst(basedir: string): expr =
  ## Shortcut to simplify getting lists of files.
  to_seq(walk_files(basedir/"*.rst"))

let
  rst_build_files = glob_rst(resource_dir/"html")
  normal_rst_files = concat(glob_rst("."), glob_rst("docs"),
    glob_rst(resource_dir/"html"))
  help_insert_files = concat(mapIt(["appstore_changes", "full_changes"],
    string, resource_dir/"html"/(it & ".rst")), @["LICENSE.rst"])

var
  CONFIGS = newStringTable(modeCaseInsensitive)
    ## Stores previously read configuration files.

proc update_timestamp(path: string) =
  discard utimes(path, nil)

proc load_config(path: string): string =
  ## Loads the config at path and returns it.
  ##
  ## Uses the CONFIGS variable to cache contents. Returns nil if path is nil.
  if path.isNil: return
  if CONFIGS.hasKey(path): return CONFIGS[path]
  CONFIGS[path] = path.readFile
  result = CONFIGS[path]

proc rst2html(src: string, out_path = ""): bool =
  ## Converts the filename `src` into `out_path` or src with extension changed.
  let output = safe_rst_file_to_html(src)
  if output.len > 0:
    let dest = if out_path.len > 0: out_path else: src.changeFileExt("html")
    dest.writeFile(output)
    result = true

proc change_rst_links_to_html(html_file: string) =
  ## Opens the file, iterates hrefs and changes them to .html if they are .rst.
  let html = loadHTML(html_file)
  var DID_CHANGE: bool

  for a in html.findAll("a"):
    let href = a.attrs["href"]
    if not href.isNil:
      let (dir, filename, ext) = splitFile(href)
      if cmpIgnoreCase(ext, ".rst") == 0:
        a.attrs["href"] = dir / filename & ".html"
        DID_CHANGE = true

  if DID_CHANGE:
    writeFile(html_file, $html)


proc needs_refresh(target: In_out): bool =
  ## Wrapper around the normal needs_refresh for In_out types.
  if target.options.isNil:
    result = target.dest.needs_refresh(target.src)
  else:
    result = target.dest.needs_refresh(target.src, target.options)


proc icon_needs_refresh(dest, src_dir: string): bool =
  ## Wrapper around the normal needs_refresh expanding the src directory.
  result = dest.needs_refresh(to_seq(walk_files(src_dir/"icon*png")))


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

  if not rst.needs_refresh: return
  discard change_rst_options(rst.options.load_config)
  if not rst2html(rst.src, rst.dest):
    quit("Could not generate html doc for " & rst.src)
  else:
    echo rst.src & " -> " & rst.dest
    result = true


task "doc", "Generates documentation in HTML and applehelp formats":
  doc_build_dir.create_dir
  # Generate html files from the rst docs.
  for f in build_all_rst_files():
    let (rst_file, html_file, options) = f
    if not f.needs_refresh: continue
    discard change_rst_options(options.load_config)
    if not rst2html(rst_file, html_file):
      quit("Could not generate html doc for " & rst_file)
    else:
      if options.isNil:
        change_rst_links_to_html(html_file)
      doc_build_dir.update_timestamp
      echo rst_file & " -> " & html_file

  # Generate Apple .help directories.
  for help_dir in find_help_directories():
    let basename = help_dir.extract_filename
    var
      dest = build_dir/basename/help_contents_dir/info_plist
      src = help_dir/info_plist
      did_change = false
    dest.split_file.dir.create_dir
    if dest.needs_refresh(src):
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
          src.copyFileWithPermissions(dest_file)
          echo src, " -> ", dest_file
          did_change = true

    # Refresh the base directory for Xcode to update files.
    if did_change: update_timestamp(build_dir/basename)

  echo "All docs generated"

task "check_doc", "Validates rst format for a subset of documentation":
  for f in build_all_rst_files():
    let rst_file = f.src
    echo "Testing ", rst_file
    let (output, exit) = execCmdEx("rst2html.py " & rst_file & " /dev/null")
    if output.len > 0 or exit != 0:
      echo "Failed python processing of " & rst_file
      echo output

task "clean", "Removes temporal files, mainly":
  for path in walkDirRec("."):
    let (dir, name, ext) = splitFile(path)
    if ext == ".html":
      echo "Removing ", path
      path.removeFile()

task "icons", "Generates icons from the source png files":
  gfx_build_dir.create_dir
  for path in walk_dirs(icons_dir):
    if not (path.split_file.ext == ".iconset"): continue
    let
      src = icons_dir/path
      dest = gfx_build_dir/path.changeFileExt("icns")
      dir = dest.split_file.dir
    dir.create_dir
    if not dest.icon_needs_refresh(src): continue
    if not shell("iconutil --convert icns --output", dest, src):
      quit("Error generating icon from " & src)
    else:
      echo src, " -> ", dest
  echo "All icons generated"
