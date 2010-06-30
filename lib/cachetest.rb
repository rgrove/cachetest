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
  use Rack::CommonLogger
  use Rack::Deflater

  # set :public, 'public'

  # Extension to content-type map.
  CONTENT_TYPES = {
    'css'  => 'text/css',
    'html' => 'text/html',
    'js'   => 'application/javascript',
  }

  # Maximum adjustment size in bytes.
  MAX_ADJUST = 1048576

  # Maximum component size to test in bytes.
  MAX_TEST_SIZE = 4194304

  get '/' do
    # Generate a new unique session id.
    @id = stamp

    # Clear all existing cachetest cookies.
    request.cookies.each_key do |name|
      response.delete_cookie(name) if name =~ /^cache_/
    end

    # Render the index page.
    erubis :index
  end

  get '/a/:id' do |id|
    get_cookies

    adjust(:css)
    adjust(:js)

    @id            = id
    @max_test_size = MAX_TEST_SIZE
    @request_css   = !@cookies[:css][:max]
    @request_js    = !@cookies[:js][:max]
    @next_url      = "/b/#{@id}"

    response['Content-Type']  = 'text/html;charset=utf-8'
    response['Cache-Control'] = 'no-store;max-age=0;must-revalidate'
    response['Expires']       = 'Fri, 01 Apr 2010 01:00:00 GMT'

    erubis :a
  end

  get '/b/:id' do |id|
    get_cookies

    @id            = id
    @max_test_size = MAX_TEST_SIZE
    @request_css   = !@cookies[:css][:max]
    @request_js    = !@cookies[:js][:max]
    @next_url      = "/a/#{@id}"

    response['Content-Type']  = 'text/html;charset=utf-8'
    response['Cache-Control'] = 'no-store;max-age=0;must-revalidate'
    response['Expires']       = 'Fri, 01 Apr 2010 01:00:00 GMT'

    erubis :b
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

    # if length > 1128005 && ext == 'js'
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
    def adjust(type)
      values = @cookies[type]

      unless values[:max] || values[:status] == 'new'

        if values[:status] == 'miss'
          # Cache miss: over the max size. Adjust downward.
          values[:adjust] = [values[:adjust] / 2, 1].max if values[:adjust] > 1
          values[:size]  -= values[:adjust]
          response.set_cookie("cache_#{type}_adjust", :value => values[:adjust], :path => '/')

        else
          # Cache hit: under the max size.
          if values[:adjust] == 1 || values[:size] >= MAX_TEST_SIZE
            # We either found the max size or hit the test ceiling
            values[:size] = MAX_TEST_SIZE if values[:size] > MAX_TEST_SIZE
            values[:max]  = values[:size]
            response.set_cookie("cache_#{type}_max", :value => values[:max], :path => '/')

          else
            # Adjust upward to a max of 4MB.
            values[:adjust] = [values[:adjust] + (values[:adjust] / 4), MAX_ADJUST].min
            values[:size]  += values[:adjust]
            response.set_cookie("cache_#{type}_adjust", :value => values[:adjust], :path => '/')
          end
        end

        response.set_cookie("cache_#{type}_size", :value => values[:size], :path => '/')
      end
    end

    def get_cookies
      @cookies = {
        :css => {
          :adjust => (request.cookies['cache_css_adjust'] || 65536).to_i,
          :max    => request.cookies['cache_css_max'],
          :size   => (request.cookies['cache_css_size'] || 65536).to_i,
          :status => request.cookies['cache_css_status'] || 'new'
        },

        :js => {
          :adjust => (request.cookies['cache_js_adjust'] || 65536).to_i,
          :max    => request.cookies['cache_js_max'],
          :size   => (request.cookies['cache_js_size'] || 65536).to_i,
          :status => request.cookies['cache_js_status'] || 'new'
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
