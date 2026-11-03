# frozen_string_literal: true

require "pathname"

module RailsVis
  class Repo
    GITHUB = %r{\A(?:git@github\.com:|https://github\.com/)([^/\s]+)/([^/\s]+?)(?:\.git)?/?\z}

    attr_reader :root, :owner, :repo, :sha, :warnings

    def self.detect(root, repo_url: nil)
      new(root, repo_url)
    end

    def initialize(root, repo_url)
      @warnings = []
      given = Pathname.new(root.to_s)
      top = git(given, "rev-parse", "--show-toplevel")
      @root = top ? Pathname.new(top) : given
      if top
        @sha = git(@root, "rev-parse", "HEAD")
        @dirty = !git(@root, "status", "--porcelain").to_s.empty?
        @warnings << "working tree is dirty; source links point at the last commit, not your edits" if @dirty
        @owner, @repo = parse(repo_url || git(@root, "remote", "get-url", "origin"))
        @warnings << "no GitHub origin found; source links disabled" unless @owner
      else
        @warnings << "not a git repository; source links disabled"
      end
    end

    def dirty? = @dirty || false

    def url_base
      "https://github.com/#{owner}/#{repo}/blob/#{sha}" if owner && sha
    end

    def relative(path)
      p = Pathname.new(path.to_s)
      return p.cleanpath.to_s unless p.absolute?
      rel = p.relative_path_from(root).to_s
      rel.start_with?("..") ? resolve(p).relative_path_from(root.realpath).to_s : rel
    end

    def url_for(path, line)
      return unless url_base
      rel = relative(path)
      "#{url_base}/#{rel}#L#{line}" unless rel.start_with?("..")
    end

    def to_h
      { "owner" => owner, "repo" => repo, "sha" => sha, "dirty" => dirty?, "url_base" => url_base }
    end

    private

    # realpath of the deepest existing ancestor, plus the non-existent remainder.
    def resolve(path)
      tail = []
      until path.exist?
        tail.unshift(path.basename)
        path = path.dirname
      end
      tail.reduce(path.realpath) { |acc, name| acc + name }
    end

    # Returns stripped stdout, or nil when git fails (no repo, no origin, no commits).
    def git(dir, *args)
      out = IO.popen(["git", "-C", dir.to_s, *args], err: File::NULL, &:read)
      $?.success? ? out.strip : nil
    rescue Errno::ENOENT
      nil
    end

    def parse(url)
      m = GITHUB.match(url.to_s)
      m ? [m[1], m[2]] : [nil, nil]
    end
  end
end
