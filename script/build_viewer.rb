# frozen_string_literal: true

# Builds viewer/index.html from viewer/src and viewer/vendor: one file, everything inline.
# Usage: ruby script/build_viewer.rb

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

page = read("viewer/src/index.html")
abort "viewer/src/index.html: #{TOKEN} must appear exactly once" unless page.scan(TOKEN).size == 1
%w[<!--BUILD:STYLE--> <!--BUILD:SCRIPTS-->].each { |m| abort "viewer/src/index.html: missing #{m}" unless page.include?(m) }

css = read("viewer/src/app.css")
abort "app.css: contains </style" if css.match?(%r{</style}i)

scripts = %w[viewer/vendor/marked.min.js viewer/vendor/mermaid.min.js viewer/src/app.js].map { script(_1) }.join("\n")

out = page
  .sub("<!--BUILD:STYLE-->") { "<style>\n#{css.chomp}\n</style>" }
  .sub("<!--BUILD:SCRIPTS-->") { scripts }

File.binwrite(File.join(ROOT, "viewer/index.html"), out)
puts "wrote viewer/index.html (#{out.bytesize} bytes)"
