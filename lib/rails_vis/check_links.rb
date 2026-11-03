# frozen_string_literal: true

require "net/http"
require "uri"

module RailsVis
  # Fetches a sample of the links in data.json and reports non-200s. Only rails_vis:check_links uses it;
  # the dump never touches the network.
  class CheckLinks
    PREFIXES = { "github" => "https://github.com/", "api" => "https://api.rubyonrails.org/", "guides" => "https://guides.rubyonrails.org/" }.freeze

    # Follows up to 3 redirects. `get` is url -> [status code, Location or nil]. Returns the last response's status.
    def self.follow(url, get)
      uri = URI(url)
      code = nil
      4.times do # the first request plus up to 3 redirects
        code, location = get.call(uri.to_s)
        return code unless (300..399).cover?(code) && location
        uri = URI.join(uri, location)
      end
      code
    end

    HTTP_GET = lambda do |url|
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 10) do |http|
        http.get(uri.request_uri, "User-Agent" => "rails_vis")
      end
      [response.code.to_i, response["location"]]
    end

    FETCH = ->(url) { follow(url, HTTP_GET) }

    def initialize(data, sample: 10, fetch: FETCH, io: $stdout)
      @data = data
      @sample = sample
      @fetch = fetch
      @io = io
    end

    def call
      @results = urls.group_by { |url| kind(url) }.flat_map do |kind, list|
        list.uniq { |url| url.sub(/#.*/m, "") }.first(@sample).map do |url|
          status = begin
            @fetch.call(url.sub(/#.*/m, ""))
          rescue StandardError
            0
          end
          @io.puts(status == 200 ? "ok   #{kind} #{url}" : "FAIL #{kind} #{url} (#{status})")
          { "kind" => kind, "url" => url, "status" => status }
        end
      end
      @io.puts "#{@results.size} checked, #{failures.size} failed"
      @results
    end

    def failures = (@results || []).reject { |r| r["status"] == 200 }

    private

    def urls
      found = []
      walk = lambda do |node|
        case node
        # "body" holds a document's Markdown, whose URLs are prose, not generated links; skipped at any depth.
        when Hash then node.each { |key, value| walk.call(value) unless key == "body" }
        when Array then node.each { |value| walk.call(value) }
        when %r{\Ahttps?://} then found << node
        end
      end
      walk.call(@data)
      found.uniq.sort
    end

    def kind(url) = PREFIXES.find { |_, prefix| url.start_with?(prefix) }&.first || "gem"
  end
end
