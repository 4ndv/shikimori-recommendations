require 'redis'
require 'securerandom'

# https://rosettacode.org/wiki/Averages/Root_mean_square#Ruby
class Array
  def quadratic_mean
    Math.sqrt(self.inject(0.0) { |s, y| s + y * y } / self.length)
  end
end

# Basic recommendation system implementation from this Redislabs whitepaper (with some changes):
# https://redislabs.com/docs/ultra-fast-recommendations-engine-using-redis-go/
# https://github.com/RedisLabs/redis-recommend/

# Well, it's not worked good for me, but maybe it's my fault

#
# If you want to see likes/dislikes, open recommender.rb, not this file
#

class Recommender
  TEMP_TTL = 240

  def initialize
    @redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
    @vars = {}
  end

  def set var, value
    @vars[var] = value
  end

  def get var
    @vars[var]
  end

  def temp_key
    "ztmp:#{SecureRandom.hex(10)}"
  end

  def user_items(category, user, amount = -1)
    @redis.zrevrange("#{category}:user:#{user}:items", 0, amount)
  end

  def item_scores(category, item, amount = -1)
    @redis.zrevrange("#{category}:item:#{item}:scores", 0, amount)
  end

  # Ищем подходящие итемы
  def find_suggest_candidates(category, user)
    key = temp_key

    similar_users = find_similarity_candidates(category, user)

    similar_users_items = ["#{category}:user:#{user}:items"]
    similar_users_items << similar_users.map { |s| "#{category}:user:#{s}:items" }
    similar_users_weights = [-1]
    similar_users_weights << Array.new(similar_users.size, 1)

    @redis.zunionstore(key, similar_users_items.flatten, weights: similar_users_weights.flatten, aggregate: 'min')

    candidates = @redis.zrangebyscore(key, 0, 'inf')

    @redis.del(key)

    candidates
  end

  # Ищем пользователей, которые лайкали все то же самое
  def find_similarity_candidates(category, user)
    key = temp_key

    items = user_items(category, user)

    scores_keys = items.map { |i| "#{category}:item:#{i}:scores" }

    @redis.zunionstore(key, scores_keys)

    users = @redis.zrange(key, 0, -1)

    @redis.del(key)

    users
  end

  def calc_item_probability(category, similars_key, item)
    key = temp_key

    @redis.zinterstore(key, [similars_key, "#{category}:item:#{item}:scores"], weights: [0, 1])

    scores = @redis.zrange(key, 0, -1, with_scores: true)

    @redis.del(key)

    scores = scores.map { |s| s[1] }

    return 0 if scores.empty?

    probability = scores.sum / scores.size

    probability
  end

  # Ищем похожих пользователей и считаем для них RMS
  # Единственный метод, который возвращает ключ, по которому можно получить данные
  def calculate_similars(category, user)
    key_similars = temp_key

    similars = find_similarity_candidates(category, user)

    similars.each do |similar_user|
      similarity = calc_similarity(category, user, similar_user)

      next if similarity > get(:similars_limit)

      @redis.zadd(key_similars, similarity, similar_user)
    end

    @redis.expire(key_similars, TEMP_TTL)

    key_similars
  end

  def suggest(category, user, amount = -1)
    sims = calculate_similars(category, user)
    candidates = find_suggest_candidates(category, user)

    candidates_scores = []

    candidates.each do |candidate|
      candidates_scores << [candidate, calc_item_probability(category, sims, candidate)]
    end

    if amount > 0
      candidates_scores.sort_by(&:last).reverse.first(amount)
    else
      candidates_scores.sort_by(&:last).reverse
    end
  end

  def calc_similarity(category, user, with)
    key = temp_key

    @redis.zinterstore(key, ["#{category}:user:#{user}:items", "#{category}:user:#{with}:items"], weights: [1, -1])

    diffs = @redis.zrange(key, 0, -1, with_scores: true)

    @redis.del(key)

    diffs = diffs.map { |d| d[1] }

    diffs.quadratic_mean
  end

  def rate(category, user, item, score)
    @redis.zadd "#{category}:user:#{user}:items", score, item
    @redis.zadd "#{category}:item:#{item}:scores", score, user
    @redis.sadd 'users', user
    @redis.sadd 'items', item
    @redis.sadd 'categories', category
  end
end
