# frozen_string_literal: true

module RailsVis
  # Pure string building; never touches the network.
  module DocLinks
    API_BASE = "https://api.rubyonrails.org"
    GUIDES_BASE = "https://guides.rubyonrails.org"

    module_function

    def api(module_path, method, kind: :instance)
      prefix = kind == :class ? "method-c-" : "method-i-"
      "#{API_BASE}/v#{Rails.version}/classes/#{module_path.gsub('::', '/')}.html##{prefix}#{method}"
    end

    def guide(name, anchor: nil)
      url = "#{GUIDES_BASE}/v#{Rails.version.split('.')[0, 2].join('.')}/#{name}.html"
      anchor ? "#{url}##{anchor}" : url
    end

    def association(macro)
      api("ActiveRecord::Associations::ClassMethods", macro)
    end

    ACTIVE_RECORD_VALIDATIONS = %w[uniqueness associated].freeze

    def validation(kind)
      mod = ACTIVE_RECORD_VALIDATIONS.include?(kind.to_s) ? "ActiveRecord::Validations::ClassMethods" : "ActiveModel::Validations::HelperMethods"
      api(mod, "validates_#{kind}_of")
    end

    def model_callback
      guide("active_record_callbacks")
    end

    def controller_filter(kind)
      api("AbstractController::Callbacks::ClassMethods", "#{kind}_action")
    end

    def routing
      guide("routing")
    end

    def multiple_databases
      guide("active_record_multiple_databases")
    end

    def rails_on_rack
      guide("rails_on_rack")
    end

    def gem(name)
      spec = Gem.loaded_specs[name]
      version = spec&.version&.to_s
      meta = spec&.metadata || {}
      {
        homepage: spec&.homepage,
        documentation_uri: meta["documentation_uri"],
        source_code_uri: meta["source_code_uri"],
        changelog_uri: meta["changelog_uri"],
        rubygems: ["https://rubygems.org/gems/#{name}", version && "versions/#{version}"].compact.join("/"),
        rubydoc: ["https://rubydoc.info/gems/#{name}", version].compact.join("/")
      }
    end
  end
end
