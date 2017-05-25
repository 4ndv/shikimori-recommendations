require_relative 'lib/recommender'

recommenders = {}

data = File.read(ARGV[0])

i = 0

data.each_line do |line|
  rate = line.split(':')

  recommenders[rate[1]] = Recommender.new(rate[1]) unless recommenders.key?(rate[1])

  r = recommenders[rate[1]]

  # Обратите внимание, что 1 и 0 поменяны местами!
  r.like(rate[0], rate[2]) if rate[3].to_i >= 6
  r.dislike(rate[0], rate[2]) if rate[3].to_i < 6

  puts "Nom. #{i += 1}"
end
