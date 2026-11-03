# frozen_string_literal: true

require "test_helper"

# The gem documents itself in its own convention; this keeps those documents loadable by the collector.
class SelfDocsTest < Minitest::Test
  GEM_ROOT = Pathname(__dir__).join("..").expand_path

  def result
    @result ||= begin
      previous = RailsVis.root
      RailsVis.root = GEM_ROOT
      RailsVis::Collectors::Documents.new(config: RailsVis::Config.load(GEM_ROOT), repo: RailsVis::Repo.detect(GEM_ROOT)).call
    ensure
      RailsVis.root = previous
    end
  end

  def doc(path) = result["documents"].find { |d| d["path"] == "docs/#{path}" }

  def test_start_here_order
    assert_equal [1, 2, 3], %w[overview.md architecture.md runbooks/local-setup.md].map { |p| doc(p)["order"] }
  end

  def test_decisions_are_decisions
    docs = result["documents"].select { |d| d["path"].start_with?("docs/decisions/") }
    assert_equal 4, docs.size
    assert(docs.all? { |d| d["kind"] == "decision" })
  end

  def test_architecture_has_mermaid
    assert_equal true, doc("architecture.md")["has_mermaid"]
  end

  def test_no_warnings
    assert_equal [], result["warnings"]
  end
end
