# frozen_string_literal: true

require "test_helper"

class DocLinksTest < Minitest::Test
  D = RailsVis::DocLinks

  def test_api_url
    assert_equal "https://api.rubyonrails.org/v#{Rails.version}/classes/ActiveRecord/Associations/ClassMethods.html#method-i-has_many",
                 D.api("ActiveRecord::Associations::ClassMethods", :has_many)
  end

  def test_api_class_method
    assert D.api("ActiveRecord::Base", :find_by, kind: :class).end_with?("#method-c-find_by")
  end

  def test_guide_url
    assert_equal "https://guides.rubyonrails.org/v#{Rails.version.split('.')[0, 2].join('.')}/routing.html", D.guide("routing")
    assert D.guide("routing", anchor: "x").end_with?("routing.html#x")
  end

  def test_fixed_mappings
    assert D.association(:belongs_to).end_with?("ActiveRecord/Associations/ClassMethods.html#method-i-belongs_to")
    assert D.validation(:presence).end_with?("#method-i-validates_presence_of")
    assert D.controller_filter(:before).end_with?("AbstractController/Callbacks/ClassMethods.html#method-i-before_action")
    assert D.model_callback.end_with?("/active_record_callbacks.html")
    assert D.routing.end_with?("/routing.html")
    assert D.multiple_databases.end_with?("/active_record_multiple_databases.html")
  end

  def test_validation_uniqueness_is_active_record
    assert_includes D.validation(:uniqueness), "ActiveRecord/Validations/ClassMethods.html#method-i-validates_uniqueness_of"
  end

  def test_gem_links_for_rails
    links = D.gem("rails")
    assert_equal "https://rubygems.org/gems/rails/versions/#{Rails.version}", links[:rubygems]
    assert_equal "https://rubydoc.info/gems/rails/#{Rails.version}", links[:rubydoc]
    refute_nil links[:homepage]
  end

  def test_gem_links_unknown
    assert_equal({ homepage: nil, documentation_uri: nil, source_code_uri: nil, changelog_uri: nil,
                   rubygems: "https://rubygems.org/gems/nope", rubydoc: "https://rubydoc.info/gems/nope" },
                 D.gem("nope"))
  end
end
