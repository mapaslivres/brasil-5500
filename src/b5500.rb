# encoding: UTF-8

require 'sequel'
require 'logger'


# Initialize database
DB = Sequel.postgres('b5500', :user => 'vitor', :host => 'localhost') #, :loggers => [Logger.new($stdout)])

# Define tables
if not DB.tables.include?(:cities) then
  DB.create_table :cities do
    primary_key :id
    String :name
    String :uf
    Float :lon
    Float :lat
    Boolean :is_capital
  end  
end

if not DB.tables.include?(:connections) then
  DB.create_table :connections do
    foreign_key :start_city_id, :cities, :null=>false
    foreign_key :end_city_id, :cities, :null=>false
    Float :geographic_distance    
    Float :ab_route_distance
    Float :ba_route_distance
    Boolean :ab_connected
    Boolean :ba_connected    
    Boolean :ab_tortuous
    Boolean :ba_tortuous
  end
  DB.run("ALTER TABLE connections ADD COLUMN line_geometry geography(LINESTRING, 4326);")
end

# Include models
require './city.rb'
require './connection.rb'

# Import cities, if database is empty
if City.dataset.empty? then 
  City.init_db_from_csv('../data/cities.csv') 
end

Connection.dataset.delete
City.limit(1).each do |city_a|
  city_a.nearest(1).each do |city_b|
    print '.'

    c = Connection.new({:start_city => city_a, :end_city => city_b})
    c.save
    
    c = Connection.new({:start_city => city_b, :end_city => city_a})
    c.save
    
    
  end
end


# City.first.nearest(5).each do |city_b|
#   puts city_b.name
# end
# City.all.each do |c|
#   puts c.make_point
# end
