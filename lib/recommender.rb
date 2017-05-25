require 'redis'
require 'securerandom'

# Redis implementation of this recommendation system:
# https://davidcel.is/posts/collaborative-filtering-with-likes-and-dislikes/

class Recommender
  def initialize(category)
    @redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')

    @vars = {
      user_similarity_threshold: 0.15
    }

    @category = category
  end

  def set(var, value)
    @vars[var] = value
  end

  def get(var)
    @vars[var]
  end

  def temp_key
    "ztmp:#{SecureRandom.hex(10)}"
  end

  def find_similar_users_with_scores(user)
    liked_items = @redis.smembers("#{@category}:user_likes:#{user}")

    like_it_too_keys = liked_items.map { |item| "#{@category}:item_liked_by:#{item}" }

    who_likes_this_too = @redis.sunion(like_it_too_keys)

    users = []

    who_likes_this_too.each do |like_user|
      similarity = similarity_koeff(user, like_user)

      next if similarity < get(:user_similarity_threshold)

      users << [like_user, similarity]
    end

    users
  end

  def what_users_likes(users)
    users = users.map { |user| "#{@category}:user_likes:#{user}" }

    @redis.sunion(users)
  end

  def union_rates_count(user_one, user_two)
    key = temp_key

    @redis.sunionstore(key, ["#{@category}:user_items:#{user_one}", "#{@category}:user_items:#{user_two}"])

    count = @redis.scard(key)

    @redis.del(key)

    count
  end

  def intersection_likes_count(user_one, user_two)
    key = temp_key

    @redis.sinterstore(key, ["#{@category}:user_likes:#{user_one}", "#{@category}:user_likes:#{user_two}"])

    count = @redis.scard(key)

    @redis.del(key)

    count
  end

  def intersection_dislikes_count(user_one, user_two)
    key = temp_key

    @redis.sinterstore(key, ["#{@category}:user_dislikes:#{user_one}", "#{@category}:user_dislikes:#{user_two}"])

    count = @redis.scard(key)

    @redis.del(key)

    count
  end

  def intersection_likes_dislikes_count(user_one, user_two)
    key = temp_key

    @redis.sinterstore(key, ["#{@category}:user_likes:#{user_one}", "#{@category}:user_dislikes:#{user_two}"])

    count = @redis.scard(key)

    @redis.del(key)

    count
  end

  def similarity_koeff(user_one, user_two)
    # Ключ для кеша. Minmax чтобы отдельно не кешировать вещи вроде A:B, B:A
    id = [user_one.to_i, user_two.to_i].minmax.join(':')

    cached = @redis.hget("#{@category}:similarity_cache", id)

    return cached.to_f if cached

    sum = 0.0

    # Лайки-лайки
    sum += intersection_likes_count(user_one, user_two)
    # Дизлайки-дизлайки
    sum += intersection_dislikes_count(user_one, user_two)
    # Лайки-дизлайки
    sum -= intersection_likes_dislikes_count(user_one, user_two)
    # Дизлайки-лайки
    # Используем ту же функцию, но аргументы в обратном порядке
    sum -= intersection_likes_dislikes_count(user_two, user_one)

    sum /= union_rates_count(user_one, user_two)

    @redis.hset("#{@category}:similarity_cache", id, sum)

    sum
  end

  def who_likes_item(item)
    @redis.smembers("#{@category}:item_liked_by:#{item}")
  end

  def who_dislikes_item(item)
    @redis.smembers("#{@category}:item_disliked_by:#{item}")
  end

  def how_much_users_rated_item(item)
    @redis.scard("#{@category}:item_rated_by:#{item}")
  end

  def sum_koeffs(user, with)
    # with = Array

    koeffs = 0.0

    with.each do |w|
      koeffs += similarity_koeff(user, w)
    end

    koeffs
  end

  def predict(user, item)
    likes = who_likes_item(item)
    dislikes = who_dislikes_item(item)

    rates_count = how_much_users_rated_item(item)

    likes_sum = sum_koeffs(user, likes)
    dislikes_sum = sum_koeffs(user, dislikes)

    (likes_sum - dislikes_sum) / rates_count
  end

  def recommend(user, amount = -1)
    similar_users = find_similar_users_with_scores(user)
    similar_users = similar_users.map(&:first)

    liked_by_similar = what_users_likes(similar_users)

    # Убираем то, что и так уже просмотрено нами
    liked_by_similar -= what_users_likes([user])

    results = []

    liked_by_similar.each do |like|
      results << [like, predict(user, like)]
    end

    if amount < 0
      results.sort_by(&:last).reverse
    else
      results.sort_by(&:last).reverse.first(amount)
    end
  end

  # Сохраняем все, что не зависит от оценки
  def store_item(user, item)
    @redis.sadd "#{@category}:user_items:#{user}", item
    @redis.sadd "#{@category}:item_rated_by:#{item}", user
    @redis.sadd "#{@category}:users", user
    @redis.sadd "#{@category}:items", item
    @redis.sadd 'categories', @category
  end

  def like(user, item)
    @redis.sadd "#{@category}:user_likes:#{user}", item
    @redis.sadd "#{@category}:item_liked_by:#{item}", user

    store_item(user, item)
  end

  def dislike(user, item)
    @redis.sadd "#{@category}:user_dislikes:#{user}", item
    @redis.sadd "#{@category}:item_disliked_by:#{item}", user

    store_item(user, item)
  end
end
