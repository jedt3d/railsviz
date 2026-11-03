# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class DocumentsCollectorTest < Minitest::Test
  def repo = @repo ||= RailsVis::Repo.detect(RailsVis.root)
  def config(**values) = RailsVis::Config.new(RailsVis::Config::DEFAULTS.merge(values.transform_keys(&:to_s)))
  def collect(cfg = config) = RailsVis::Collectors::Documents.new(config: cfg, repo: repo).call
  def result = @result ||= collect
  def doc(path, res = result) = res["documents"].find { |d| d["path"] == "test/dummy/docs/#{path}" }

  def test_front_matter_read
    overview = doc("overview.md")
    assert_equal "Dummy overview", overview["title"]
    assert_equal "overview", overview["kind"]
    assert_equal "all", overview["audience"]
    assert_equal 10, overview["order"]
    assert_equal 2, overview["related"].size
    assert_equal({ "name" => "app/models/patient.rb", "path" => "test/dummy/app/models/patient.rb", "line" => 1 },
                 overview["related"][0].slice("name", "path", "line"))
    assert_equal "PatientsController#show", overview["related"][1]["name"]
    assert_equal "test/dummy/app/controllers/patients_controller.rb", overview["related"][1]["path"]
    assert overview["body"].start_with?("# Overview\n")
    assert_equal false, overview["has_mermaid"]
  end

  def test_kind_inferred_decision
    decision = doc("decisions/0001-sqlite.md")
    assert_equal "decision", decision["kind"]
    assert_equal "ADR 0001: SQLite", decision["title"]
    assert_nil decision["order"]
    assert_equal [], decision["related"]
  end

  def test_kind_inferred_diagram
    er = doc("domain/er.md")
    assert_equal "diagram", er["kind"]
    assert_equal true, er["has_mermaid"]
  end

  def test_broken_front_matter_warns
    broken = doc("broken.md")
    assert_equal "broken", broken["title"]
    assert_equal File.read(RailsVis.root.join("docs/broken.md")), broken["body"]
    assert result["warnings"].any? { |w| w["where"] == "documents" && w["message"].include?("docs/broken.md") }
  end

  def test_start_here_from_config
    res = collect(config(start_here: ["docs/decisions/0001-sqlite.md"]))
    assert_equal 1, doc("decisions/0001-sqlite.md", res)["order"]
    assert_equal 10, doc("overview.md", res)["order"]
  end

  def test_unresolved_related_warns
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ghost.md"), "---\nrelated:\n  - Nope#x\n  - app/models/patient.rb\n---\n# Ghost\n")
      res = collect(config(docs: ["#{dir}/*.md"]))
      assert_equal ["app/models/patient.rb"], res["documents"].first["related"].map { |n| n["name"] }
      assert res["warnings"].any? { |w| w["message"].include?("ghost.md") && w["message"].include?("Nope#x") }
    end
  end

  # Writes { relative path => content } into a temp docs root and collects it.
  def collect_temp(files)
    Dir.mktmpdir do |dir|
      files.each do |rel, content|
        FileUtils.mkdir_p(File.dirname(File.join(dir, rel)))
        File.binwrite(File.join(dir, rel), content)
      end
      yield collect(config(docs: ["#{dir}/**/*.md"])), dir
    end
  end

  def test_dated_front_matter_loads
    collect_temp("dated.md" => "---\ntitle: Dated\ndate: 2026-11-03\n---\nBody\n") do |res, _|
      assert_equal "Dated", res["documents"].first["title"]
      assert_equal [], res["warnings"]
    end
  end

  def test_crlf_and_bom_front_matter
    collect_temp("crlf.md" => "﻿---\r\ntitle: CRLF\r\n---\r\nBody\r\n") do |res, _|
      crlf = res["documents"].first
      assert_equal "CRLF", crlf["title"]
      refute crlf["body"].start_with?("---")
      assert_equal "Body\r\n", crlf["body"]
    end
  end

  def test_kind_from_first_folder_below_root
    collect_temp("domain/sub/x.md" => "# X\n\n```mermaid\ngraph TD\n```\n", "top.md" => "# Top\n") do |res, _|
      assert_equal "diagram", res["documents"].find { |d| d["path"].end_with?("domain/sub/x.md") }["kind"]
      assert_equal "overview", res["documents"].find { |d| d["path"].end_with?("top.md") }["kind"]
    end
  end

  def test_exclude
    assert result["documents"].none? { |d| d["path"].include?("docs/superpowers/") }
    assert_equal 4, result["documents"].size
  end
end
