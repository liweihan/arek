#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that Package.swift (SwiftPM) and arek.podspec (CocoaPods) split AREK the same way, and that the split holds.
#
#   ruby scripts/check-package.rb <package.json>
#
# <package.json> is the output of `swift package describe --type json`; scripts/check-package.sh makes it and runs this.
# Needs no Xcode and no CocoaPods: the podspec is evaluated with a stand-in for Pod::Spec. Needs Ruby 2.6 (the system
# Ruby of a Mac) or later: write nothing here that only 2.7 has (`filter_map`, `tally`, numbered block parameters).
#
# What it checks:
#   1. the iOS deployment target of Package.swift is the podspec's;
#   2. each subspec of the podspec is a product "Arek<Name>" with one target of the same name, which depends on
#      ArekCore alone, and "Core" is ArekCore, which depends on nothing; the podspec's root declares no files, no
#      frameworks and no dependencies (what the root holds is installed beside any subspec an app asks for, or
#      beside all of them for `pod 'arek'`: every file belongs to a subspec);
#   3. each product's target compiles the files its subspec lists, no more and no fewer;
#   4. every .swift file of code/Classes is in exactly one target;
#   5. each target imports the iOS frameworks its subspec links, no more and no fewer (Foundation and UIKit are the
#      core's; they need no entry), so that an app that adds ArekCamera links no HealthKit: HealthKit is imported by
#      ArekHealth and by nothing else;
#   6. every permission file imports ArekCore where SwiftPM builds it as a module of its own
#      (`#if canImport(ArekCore)`), and every permission, as a module of its own, type-checks against ArekCore as an
#      app would see it: it uses nothing of the core that is not `public` or `open`. Needs swiftc: a UIKit stand-in
#      (scripts/package-check/UIKit.swift) lets ArekCore compile on Linux, and each iOS framework a permission imports
#      is an empty module, so only the errors about AREK's own names are the check's (the frameworks' are not). A
#      swiftc that fails for the core, for a stand-in module, or without a diagnostic we can read, fails the check;
#   7. the source the podspec downloads (`s.source`: a tag or a commit) imports nothing the podspec does not link, and
#      every subspec's files are in it. At the tag 4.0.2 the core imported PMAlertController, which the podspec no
#      longer declares, so a `pod spec lint` of it could not compile. Read with git, so a checkout without that
#      revision (a shallow clone) says so and goes on.
#
# The compiler with the real iOS SDK has the last word: scripts/check-package-consumer.sh, on a Mac.

require 'json'
require 'open3'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
CLASSES = 'code/Classes'
# Modules every target may import without the podspec listing them (ArekCore is the target's own core).
IMPLICIT_MODULES = %w[Foundation UIKit ArekCore].freeze
# What a permission's compile errors may say about AREK's own names: a name that is not visible, or not public or open.
AREK_ERROR = /\bArek\w*|inaccessible|protection level|non-open|overrid|\bsuper\b/.freeze
# swiftc's own error: "<path>:<line>:<column>: error: " (the path may hold spaces) or a driver's "error: ".
DIAGNOSTIC = /\A(?:.+?:\d+:\d+: )?error: /.freeze
# What the root of the podspec may not declare: a subspec's files and frameworks are its own.
ROOT_ATTRIBUTES = %w[source_files public_header_files resources frameworks weak_frameworks libraries vendored_frameworks
                     vendored_libraries].freeze

# --- The podspec, evaluated with a stand-in for CocoaPods' Pod::Spec ---------------------------------------------

# Records what a podspec assigns (`s.name = ...`), its subspecs, and `s.ios.deployment_target`.
class SpecRecorder
  attr_reader :values, :subspecs, :dependencies

  def initialize
    @values = {}
    @subspecs = {}
    @dependencies = []
  end

  def subspec(name)
    recorder = SpecRecorder.new
    yield recorder
    @subspecs[name] = recorder
  end

  def dependency(*args)
    @dependencies << args.first
  end

  def ios
    PlatformRecorder.new(@values, 'ios')
  end

  def method_missing(name, *args)
    key = name.to_s
    return @values[key.chomp('=')] = (args.size > 1 ? args : args.first) if key.end_with?('=')

    @values[key]
  end

  def respond_to_missing?(*)
    true
  end
