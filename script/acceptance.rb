# frozen_string_literal: true

# Runs rails_vis:dump inside a real Rails app pinned in acceptance/targets.yml and writes
# tmp/acceptance/<target>.report.json. Standard library only.
# Usage: ruby script/acceptance.rb <target>   (exit 2 = skipped: wrong Ruby; RAILS_VIS_ACCEPTANCE_FORCE=1 overrides)

require "json"
require "yaml"
require "open3"
require "net/http"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
name = ARGV.fetch(0) { abort "usage: ruby script/acceptance.rb <target>" }
target = YAML.load_file(File.join(ROOT, "acceptance/targets.yml"))[name] or abort "unknown target: #{name}"

if target["ruby"] && target["ruby"] != RUBY_VERSION && ENV["RAILS_VIS_ACCEPTANCE_FORCE"] != "1"
  puts "skipped: #{name} requires Ruby #{target["ruby"]}, running #{RUBY_VERSION}"
  exit 2
end

clone = File.join(ROOT, "tmp/acceptance", name)
app = File.expand_path(target["app_dir"], clone)
env = (target["env"] || {}).transform_values(&:to_s)

# Prints the command, runs it outside our bundle, aborts with the step name on failure.
def sh(step, cmd, dir:, env: {})
  puts "[#{step}] (#{dir}) $ #{cmd}"
  run = -> { system(env, cmd, chdir: dir) }
  ok = defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.call
  abort "acceptance: step '#{step}' failed (#{cmd})" unless ok
end

head = (Open3.capture2("git", "-C", clone, "rev-parse", "HEAD").first.strip if File.directory?(File.join(clone, ".git")))
unless head == target["sha"]
  sh("clone", "git clone --filter=blob:none #{target["repo"]} #{clone}", dir: ROOT) unless head
  sh("checkout", "git checkout --quiet #{target["sha"]}", dir: clone)
end

gemfile = File.join(clone, "Gemfile")
lines = File.readlines(gemfile)
unless lines.any? { |l| l.match?(/^\s*gem ["']rails_vis["']/) }
  entry = %(  gem "rails_vis", path: "#{ROOT}"\n)
  at = lines.index { |l| l.match?(/^group\b.*:development\b.*\bdo\s*$/) }
  at ? lines.insert(at + 1, entry) : lines.push("\ngroup :development do\n", entry, "end\n")
  File.write(gemfile, lines.join)
  puts "[gemfile] added rails_vis to #{gemfile}"
end

sh("bundle install", "bundle install", dir: clone)
target["prepare"].each { |cmd| sh("prepare", cmd, dir: app, env: env) }
sh("dump", "bundle exec rake rails_vis:dump", dir: app, env: env)

data = JSON.parse(File.read(File.join(app, "doc/rails_vis/data.json")))

def get(url)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
    http.request(Net::HTTP::Get.new(uri.request_uri, "User-Agent" => "rails_vis-acceptance"))
  end
end

# A link is ok when the blob page answers 200 and the raw file at that SHA has `def <action>` on that line.
# Inherited actions repeat on every subclass; distinct URLs make ten real checks.
repo = data["meta"]["repo"]
actions = data["controllers"].flat_map { |c| c["actions"] }.map { |a| a["source"] }.compact
                             .select { |s| s["url"] }.uniq { |s| s["url"] }.first(10)
links = actions.map do |s|
  action = s["name"].split("#").last
  status = get(s["url"]).code.to_i
  raw = get("https://raw.githubusercontent.com/#{repo["owner"]}/#{repo["repo"]}/#{repo["sha"]}/#{s["path"]}")
  line = raw.code == "200" ? raw.body.lines[s["line"] - 1].to_s.strip : nil
  ok = status == 200 && line.to_s.match?(/\bdef #{Regexp.escape(action)}(?![\w?!=])/)
  puts "[link] #{ok ? "ok  " : "FAIL"} #{s["url"]} -> #{line.inspect}"
  { "url" => s["url"], "status" => status, "line" => line, "ok" => ok }
end

report = {
  "routes" => data["routes"].size,
  "models" => data["models"].size,
  "controllers" => data["controllers"].size,
  "documents" => data["documents"].size,
  "warnings" => data["warnings"],
  "links_checked" => links.size,
  "links_ok" => links.count { |l| l["ok"] },
  "links" => links
}
out = File.join(ROOT, "tmp/acceptance/#{name}.report.json")
File.write(out, JSON.pretty_generate(report))
puts "report: #{out}"
puts report.except("warnings", "links").merge("warnings" => data["warnings"].size).to_json
