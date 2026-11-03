# frozen_string_literal: true

require "net/http"
require "uri"

module RailsVis
  # Fetches a sample of the links in data.json and reports non-200s. Only rails_vis:check_links uses it;
  # the dump never touches the network.
  class CheckLinks
    PREFIXES = { "github" => "https://github.com/", "api" => "https://api.rubyonrails.org/", "guides" => "https://guides.rubyonrails.org/" }.freeze

    FETCH = lambda do |url|
      uri = URI(url)
      4.times do # the first request plus up to 3 redirects
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 10) do |http|
          http.get(uri.request_uri, "User-Agent" => "rails_vis")
        end
        return response.code.to_i unless response.is_a?(Net::HTTPRedirection) && response["location"]
        uri = URI.join(uri, response["location"])
      end
      302
    end

    def initialize(data, sample: 10, fetch: FETCH, io: $stdout)
      @data = data
      @sample = sample
      @fetch = fetch
      @io = io
    end

    def call
      @results = urls.group_by { |url| kind(url) }.flat_map do |kind, list|
        list.first(@sample).map do |url|
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