end

# `s.ios.deployment_target = '12.0'` is recorded as the value "ios.deployment_target".
class PlatformRecorder
  def initialize(values, platform)
    @values = values
    @platform = platform
  end

  def method_missing(name, *args)
    key = "#{@platform}.#{name.to_s.chomp('=')}"
    return @values[key] = args.first if name.to_s.end_with?('=')

    @values[key]
  end

  def respond_to_missing?(*)
    true
  end
end

module Pod
  class Spec
    def self.new
      recorder = SpecRecorder.new
      yield recorder
      recorder
    end
  end
end

def load_podspec(path)
  eval(File.read(path), TOPLEVEL_BINDING, path) # rubocop:disable Security/Eval -- the repository's own podspec
end

# --- The sources ---------------------------------------------------------------------------------------------------

def swift_files_of(patterns)
  Array(patterns).flat_map { |pattern| Dir.glob(pattern, base: ROOT) }.select { |file| file.end_with?('.swift') }.sort
end

def code_lines(text)
  text.lines.map(&:chomp).reject { |line| line.strip.start_with?('//') }
end

def imports_in(text)
  code_lines(text).map do |line|
    line[/^\s*import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?([A-Za-z_]\w*)/, 1]
  end.compact
end

def imports_of(files)
  files.flat_map { |file| imports_in(File.read(File.join(ROOT, file))) }.uniq.sort
end

# git of this checkout: [output, succeeded].
def git(*args)
  output, status = Open3.capture2e('git', '-C', ROOT, *args)
  [output, status.success?]
end

# --- The checks -------------------------------------------------------------------------------------------------------

errors = []
fail_with = ->(message) { errors << message }

package = JSON.parse(File.read(ARGV.fetch(0)))
podspec = load_podspec(File.join(ROOT, 'arek.podspec'))

targets = package.fetch('targets').to_h { |target| [target['name'], target] }
products = package.fetch('products').to_h { |product| [product['name'], product] }

# 1. The deployment target.
ios = package.fetch('platforms').find { |platform| platform['name'] == 'ios' }
pod_ios = podspec.values['ios.deployment_target']
fail_with.call("Package.swift supports iOS #{ios && ios['version']}, arek.podspec iOS #{pod_ios}") if ios.nil? || ios['version'].to_f != pod_ios.to_f

# 2. Subspec <-> product <-> target.
subspec_names = podspec.subspecs.keys
expected = subspec_names.to_h { |name| [name, "Arek#{name}"] }
(expected.values - products.keys).each { |name| fail_with.call("the podspec has a subspec for #{name}, Package.swift has no product of that name") }
(products.keys - expected.values).each { |name| fail_with.call("Package.swift has product #{name}, arek.podspec has no subspec for it") }
expected.each_value do |name|
  product = products[name]
  next unless product

  fail_with.call("product #{name} is #{product['targets'].inspect}, expected [#{name.inspect}]") if product['targets'] != [name]
  target = targets[name]
  fail_with.call("product #{name} has no target of that name") if target.nil?
  next if target.nil?

  want_deps = name == 'ArekCore' ? [] : ['ArekCore']
  got_deps = Array(target['target_dependencies'])
  fail_with.call("target #{name} depends on #{got_deps.inspect}, expected #{want_deps.inspect}") if got_deps.sort != want_deps
  fail_with.call("target #{name} is #{target['type']}, expected a library") if target['type'] != 'library'
end
ROOT_ATTRIBUTES.each do |key|
  fail_with.call("arek.podspec declares #{key} at its root: it belongs to a subspec, so that an install of one subspec compiles that one") unless podspec.values[key].nil?
