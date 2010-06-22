require 'lib/cachetest'

map '/' do
  run CacheTest
end

map '/gzip' do
  run GzipCacheTest
end
