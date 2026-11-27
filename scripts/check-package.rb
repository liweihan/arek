#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that Package.swift (SwiftPM) and arek.podspec (CocoaPods) split AREK the same way, and that the split holds.
#
#   ruby scripts/check-package.rb <package.json>
#
# <package.json> is the output of `swift package describe --type json`; scripts/check-package.sh makes it and runs this.
# Needs no Xcode and no CocoaPods: the podspec is evaluated with a stand-in for Pod::Spec.
#
# What it checks:
#   1. the iOS deployment target of Package.swift is the podspec's;
#   2. each subspec of the podspec is a product "Arek<Name>" with one target of the same name, which depends on
#      ArekCore alone, and "Core" is ArekCore, which depends on nothing;
#   3. each product's target compiles the files its subspec lists, no more and no fewer;
#   4. every .swift file of code/Classes is in exactly one target;
#   5. each target imports the iOS frameworks its subspec links, no more and no fewer (Foundation and UIKit are the
#      core's; they need no entry), so that an app that adds ArekCamera links no HealthKit: HealthKit is imported by
#      ArekHealth and by nothing else;
#   6. every permission file imports ArekCore where SwiftPM builds it as a module of its own
#      (`#if canImport(ArekCore)`), and every permission, as a module of its own, type-checks against ArekCore as an
#      app would see it: it uses nothing of the core that is not `public` or `open`. Needs swiftc: a UIKit stand-in
#      (scripts/package-check/UIKit.swift) lets ArekCore compile on Linux, and each iOS framework a permission imports
#      is an empty module, so only the errors about AREK's own names are the check's (the frameworks' are not).
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

def code_lines(file)
  File.readlines(File.join(ROOT, file), chomp: true).reject { |line| line.strip.start_with?('//') }
end

def imports_of(files)
  files.flat_map do |file|
    code_lines(file).filter_map do |line|
      line[/^\s*import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?([A-Za-z_]\w*)/, 1]
    end
  end.uniq.sort
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
compile = lambda do |*args|
  output, status = Open3.capture2e(*swiftc, '-swift-version', '5', *args)
  [output.lines.grep(%r{^\S+:\d+:\d+: error: }), status.success?]
end
Dir.mktmpdir('arek-package-check') do |dir|
  stub = File.join(ROOT, 'scripts/package-check/UIKit.swift')
  _, ok = compile.call('-parse-as-library', '-emit-module', '-module-name', 'UIKit', stub, '-emit-module-path', "#{dir}/UIKit.swiftmodule")
  fail_with.call('scripts/package-check/UIKit.swift does not compile') unless ok

  core_files = files_of_target.fetch('ArekCore').map { |file| File.join(ROOT, file) }
  core_errors, = compile.call('-parse-as-library', '-emit-module', '-module-name', 'ArekCore', '-I', dir, *core_files,
                              '-emit-module-path', "#{dir}/ArekCore.swiftmodule")
  core_errors.each { |line| fail_with.call("ArekCore does not compile against the UIKit stand-in: #{line.strip.sub(ROOT + '/', '')}") }
  next unless core_errors.empty? # without the core module, every permission would fail for that one reason

  permission_files = files_of_target.reject { |name, _| name == 'ArekCore' }
  frameworks = imports_of(permission_files.values.flatten) - IMPLICIT_MODULES
  empty = File.join(dir, 'Empty.swift')
  File.write(empty, '')
  frameworks.each do |framework|
    compile.call('-parse-as-library', '-emit-module', '-module-name', framework, empty, '-emit-module-path', "#{dir}/#{framework}.swiftmodule")
  end

  permission_files.each do |name, files|
    errors_of_target, = compile.call('-typecheck', '-I', dir, '-module-name', name, *files.map { |file| File.join(ROOT, file) })
    errors_of_target.each do |line|
      next unless line.sub(/^\S+:\d+:\d+: error: /, '').match?(AREK_ERROR)

      fail_with.call("target #{name} as a module of its own: #{line.strip.sub(ROOT + '/', '')}")
    end
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
