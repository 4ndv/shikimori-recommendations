require_relative 'lib/recommender'

category = ARGV[0]
categories = category.downcase + 's'

r = Recommender.new(category)

r.set :user_similarity_threshold, 0.15

suggestions = r.recommend(ARGV[1], (ARGV[2] || 25).to_i)

suggestions.each do |s|
  puts "https://shikimori.org/#{categories}/#{s[0]} with score #{s[1]}"
end
