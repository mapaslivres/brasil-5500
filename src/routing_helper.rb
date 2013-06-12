require 'net/http'
require 'JSON'

class RoutingHelper
  
  def self.between(city_a, city_b)
    uri = URI("http://localhost:5000/viaroute?loc=#{city_a.lat},#{city_a.lon}&loc=#{city_b.lat},#{city_b.lon}")
    response = Net::HTTP.get(uri)
    JSON.parse(response)
  end
  
end