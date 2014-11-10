#
# Requires the following gems:
#   - erubis
#   - sinatra
#

require 'digest/md5'

require 'rubygems'
require 'erubis'
require 'sinatra'

class CacheTest < Sinatra::Base
  # Configure Sinatra
  set :views, Proc.new { File.join(root, "/../views") }
  use Rack::CommonLogger
  # Extension to content-type map.
  CONTENT_TYPES = {
    'css'  => 'text/css',
    'html' => 'text/html',
    'js'   => 'application/javascript',
  }

  # Maximum component size to test in bytes.
  SIZE_MAX = 4194304

  # Minimum component size to test in bytes.
  SIZE_MIN = 1024

  get '/' do
    # Generate a new unique session id.
    @id = stamp

    # Set initial cookie values.
    ['css', 'js'].each do |type|
      response.set_cookie("cache_#{type}_delta",     :value => (SIZE_MIN + SIZE_MAX) / 2, :path => '/')
      response.set_cookie("cache_#{type}_iteration", :value => 0,        :path => '/')
      response.set_cookie("cache_#{type}_max",       :value => 0,        :path => '/')
      response.set_cookie("cache_#{type}_size",      :value => (SIZE_MIN + SIZE_MAX) / 2, :path => '/')
      response.set_cookie("cache_#{type}_status",    :value => 'new',    :path => '/')
    end

    # Render the index page.
    erb :index
  end

  get '/a/:type/:step/:id' do |type, step, id|
    get_cookies

    @type = type.to_sym

    adjust_delta(@type)

    @id          = id
    @next_url    = "/b/#{@type}/#{step}/#{@id}"
    @request_css = @type == :css && @cookies[:css][:delta] != 0
    @request_js  = @type == :js && @cookies[:js][:delta] != 0
    @size_max    = SIZE_MAX

    response['Content-Type']  = 'text/html;charset=utf-8'
    response['Cache-Control'] = 'no-store;max-age=0;must-revalidate'
    response['Expires']       = 'Fri, 01 Apr 2010 01:00:00 GMT'

    erb :a
  end

  get '/b/:type/:step/:id' do |type, step, id|
    get_cookies

    @type = type.to_sym

    @id          = id
    @manual      = step == 'manual'
    @next_url    = "/a/#{@type}/#{step}/#{@id}"
    @request_css = @type == :css && @cookies[:css][:delta] != 0
    @request_js  = @type == :js && @cookies[:js][:delta] != 0
    @size_max    = SIZE_MAX

    response['Content-Type']  = 'text/html;charset=utf-8'
    response['Cache-Control'] = 'no-store;max-age=0;must-revalidate'
    response['Expires']       = 'Fri, 01 Apr 2010 01:00:00 GMT'

    erb :b
  end

  # url format: /random/<id>/<bytes>[.<extension>]
  get %r{^/random/([0-9a-f]+)/(\d+)(?:\.([a-z]+))?$} do |id, length, ext|
    length = length.to_i

    # Limit length to >=64b and <=20MB.
    if length < 64 || length > 20971520
      halt 400, 'Length must be at least 64 and not more than 20971520.'
    end

    # Use the appropriate content-type for the specified file extension, or
    # fall back to text/plain if none match.
    type = CONTENT_TYPES[ext] || 'text/plain'

    # if length > 1128005
    #   # sanity check
    #   response['Cache-Control'] = 'no-store;max-age=0;must-revalidate'
    #   response['Expires']       = 'Fri, 01 Apr 2010 01:00:00 GMT'
    # else
      response['Content-Type'] = "#{type};charset=utf-8"
      response['Cache-Control'] = 'max-age=315360000'
      response['Expires']       = 'Fri, 01 May 2020 03:47:24 GMT'
    # end

    # Set a timing cookie so the client knows this was not a cached response.
    # Note that the format of the timestamp here (which differs from the format
    # generated in JS) doesn't actually matter; all that matters is that it's
    # different from the previous cookie value.
    response.set_cookie("cache_#{ext}_time", :value => Time.now.to_f.to_s, :path => '/')

    # Wrap the response appropriately to ensure it's valid for the requested
    # content-type.
    case type
    when 'application/javascript'
      "/*#{random_alpha(length - 4)}*/"

    when 'text/css'
      "/*#{random_alpha(length - 4)}*/"

    when 'text/html'
      "<!DOCTYPE html><html><body>#{random_alpha(length - 42)}</body></html>"

    else # text/plain
      random_alpha(length)
    end
  end

  helpers do
    def adjust_delta(type)
      values = @cookies[type]

      response.set_cookie("cache_#{type}_iteration", :value => values[:iteration] += 1, :path => '/')

      unless values[:delta] == 0 || values[:status] == 'new'

        if values[:status] == 'miss'
          # Cache miss: over the max size. Adjust downward.
          values[:delta] = [(values[:size] - values[:max]) / 2, SIZE_MIN].max
          values[:size] -= values[:delta]
          values[:max]   = values[:size] if values[:size] < values[:max] # account for adaptive cache limits

        else
          # Cache hit: under the max size.
          values[:max] = values[:size] if values[:size] > values[:max]

          if values[:delta] == SIZE_MIN || values[:size] >= SIZE_MAX
            # We either found the max size or hit the test ceiling, so stop.
            values[:delta] = 0

          else
            # Adjust upward.
            values[:delta] = [(values[:delta] * 1.5).to_i, SIZE_MAX].min
            values[:size]  = [values[:size] + values[:delta], SIZE_MAX].min
          end

        end

        response.set_cookie("cache_#{type}_delta", :value => values[:delta], :path => '/')
        response.set_cookie("cache_#{type}_max",   :value => values[:max],   :path => '/')
        response.set_cookie("cache_#{type}_size",  :value => values[:size],  :path => '/')
      end
    end

    def format_size(bytes)
      bytes >= 1024 ? "#{bytes / 1024}KB" : bytes.to_s
    end

    def get_cookies
      # Cookies:
      #   - cache_<type>_delta: Delta between the previous size and the current size. Delta of 0 halts further testing.
      #   - cache_<type>_iteration: Current test iteration.
      #   - cache_<type>_max: Maximum size that has resulted in a cache hit so far.
      #   - cache_<type>_size: Most recent size tested.
      #   - cache_<type>_status: 'hit' if the last test was a cache hit, 'miss' if it was a miss.

      @cookies = {
        :css => {
          :delta     => request.cookies['cache_css_delta'].to_i,
          :iteration => request.cookies['cache_css_iteration'].to_i,
          :max       => request.cookies['cache_css_max'].to_i,
          :size      => request.cookies['cache_css_size'].to_i,
          :status    => request.cookies['cache_css_status']
        },

        :js => {
          :delta     => request.cookies['cache_js_delta'].to_i,
          :iteration => request.cookies['cache_js_iteration'].to_i,
          :max       => request.cookies['cache_js_max'].to_i,
          :size      => request.cookies['cache_js_size'].to_i,
          :status    => request.cookies['cache_js_status']
        }
      }
    end

    # Returns the specified number of pseudorandom alphanumeric and whitespace
    # characters.
    def random_alpha(length)
      length = length.to_i
      result = ''

      # Using MD5 here since it's much faster than randomizing each individual
      # character, and it's still random enough for our purposes even though it
      # only gives us a limited range of alphanumeric characters.
      while result.length < length do
        result << Digest::MD5.hexdigest(Kernel.rand.to_s) << "\n"
      end

      result[0, length]
    end

    # Returns a unique hash generated from the current time (with microseconds)
    # concatenated with a random value.
    def stamp
      Digest::MD5.hexdigest(Time.now.to_f.to_s + Kernel.rand.to_s)
    end
  end

end
