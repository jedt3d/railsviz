# frozen_string_literal: true

# Builds viewer/index.html from viewer/src and viewer/vendor: one file, everything inline
# (stylesheets concatenated, the IBM Plex subsets embedded as data URIs, Marked, Mermaid and app.js inlined).
# Usage: ruby script/build_viewer.rb

require "base64"

ROOT = File.expand_path("..", __dir__)
TOKEN = "<!--RAILS_VIS_DATA-->"

def read(rel) = File.read(File.join(ROOT, rel), encoding: "UTF-8")

def script(rel)
  js = read(rel)
  # Inline JS must not close or open a script element, or the HTML parser splits it.
  abort "#{rel}: contains </script or <script" if js.match?(%r{</?script}i)
  abort "#{rel}: contains #{TOKEN}" if js.include?(TOKEN)
  "<script>\n#{js.chomp}\n</script>"
end

# viewer/vendor/fonts/fonts.css names each woff2 by file; the built page carries them as data URIs so it never fetches.
def fonts
  read("viewer/vendor/fonts/fonts.css").gsub(/url\(([^)]+\.woff2)\)/) do
    file = File.join(ROOT, "viewer/vendor/fonts", Regexp.last_match(1))
    "url(data:font/woff2;base64,#{Base64.strict_encode64(File.binread(file))})"
  end
end

page = read("viewer/src/index.html")
abort "viewer/src/index.html: #{TOKEN} must appear exactly once" unless page.scan(TOKEN).size == 1
%w[<!--BUILD:STYLE--> <!--BUILD:SCRIPTS-->].each { |m| abort "viewer/src/index.html: missing #{m}" unless page.include?(m) }

css = [fonts, read("viewer/src/tokens.css"), read("viewer/src/base.css"), read("viewer/src/app.css")].map(&:chomp).join("\n")
abort "css: contains </style" if css.match?(%r{</style}i)

scripts = %w[viewer/vendor/marked.min.js viewer/vendor/mermaid.min.js viewer/src/app.js].map { script(_1) }.join("\n")

out = page
  .sub("<!--BUILD:STYLE-->") { "<style>\n#{css}\n</style>" }
  .sub("<!--BUILD:SCRIPTS-->") { scripts }

File.binwrite(File.join(ROOT, "viewer/index.html"), out)
puts "wrote viewer/index.html (#{out.bytesize} bytes)"
