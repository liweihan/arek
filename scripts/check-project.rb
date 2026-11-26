# Checks, without Xcode (Linux or a Mac), that the two ways AREK is installed build the same thing and that a newer
# iOS SDK cannot break its switches over iOS's statuses.
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

if failures.empty?
  puts 'project: every check passed'
else
  puts "project: #{failures.size} check(s) failed"
  exit 1
end