end
fail_with.call("arek.podspec's root depends on #{podspec.dependencies.inspect}: a dependency belongs to the subspec that uses it") unless podspec.dependencies.empty?
fail_with.call('arek.podspec has no Core subspec') unless subspec_names.include?('Core')
fail_with.call("the permission subspecs must depend on arek/Core: #{podspec.subspecs.reject { |_, spec| spec.dependencies == ['arek/Core'] || spec.dependencies.empty? }.keys.inspect}") if subspec_names.any? { |name| name != 'Core' && podspec.subspecs[name].dependencies != ['arek/Core'] }

# 3 and 5. The files and the frameworks of each product.
files_of_target = {}
targets.each do |name, target|
  files_of_target[name] = Array(target['sources']).map { |source| File.join(target['path'], source) }.sort
end
subspec_names.each do |name|
  target_name = expected[name]
  next unless files_of_target.key?(target_name)

  spec = podspec.subspecs[name]
  spec_files = swift_files_of(spec.values['source_files'])
  target_files = files_of_target[target_name]
  (spec_files - target_files).each { |file| fail_with.call("#{file} is in subspec #{name} and not in target #{target_name}") }
  (target_files - spec_files).each { |file| fail_with.call("#{file} is in target #{target_name} and not in subspec #{name}") }

  imported = imports_of(target_files) - IMPLICIT_MODULES
  linked = Array(spec.values['frameworks']).sort
  (imported - linked).each { |framework| fail_with.call("target #{target_name} imports #{framework}, subspec #{name} does not list it in frameworks") }
  (linked - imported).each { |framework| fail_with.call("subspec #{name} lists #{framework} in frameworks, target #{target_name} does not import it") }
end

# HealthKit is the framework the App Store rejects an app for linking without using: only ArekHealth may import it.
targets.each do |name, target|
  next if name == 'ArekHealth'

  files = files_of_target[name]
  fail_with.call("target #{name} imports HealthKit: an app that adds only #{name} would link it") if imports_of(files).include?('HealthKit')
  fail_with.call("target #{name} has no sources") if files.empty? && target['type'] == 'library'
end

# 4. Every file is in exactly one target.
all_files = Dir.glob("#{CLASSES}/**/*.swift", base: ROOT).sort
owners = Hash.new { |hash, key| hash[key] = [] }
files_of_target.each { |name, files| files.each { |file| owners[file] << name } }
all_files.each do |file|
  fail_with.call("#{file} is in no target") if owners[file].empty?
  fail_with.call("#{file} is in #{owners[file].size} targets: #{owners[file].join(', ')}") if owners[file].size > 1
end
(owners.keys - all_files).each { |file| fail_with.call("target source #{file} does not exist") }

# 6. The import of ArekCore, and each permission against ArekCore as a module of its own.
core_import = /^#if canImport\(ArekCore\)\nimport ArekCore\n#endif$/
files_of_target.each do |name, files|
  next if name == 'ArekCore'

  files.each do |file|
    fail_with.call("#{file} (target #{name}) lacks `#if canImport(ArekCore)` + `import ArekCore`") unless File.read(File.join(ROOT, file)).match?(core_import)
  end
end

swiftc = ENV.fetch('AREK_SWIFTC', 'swiftc').split
# [the error lines of swiftc's output, whether swiftc succeeded, what it printed whole]
compile = lambda do |*args|
  output, status = Open3.capture2e(*swiftc, '-swift-version', '5', *args)
  [output.lines.grep(DIAGNOSTIC), status.success?, output]
end
# What a failed compile says: its error lines, else the last lines of what it printed (a crash, a missing compiler).
failure_lines = lambda do |errors, output|
  lines = errors.empty? ? output.lines.last(3) : errors
  lines = ['swiftc printed nothing'] if lines.empty?
  lines.map { |line| line.strip.sub("#{ROOT}/", '') }
