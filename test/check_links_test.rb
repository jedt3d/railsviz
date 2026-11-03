# frozen_string_literal: true
require "test_helper"
require "stringio"
require "rake"

class CheckLinksTest < Minitest::Test
  DATA = {
    "routes" => [{ "source" => { "url" => "https://github.com/acme/app/blob/abc/config/routes.rb#L3" }, "doc_url" => "https://guides.rubyonrails.org/v8.1/routing.html" }],
    "models" => [{ "associations" => [{ "doc_url" => "https://api.rubyonrails.org/v8.1.3/classes/ActiveRecord/Associations/ClassMethods.html#method-i-has_many" }] },
                 { "associations" => [{ "doc_url" => "https://api.rubyonrails.org/v8.1.3/classes/ActiveRecord/Associations/ClassMethods.html#method-i-belongs_to" }] }],
    "databases" => [{ "links" => { "rubygems" => "https://rubygems.org/gems/solid_queue/versions/1.0.0", "broken" => "https://example.com/broken" } }],
    "documents" => [{ "body" => "see https://example.com/in-markdown-only" }]
  }.freeze

  def run_check(sample: 10, fetch: ->(url) { url.include?("broken") ? 404 : 200 })
    io = StringIO.new
    checker = RailsVis::CheckLinks.new(DATA, sample: sample, fetch: fetch, io: io)
    [checker.call, checker, io.string]
  end

  def test_kinds_and_statuses
    results, checker, out = run_check
    assert_equal %w[api gem gem github guides], results.map { |r| r["kind"] }.sort
    assert_equal [{ "kind" => "gem", "url" => "https://example.com/broken", "status" => 404 }], checker.failures
    assert_includes out, "FAIL gem https://example.com/broken (404)"
    assert_includes out, "ok   github https://github.com/acme/app/blob/abc/config/routes.rb#L3"
    assert_includes out, "5 checked, 1 failed"
    refute results.any? { |r| r["url"].include?("in-markdown-only") }
  end

  def test_fetch_gets_url_without_fragment_and_sample_limits_per_kind
    seen = []
    results, = run_check(sample: 1, fetch: ->(url) { seen << url; 200 })
    assert_equal 4, results.size
    assert seen.none? { |u| u.include?("#") }, seen.inspect
    assert_includes seen, "https://github.com/acme/app/blob/abc/config/routes.rb"
  end

  def follow(url, responses)
    calls = []
    code = RailsVis::CheckLinks.follow(url, ->(u) { calls << u; responses.shift })
    [code, calls]
  end

  def test_follow_three_redirects_then_ok
    code, calls = follow("https://a.test/x", [[301, "/y"], [302, "https://b.test/z"], [307, "w"], [200, nil]])
    assert_equal 200, code
    assert_equal %w[https://a.test/x https://a.test/y https://b.test/z https://b.test/w], calls
  end

  def test_follow_stops_after_three_redirects_with_last_code
    code, calls = follow("https://a.test/x", [[302, "/1"], [302, "/2"], [302, "/3"], [301, "/4"]])
    assert_equal 301, code
    assert_equal 4, calls.size
  end

  def test_fetch_error_counts_as_failure
    results, checker, = run_check(fetch: ->(_) { raise Errno::ECONNREFUSED })
    assert results.all? { |r| r["status"] == 0 }
    assert_equal results.size, checker.failures.size
  end

  def test_rake_task_defined
    Rails.application.load_tasks unless Rake::Task.task_defined?("rails_vis:check_links")
    assert Rake::Task.task_defined?("rails_vis:check_links")
  end
end
