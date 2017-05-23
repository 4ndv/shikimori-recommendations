require 'redis'
require 'secure_random'

# Basic recommendation system implementation from this Redislabs whitepaper:
# https://redislabs.com/docs/ultra-fast-recommendations-engine-using-redis-go/
# https://github.com/RedisLabs/redis-recommend/

class Recommender
  def initialize
    @redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
  end

  def temp_key
    "ztmp:#{SecureRandom.hex(10)}"
  end

  def rate(user, category, item, score)
    @redis.zadd "user:#{category}:#{user}:items", score, item
    @redis.zadd "item:#{category}:#{item}:scores", score, user
    @redis.sadd 'users', user
    @redis.sadd 'items', item
    @redis.sadd 'categories', category
  end
end
