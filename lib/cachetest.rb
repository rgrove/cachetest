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

  # Uncomment the following line to include an ETag response header.
  # use Rack::ETag

  set :modtime, Time.now

  get '/' do
    erubis :index
  end

  get %r{^/random/(nocache/)?(\d+)(?:\.([a-z]+))?$} do |nocache, length, ext|
    types = {
      'css'  => 'text/css',
      'html' => 'text/html',
      'js'   => 'application/javascript',
    }

    # Limit to 20MB.
    return 400 if length.to_i > 20971520

    # Spit out request headers, for verifying ETag/Last-Modified support.
    # env.each do |key, value|
    #   puts "#{key}: #{value}" if key =~ /^HTTP_/
    # end

    # Uncomment the following line (and use the /random/nocache component URL)
    # to test Last-Modified support.
    # last_modified(settings.modtime)

    response['Content-Type'] = "#{types[ext] || 'text/plain'};charset=utf-8"

    if nocache
      response['Cache-Control'] = 'max-age=0;must-revalidate'
      response['Expires']       = 'Thu, 01 Apr 2010 01:00:00 GMT'
    else
      response['Cache-Control'] = 'max-age=315360000'
      response['Expires']       = 'Fri, 01 May 2020 03:47:24 GMT'
    end

    random_alpha(length)
  end

  helpers do

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

  end

end

class GzipCacheTest < CacheTest
  use Rack::Deflater
end
