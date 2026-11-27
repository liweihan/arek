# Checks, without Xcode (Linux or a Mac), that the two ways AREK is installed build the same thing, that a newer
# iOS SDK cannot break its switches over iOS's statuses and that no source calls the archiver methods iOS 12 deprecated.
# Carthage builds arek.xcodeproj, CocoaPods builds arek.podspec's globs of code/Classes. Until 2026-11 they had drifted:
# ArekPopupStyle.swift was in the pod and missing from the project (whose target could then not compile), the project
# said Swift 3.0 / iOS 9.0 and the podspec Swift 4.2 / iOS 10.0, and the shared scheme tested nothing.
#
#   ruby scripts/check-project.rb      (needs the xcodeproj gem: gem install --user-install xcodeproj)
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)
failures = []
check = lambda do |what, problems|
  if problems.empty?
    puts "ok    #{what}"
  else
    puts "FAIL  #{what}"
    problems.each { |p| puts "        #{p}" }
    failures << what
  end
end

project = Xcodeproj::Project.open('arek.xcodeproj')
target = ->(name) { project.targets.find { |t| t.name == name } }
sources = lambda do |t|
  t.source_build_phase.files_references.compact.map { |ref| ref.real_path.relative_path_from(Pathname(ROOT)).to_s }.sort