end
Dir.mktmpdir('arek-package-check') do |dir|
  stub = File.join(ROOT, 'scripts/package-check/UIKit.swift')
  stub_errors, stub_ok, stub_output = compile.call('-parse-as-library', '-emit-module', '-module-name', 'UIKit', stub,
                                                   '-emit-module-path', "#{dir}/UIKit.swiftmodule")
  failure_lines.call(stub_errors, stub_output).each { |line| fail_with.call("scripts/package-check/UIKit.swift does not compile: #{line}") } unless stub_ok

  core_files = files_of_target.fetch('ArekCore').map { |file| File.join(ROOT, file) }
  core_errors, core_ok, core_output = compile.call('-parse-as-library', '-emit-module', '-module-name', 'ArekCore', '-I', dir,
                                                   *core_files, '-emit-module-path', "#{dir}/ArekCore.swiftmodule")
  failure_lines.call(core_errors, core_output).each { |line| fail_with.call("ArekCore does not compile against the UIKit stand-in: #{line}") } unless core_ok
  next unless core_ok && stub_ok # without the core module, every permission would fail for that one reason

  permission_files = files_of_target.reject { |name, _| name == 'ArekCore' }
  frameworks = imports_of(permission_files.values.flatten) - IMPLICIT_MODULES
  empty = File.join(dir, 'Empty.swift')
  File.write(empty, '')
  frameworks.each do |framework|
    framework_errors, framework_ok, framework_output = compile.call('-parse-as-library', '-emit-module', '-module-name', framework, empty,
                                                                    '-emit-module-path', "#{dir}/#{framework}.swiftmodule")
    failure_lines.call(framework_errors, framework_output).each { |line| fail_with.call("the empty stand-in module for #{framework} does not build: #{line}") } unless framework_ok
  end

  permission_files.each do |name, files|
    errors_of_target, target_ok, target_output = compile.call('-typecheck', '-I', dir, '-module-name', name, *files.map { |file| File.join(ROOT, file) })
    # The empty frameworks make a failure expected; a failure that says nothing of the kind is not.
    if !target_ok && errors_of_target.empty?
      failure_lines.call(errors_of_target, target_output).each { |line| fail_with.call("target #{name} as a module of its own: swiftc failed without an error line: #{line}") }
    end
    errors_of_target.each do |line|
      next unless line.sub(DIAGNOSTIC, '').match?(AREK_ERROR)

      fail_with.call("target #{name} as a module of its own: #{line.strip.sub("#{ROOT}/", '')}")
    end
  end
end

# 7. What `s.source` downloads is the code the podspec describes.
source = podspec.values['source']
revision = source.is_a?(Hash) ? (source[:commit] || source[:tag]) : nil
if revision.nil?
  fail_with.call('arek.podspec `source` names neither a :commit nor a :tag')
else
  listing, found = git('ls-tree', '-r', '--name-only', revision, '--', CLASSES)
  if found
    files_at_revision = listing.lines.map(&:strip)
    podspec.subspecs.each do |name, spec|
      Array(spec.values['source_files']).each do |pattern|
        next if files_at_revision.any? { |file| File.fnmatch(pattern, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) }

        fail_with.call("subspec #{name} lists #{pattern}, which matches nothing in #{revision[0, 12]}, the source arek.podspec downloads")
      end
    end
    linked = podspec.subspecs.values.flat_map { |spec| Array(spec.values['frameworks']) }
    imported = files_at_revision.select { |file| file.end_with?('.swift') }
                                .flat_map { |file| imports_in(git('show', "#{revision}:#{file}").first) }.uniq.sort
    (imported - IMPLICIT_MODULES - linked).each do |framework|
      fail_with.call("the source arek.podspec downloads (#{revision[0, 12]}) imports #{framework}, which no subspec links and the podspec does not depend on")
    end
  elsif git('rev-parse', '--is-shallow-repository').first.strip == 'false'
    fail_with.call("#{revision}, the source of arek.podspec, is not in this checkout, which has all its history: a mistyped commit, or a tag to fetch (`git fetch --tags`)")
  else
    warn "check-package: #{revision} (the source of arek.podspec) is not in this checkout, a shallow clone: what it downloads was not read"
  end
end

if errors.empty?
  permission_count = expected.size - 1
  puts "check-package: ok (ArekCore and #{permission_count} permission products; Package.swift and arek.podspec agree)"
else
  warn "check-package: #{errors.size} problem#{'s' unless errors.size == 1}:"
  errors.each { |message| warn "  - #{message}" }
  exit 1
end
