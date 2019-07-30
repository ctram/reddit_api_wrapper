require "http"

REDDIT_ACCESS_TOKEN_URL = 'https://www.reddit.com/api/v1/access_token'
API_DOMAIN = 'https://oauth.reddit.com'

class RedditApiWrapper
  attr_reader :username, :password, :api_id, :api_key
  attr_accessor :token

  def initialize(**credentials)
    @username, @password, @api_id, @api_key = credentials.values_at :username, :password, :api_id, :api_key
    @cached_things = {}
  end

  def get_authorization_token
    res = HTTP.
      basic_auth(:user => api_id, :pass => api_key).
      post(
        REDDIT_ACCESS_TOKEN_URL,
        form: {
          grant_type: 'password',
          username: username,
          password: password
        }
      )

    JSON.parse(res.to_s)['access_token']
  end

  def refresh_token
    @token = get_authorization_token
  end

  def token
    @token ||= refresh_token
  end

  def get_saved_things(limit = 100, id_of_last_thing = '', count = 0)
    params = { limit: limit.to_s, after: id_of_last_thing, count: count }
    puts "params #{params.inspect}"

    response = HTTP.
      auth("Bearer #{token}").
      get(API_DOMAIN + "/user/#{username}/saved", params: params)

    data = JSON.parse(response.to_s)['data']
    id_of_last_thing = data['after']
    count_received = data['dist'].to_i

    things = data['children']

    things = things.reduce([]) do |acc, child|
      acc << child['data'].slice('url', 'name')
      acc
    end

    { things: things, id_of_last_thing: id_of_last_thing, count_received: count_received }
  end

  def get_all_saved_things
    all_things = []
    things, id_of_last_thing, count = get_saved_things.values_at :things, :id_of_last_thing, :count_received

    all_things += things

    num_calls = 1
    num_slow_downs = 0

    until things.empty?
      prev_num_cached_things = @cached_things.count
      things, id_of_last_thing, count_received = get_saved_things(100, id_of_last_thing, count).values_at :things, :id_of_last_thing, :count_received
      cache_things(things)

      # keep track if we're receiving too many duplicate things
      if @cached_things.count - prev_num_cached_things  < 5
        num_slow_downs += 1
      end

      break if num_slow_downs == 10

      num_calls += 1
      puts "num calls: #{num_calls} ; num total things: #{all_things.count}; num total unique things: #{@cached_things.count}; num_slow_downs: #{num_slow_downs}"

      count += count_received

      all_things += things
    end

    puts 'Finished fetching things.'

    @cached_things
  end

  def cache_things(things)
    num_dups = 0

    things.each do |thing|
      if @cached_things[thing['name']]
        num_dups += 1
        next
      end

      @cached_things[thing['name']] = thing['url']
    end

    puts "num dups #{num_dups}"
  end

  def get_and_save_all_urls_to_file(file_path)
    things = get_all_saved_things
    save_urls_to_file(file_path, things)
  end

  def save_urls_to_file(file_path, things)
    File.open(file_path, 'w') do |file|
      things.each do |name, url|
        file.write({ name: name, url: url }.to_json)
        file.write("\n")
      end
    end

    puts "things saved to file #{file_path}"
  end

  def save_thing(thing)
    HTTP.
      auth("Bearer #{token}").
      post(
        API_DOMAIN + '/api/save',
        form: {
          id: thing['name']
        }
      )
  end

  def save_things_from_file(file_path)
    results = {}
    counter = 1
    lines = File.open(file_path, 'r').readlines

    lines.each do |line|
      thing = JSON.parse(line)
      puts "saving #{thing['name']}, #{counter}/#{lines.count}"
      res = save_thing(thing)
      puts "saving response: #{res.status}"
      results[thing['name']] = { res: res.status }
      counter += 1
    end

    pp results

    results
  end
end