end
podspec = File.read('arek.podspec')
pod = ->(key) { podspec[/^\s*s\.#{Regexp.escape(key)}\s*=\s*'([^']+)'/, 1] }

arek = target.call('arek')
tests = target.call('arekTests')
check.call('targets arek and arekTests exist', [('no target arek' unless arek), ('no target arekTests' unless tests)].compact)
exit 1 unless arek

on_disk = Dir.glob('code/Classes/**/*.swift').sort
compiled = sources.call(arek)
check.call("the arek target compiles every Swift file of code/Classes (#{on_disk.size}), as the podspec does",
           (on_disk - compiled).map { |f| "not in the arek target: #{f}" } +
           (compiled - on_disk).map { |f| "in the arek target, not in code/Classes: #{f}" })

test_files = Dir.glob('arekTests/**/*.swift').sort
test_sources = tests ? sources.call(tests) : []
check.call("the arekTests target compiles every Swift file of arekTests (#{test_files.size})",
           (test_files - test_sources).map { |f| "not in the arekTests target: #{f}" } +
           (test_sources - test_files).map { |f| "in the arekTests target, not on disk: #{f}" } +
           (test_files.empty? ? ['arekTests holds no test file'] : []))

# Two resources of one name are two commands producing one file of the bundle: Xcode stops the build there ("Multiple
# commands produce …"). Until 2026-11 the arek target copied code/Assets/.gitkeep and code/Classes/.gitkeep.
duplicates = project.targets.select { |t| t.respond_to?(:resources_build_phase) }.flat_map do |t|
  t.resources_build_phase.files_references.compact.group_by { |ref| File.basename(ref.path.to_s) }
   .select { |_, refs| refs.size > 1 }
   .map { |name, refs| "#{t.name} copies #{refs.size} files to #{name}: #{refs.map { |r| r.real_path.relative_path_from(Pathname(ROOT)) }.join(', ')}" }
end
check.call('no two resources of a target are copied to one name', duplicates)

scheme_path = 'arek.xcodeproj/xcshareddata/xcschemes/arek.xcscheme'
testables = File.exist?(scheme_path) ? Xcodeproj::XCScheme.new(scheme_path).test_action.testables : []
tested = testables.reject(&:skipped?).flat_map { |t| t.buildable_references.map(&:target_name) }
check.call('the shared scheme arek tests arekTests', tested.include?('arekTests') ? [] : ["#{scheme_path} tests #{tested.inspect}"])

swift = pod.call('swift_version')
ios = pod.call('ios.deployment_target')
versions = lambda do |key, want|
  [project, arek, tests].compact.flat_map do |owner|
    owner.build_configurations.map do |c|
      got = c.build_settings[key]
      next if got.nil? && owner != project && key == 'IPHONEOS_DEPLOYMENT_TARGET' # inherits the project's
      next if got.nil? && owner == project && key == 'SWIFT_VERSION' # set on each target
      "#{owner.respond_to?(:name) ? owner.name : 'project'} #{c.name}: #{key} = #{got.inspect}" unless got == want
    end.compact
  end
end
check.call("the project's SWIFT_VERSION is the podspec's swift_version (#{swift})", swift ? versions.call('SWIFT_VERSION', swift) : ['the podspec names no swift_version'])
check.call("the project's IPHONEOS_DEPLOYMENT_TARGET is the podspec's (#{ios})", ios ? versions.call('IPHONEOS_DEPLOYMENT_TARGET', ios) : ['the podspec names no ios.deployment_target'])

# A switch over one of iOS's statuses (AVAuthorizationStatus, PHAuthorizationStatus, …) that names its cases and no
# default stops compiling when a later SDK adds a status. The iOS 14 to 18 SDKs added statuses to five of them (photos,
# notifications, the iCloud account, calendars, contacts), so AREK 4.0.2 does not compile with a current Xcode. With
# `@unknown default` (or `default`) a status added later is a warning, not an error. Every switch of
# code/Classes/Permissions is over a status of iOS (ArekMotion's, over AREK's own, has a default already).
top_level = lambda do |body|
  body = body.gsub(/\{[^{}]*\}/, '') while body.match?(/\{[^{}]*\}/)
  body
end
switches = Dir.glob('code/Classes/Permissions/**/*.swift').sort.flat_map do |file|
  text = File.read(file).gsub(%r{//[^\n]*}, '')
  found = []
  text.scan(/\bswitch\b[^{]*\{/) do
    start = Regexp.last_match.end(0)
    depth = 1
    i = start
    while depth.positive? && i < text.size
      depth += 1 if text[i] == '{'
      depth -= 1 if text[i] == '}'
      i += 1
    end
    found << [file, text[0...start].count("\n") + 1, top_level.call(text[start...(i - 1)])]
  end
  found
end
check.call("every switch over an iOS status in code/Classes/Permissions (#{switches.size}) has an @unknown default",
           switches.reject { |_, _, body| body.match?(/(^|\s)(@unknown\s+)?default\s*:/) }
                   .map { |file, line, _| "no default: #{file}:#{line}" })

# NSKeyedUnarchiver.unarchiveObject(with:) and NSKeyedArchiver.archivedData(withRootObject:) compile without a word below
# iOS 12 and, from iOS 12 on, with one warning each, which fails nothing: ArekMotion kept both until 2026-11 and they
# were the only warnings left in the framework. This reads the code of code/Classes (not its comments and strings, which
# name the old calls beside what replaced them), so a call that comes back turns the gate red. A Swift call may break its
# line anywhere between its tokens, so it reads the code as one text, not a line at a time.
deprecated_archiver = {
  /\bunarchiveObject\s*\(/ => 'NSKeyedUnarchiver.unarchivedObject(ofClass:from:)',
  /\barchiveRootObject\s*\(/ => 'NSKeyedArchiver.archivedData(withRootObject:requiringSecureCoding:)',
  /\bNSKeyedUnarchiver\s*\(\s*forReadingWith\s*:/ => 'NSKeyedUnarchiver(forReadingFrom:)',
  /\bNSKeyedArchiver\s*\(\s*\)/ => 'NSKeyedArchiver(requiringSecureCoding:)'
}

# The text of a Swift file with its comments (// and nested /* */) and string literals (" " and """ """) blanked out, the
# newlines kept: a position in the result is the same position, and line, in the file.
swift_code = lambda do |text|
  out = +''
  i = 0
  comment_depth = 0
  blank = ->(char) { char == "\n" ? "\n" : ' ' }
  while i < text.size
    two = text[i, 2]
    if comment_depth.positive?
      if two == '/*'
        comment_depth += 1
        out << '  '
        i += 2
      elsif two == '*/'
        comment_depth -= 1
        out << '  '
        i += 2
      else
        out << blank.call(text[i])
        i += 1
      end
    elsif two == '//'
      while i < text.size && text[i] != "\n"
        out << ' '
        i += 1
      end
    elsif two == '/*'
      comment_depth = 1
      out << '  '
      i += 2
    elsif text[i, 3] == '"""'
      out << '   '
      i += 3
      until i >= text.size || text[i, 3] == '"""'
        if text[i] == '\\'
          out << ' ' << blank.call(text[i + 1].to_s)
          i += 2
        else
          out << blank.call(text[i])
          i += 1
        end
      end
      out << '   '
      i += 3
    elsif text[i] == '"'
      out << ' '
      i += 1
      while i < text.size && text[i] != '"' && text[i] != "\n"
        if text[i] == '\\'
          out << ' ' << blank.call(text[i + 1].to_s)
          i += 2
        else
          out << ' '
          i += 1
        end
      end
      if text[i] == '"'
        out << ' '
        i += 1
      end
    else
      out << text[i]
      i += 1
    end
  end
  out
end

# Every call of the deprecated methods in the code of a Swift file: [line, what to use instead].
deprecated_archiver_calls = lambda do |text|
  code = swift_code.call(text)
  found = []
  deprecated_archiver.each do |pattern, use|
    code.scan(pattern) { found << [code[0...Regexp.last_match.begin(0)].count("\n") + 1, "use #{use}"] }
  end
  # archivedData(withRootObject:) alone is the deprecated one; the one that names requiringSecureCoding: is not. Its
  # arguments end at the parenthesis that closes the call.
  code.scan(/\barchivedData\s*\(\s*withRootObject\s*:/) do
    match = Regexp.last_match
    depth = 1
    i = match.end(0)
    while depth.positive? && i < code.size
      depth += 1 if code[i] == '('
      depth -= 1 if code[i] == ')'
      i += 1
    end
    next if code[match.end(0)...i].match?(/\brequiringSecureCoding\s*:/)

    found << [code[0...match.begin(0)].count("\n") + 1, 'add requiringSecureCoding: to archivedData(withRootObject:)']
  end
  found.sort
end

archiver_calls = on_disk.flat_map do |file|
  deprecated_archiver_calls.call(File.read(file)).map { |line, use| "#{file}:#{line}: #{use}" }
end
check.call("no source of code/Classes (#{on_disk.size}) calls an NSKeyedArchiver or NSKeyedUnarchiver method that iOS 12 deprecated", archiver_calls)

# The check above must see a deprecated call wherever Swift lets it break its line, and must not see one in a comment, a
# string, or a call that names requiringSecureCoding: on another line than archivedData(.
flagged = {
  'on one line' => 'let data = NSKeyedArchiver.archivedData(withRootObject: status.rawValue)',
  'a line break after archivedData(' => "let data = NSKeyedArchiver.archivedData(\n    withRootObject: status.rawValue\n)",
  'a line break before the (' => "NSKeyedUnarchiver.unarchiveObject\n    (with: data)",
  'a line break inside forReadingWith' => "let unarchiver = NSKeyedUnarchiver(\n    forReadingWith: data)",
  'archiveRootObject' => "NSKeyedArchiver.archiveRootObject(value,\n    toFile: path)",
  'an archiver made without secure coding' => 'let archiver = NSKeyedArchiver( )',
  'after a comment that names the secure call' => "/* requiringSecureCoding: */ NSKeyedArchiver.archivedData(withRootObject: x)"
}
allowed = {
  'requiringSecureCoding: on the next line' => "try NSKeyedArchiver.archivedData(withRootObject: x,\n    requiringSecureCoding: true)",
  'requiringSecureCoding: after a line break after archivedData(' => "try NSKeyedArchiver.archivedData(\n    withRootObject: x,\n    requiringSecureCoding: true\n)",
  'the replacement of unarchiveObject' => 'try NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: data)',
  'the replacement of the initialiser' => 'let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)',
  'names in comments' => "// NSKeyedUnarchiver.unarchiveObject(with:) was deprecated\n/* a /* nested */ archiveRootObject(x, toFile: f) */",
  'names in strings' => 'let note = "NSKeyedArchiver.archivedData(withRootObject: x), unarchiveObject(with: d) \" archiveRootObject("',
  'names in a multi-line string' => "let note = \"\"\"\n  unarchiveObject(with: d)\n  NSKeyedArchiver()\n  \"\"\""
}
check.call('the check for deprecated archiver calls sees them across line breaks and not in comments or strings',
           flagged.reject { |_, source| deprecated_archiver_calls.call(source).any? }.map { |what, _| "does not see: #{what}" } +
           allowed.select { |_, source| deprecated_archiver_calls.call(source).any? }.map { |what, _| "sees one in: #{what}" })

if failures.empty?
  puts 'project: every check passed'
else
  puts "project: #{failures.size} check(s) failed"
  exit 1
end
