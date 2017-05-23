require 'faraday'
require 'faraday_middleware'
require 'faraday-rate_limiter'

@client = Faraday.new 'https://shikimori.org/api/' do |conn|
  # Лимитируем соединения, чтобы шикимори не обижалсо
  conn.request :rate_limiter, interval: 0.6

  conn.response :json
  # conn.response :logger

  conn.adapter Faraday.default_adapter
end

def user_rates_with_score(user_id)
  rates = @client.get('v2/user_rates', user_id: user_id).body
  # Убираем все неоцененные и запланированные
  rates.select { |x| x['score'] != 0 && x['status'] != 'planned' }
end

def target_rates_with_score(target_id, target_type, limit, page)
  puts "[Target] Fetching #{target_type} ##{target_id}, page #{page}"
  rates = @client.get('v2/user_rates', target_id: target_id, target_type: target_type, limit: limit, page: page).body
  # Убираем все неоцененные и запланированные
  rates.select { |x| x['score'] != 0 && x['status'] != 'planned' && (x['episodes'] > 0 || x['chapters'] > 0 || x['volumes'] > 0) }
end

def active_users
  @client.get('stats/active_users').body
end

def rate_to_cache_line(rate)
  "#{rate['user_id']}:#{rate['target_type']}:#{rate['target_id']}:#{rate['score']}"
end

puts 'Введите id пользователя, с которого начинаем процесс парсинга:'
puts '(id можно узнать, зайдя в исходный код страницы пользователя поиском по data-user-id)'
who = gets.strip

start_rates = user_rates_with_score(who)
puts 'Получили оценки пользователя, кешируем'
open 'cache/rates.txt', 'a' do |file|
  start_rates.each do |rate|
    file.puts rate_to_cache_line(rate)
  end
end

puts 'Получаем иды тех, кто смотрел те же тайтлы, что и стартовый пользователь'
our_titles_users = []
start_rates.each_with_index do |rate, index|
  puts "#{index + 1} / #{start_rates.size}"
  count = 1
  page = 1
  while count > 0
    res = target_rates_with_score(rate['target_id'], rate['target_type'], 1000, page)
    count = res.count
    our_titles_users += res
    page += 1
  end
end

puts 'Получили, кешируем'
open 'cache/our_titles_rates.txt', 'a' do |file|
  our_titles_users.each do |rate|
    file.puts rate_to_cache_line(rate)
  end
end

puts 'Получаем активных пользователей'
active_users_ids = active_users

our_titles_users_ids = our_titles_users.map { |x| x['user_id'] }.uniq
puts 'Кешируем иды тех, кто смотрел то же самое'
open 'cache/watched_same.txt', 'a' do |file|
  our_titles_users_ids.each do |id|
    file.puts id
  end
end

puts "Собрано айдишников смотревших то же самое: #{our_titles_users.size}"

puts 'Оставляем только айдишники активных пользователей, смотревших то же, что и мы'

# & - это пересечение
needed = active_users_ids & our_titles_users_ids

puts "Убираем неактивных, осталось #{needed.size} идов, парсим их"
parsed = []

needed.each_with_index do |user_id, index|
  puts "#{index + 1} / #{needed.size}"
  rates = user_rates_with_score(user_id)

  parsed += rates

  open 'cache/rates.txt', 'a' do |file|
    rates.each do |rate|
      file.puts rate_to_cache_line(rate)
    end
  end
end

puts 'Готово!'
