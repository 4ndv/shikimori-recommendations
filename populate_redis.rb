require_relative 'lib/recommender'

rec = Recommender.new

data = File.read(ARGV[0])

i = 0

data.each_line do |line|
  rate = line.split(':')

  # Обратите внимание, что 1 и 0 поменяны местами!
  rec.rate(rate[1], rate[0], rate[2], rate[3].to_f / 10)

  puts "Nom. #{i += 1}"
end
