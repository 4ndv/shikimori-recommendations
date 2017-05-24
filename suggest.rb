require_relative 'lib/recommender'

r = Recommender.new

category = ARGV[0]
categories = category.downcase + 's'

# r.set :similars_threshold, 0.9

suggestions = r.suggest(category, ARGV[1], (ARGV[2] || 25).to_i)

suggestions.each do |s|
  puts "https://shikimori.org/#{categories}/#{s[0]} with score #{s[1]}"
end
