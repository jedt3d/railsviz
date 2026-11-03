# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class RepoTest < Minitest::Test
  def git(dir, *args)
    out = IO.popen(["git", "-C", dir.to_s, *args], err: File::NULL, &:read)
    raise "git #{args.join(' ')} failed" unless $?.success?
    out
  end

  def make_repo(dir, origin: nil)
    git(dir, "init", "-q")
    git(dir, "config", "user.email", "t@example.com")
    git(dir, "config", "user.name", "T")
    git(dir, "config", "commit.gpgsign", "false")
    FileUtils.mkdir_p("#{dir}/sub/dummy")
    File.write("#{dir}/a.txt", "one\n")
    git(dir, "add", "-A")
    git(dir, "commit", "-q", "-m", "init")
    git(dir, "remote", "add", "origin", origin) if origin
  end

  def test_github_ssh_origin
    Dir.mktmpdir do |dir|
      make_repo(dir, origin: "git@github.com:acme/app.git")
      r = RailsVis::Repo.detect(dir)
      assert_equal "acme", r.owner
      assert_equal "app", r.repo
      assert_match(/\A\h{40}\z/, r.sha)
      assert r.url_for("app/x.rb", 7).end_with?("/blob/#{r.sha}/app/x.rb#L7")
      assert_empty r.warnings
    end
  end

  def test_root_is_git_toplevel
    Dir.mktmpdir do |dir|
      make_repo(dir, origin: "git@github.com:acme/app.git")
      r = RailsVis::Repo.detect("#{dir}/sub/dummy")
      assert_equal File.realpath(dir), r.root.realpath.to_s
      assert_equal "sub/dummy/config/routes.rb", r.relative("#{r.root}/sub/dummy/config/routes.rb")
      assert_equal "https://github.com/acme/app/blob/#{r.sha}/sub/dummy/x.rb#L2",
                   r.url_for("#{r.root}/sub/dummy/x.rb", 2)
    end
  end

  def test_relative_resolves_symlinked_form_of_missing_file
    Dir.mktmpdir do |dir|
      make_repo(dir, origin: "git@github.com:acme/app.git")
      r = RailsVis::Repo.detect("#{dir}/sub/dummy")
      assert_equal "sub/dummy/config/routes.rb", r.relative("#{dir}/sub/dummy/config/routes.rb")
    end
  end

  def test_url_for_outside_root_is_nil
    Dir.mktmpdir do |dir|
      make_repo(dir, origin: "git@github.com:acme/app.git")
      assert_nil RailsVis::Repo.detect(dir).url_for("/etc/hosts", 1)
    end
  end

  def test_github_https_origin_with_dot_git
    Dir.mktmpdir do |dir|
      make_repo(dir, origin: "https://github.com/acme/app.git")
      r = RailsVis::Repo.detect(dir)
      assert_equal %w[acme app], [r.owner, r.repo]
      assert_equal "https://github.com/acme/app/blob/#{r.sha}", r.to_h["url_base"]
    end
  end

  def test_dirty_tree_warns
    Dir.mktmpdir do |dir|
      make_repo(dir, origin: "git@github.com:acme/app.git")
      File.write("#{dir}/a.txt", "two\n")
      r = RailsVis::Repo.detect(dir)
      assert r.dirty?
      assert(r.warnings.any? { |w| w.include?("dirty") })
    end
  end

  # The dump's own output does not make the tree dirty; any other untracked file does.
  def test_dump_output_not_dirty
    Dir.mktmpdir do |dir|
      make_repo(dir, origin: "git@github.com:acme/app.git")
      FileUtils.mkdir_p("#{dir}/doc/rails_vis")
      File.write("#{dir}/doc/rails_vis/data.json", "{}")
      refute RailsVis::Repo.detect(dir).dirty?
      File.write("#{dir}/stray.txt", "x")
      assert RailsVis::Repo.detect(dir).dirty?
    end
  end

  def test_no_git_repo
    Dir.mktmpdir do |dir|
      r = RailsVis::Repo.detect(dir)
      assert_nil r.url_for("a.rb", 1)
      assert_nil r.sha
      assert_equal 1, r.warnings.size
    end
  end

  def test_non_github_origin
    Dir.mktmpdir do |dir|
      make_repo(dir, origin: "https://gitlab.com/a/b.git")
      r = RailsVis::Repo.detect(dir)
      assert_nil r.url_for("a.txt", 1)
      refute_empty r.warnings
    end
  end

  def test_repo_url_override
    Dir.mktmpdir do |dir|
      make_repo(dir)
      r = RailsVis::Repo.detect(dir, repo_url: "https://github.com/acme/app")
      assert_equal "https://github.com/acme/app/blob/#{r.sha}/a.txt#L3", r.url_for("a.txt", 3)
    end
  end
end
