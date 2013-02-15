# Start logplex
#   $ bin/logplex
#
# Connect an erlang REPL to the running logplex server
#   $ bin/connect
#
# In the REPL, create a username and password for the REST API:
#   > InitialCred = logplex_cred:new().
#   > NamedCred = logplex_cred:rename(<<"pivotal">>, InitialCred).
#   > GrantedCred = logplex_cred:grant(full_api, NamedCred).
#
#   {cred,<<"ACFCB5EE9F307921F1B5BD62FB479F6A">>,
#      <<"CB59E4865E7B05C4A3A858346558F79A552BE39D98FC58F99F0297DD7F5BBBE1">>,
#      [full_api],
#      <<"pivotal">>}
#
# The two hex strings are the username and password.
# Store these credentials in redis:
#   > logplex_cred:store(GrantedCred).
#
# In ruby, create a logging channel and a token for writing to it:
#   > channel_id = Sys.create_channel("channel-name")
#   > Sys.create_token(channel_id, "token-name")
#
#   => "t.53304d4b-1aac-4b1e-b1fa-2f88dc486985"
#
# Post some logs:
#   > source = Source.new("t.53304d4b-1aac-4b1e-b1fa-2f88dc486985")
#   > source.post_logs([ "first log message", "second log message" ])
#
# Create a session for the channel and read from it::
#   > guid = Sys.create_session(13)
#   > Sys.get_session(guid)
#
#   => ""
#

require "pp"
require "typhoeus"
require "json"

USERNAME = "ACFCB5EE9F307921F1B5BD62FB479F6A"
PASSWORD = "CB59E4865E7B05C4A3A858346558F79A552BE39D98FC58F99F0297DD7F5BBBE1"
HOST = "192.168.196.128"
REST_PORT = 5000
LOG_PORT = 8601
VERBOSE = true

def request(method, path, options={})
  response = Typhoeus.send(method, "#{base_url}/#{path}", options.merge(:verbose => VERBOSE))
  puts "Request Body:", options[:body], "\n" if options[:body] && VERBOSE
  {
    :code => response.code,
    :headers => response.headers,
    :body => parse_if_json(response.body)
  }
end

def parse_if_json(string)
  JSON.parse(string) rescue string
end

module Sys
  class << self
    def healthcheck
      get("healthcheck")
    end

    def create_channel(channel_name)
      post_json("channels", {
        :name => channel_name,
        :app_id => "some-app-id",
        :addon => "basic"
      })[:body]["channel_id"]
    end

    def get_channel(id)
      get("channels/#{id}/info")
    end

    def create_token(channel_id, token_name)
      post_json("channels/#{channel_id}/token", {
        :name => token_name,
      })[:body]
    end

    # Optional keys:
    # - tail
    # - num
    # - source
    # - ps
    def create_session(channel_id, options={})
      match = post_json("sessions", options.merge(
        :channel_id => channel_id.to_s
      ))[:body].match(%r{/sessions/([^/]+)})
      match[1] if match
    end

    def get_session(session_guid)
      get("sessions/#{session_guid}?srv=1")
    end

    def get(path)
      request(:get, path)
    end

    def post_json(path, data)
      request(:post, path, :body => JSON.dump(data))
    end

    private

    def base_url
      "http://#{USERNAME}:#{PASSWORD}@#{HOST}:#{REST_PORT}"
    end
  end
end

class Source
  def initialize(token)
    @token = token
  end

  def post_logs(messages)
    logplex_messages = messages.map { |m| format_logplex_message(m) }
    request(:post, "logs",
      :body => logplex_messages.join(''),
      :headers => {
        "Content-Type" => "application/logplex-1",
        "Logplex-Msg-Count" => logplex_messages.length
      },
    )
  end

  private

  def base_url
    "http://token:#{@token}@#{HOST}:#{LOG_PORT}"
  end

  def format_logplex_message(message)
    header = "<134>1 2013-12-10T03:00:48Z+00:00 erlang #{@token} console.1 -"
    entry = "#{header} - #{message}"
    "#{entry.length} #{entry}"
  end
end

puts "health check:"
pp Sys.healthcheck
