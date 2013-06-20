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
  DB.run("ALTER TABLE cities ADD COLUMN point geography(POINT, 4326);")
end

if not DB.tables.include?(:connections) then
  DB.create_table :connections do
    foreign_key :start_city_id, :cities, :null=>false
    foreign_key :end_city_id, :cities, :null=>false
    Integer :geographic_distance    
    Integer :route_distance
    Boolean :is_connected
    Boolean :is_tortuous
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

# Calculate connections
# Connection.dataset.delete
if Connection.dataset.empty? then 
  City.all.each do |city_a|
    city_a.nearest(5).each do |city_b|
      # print '.'
      puts "#{city_a.name} => #{city_b.name}"
      c = Connection.new({:start_city => city_a, :end_city => city_b})
      c.save

      puts "#{city_b.name} => #{city_a.name}"    
      c = Connection.new({:start_city => city_b, :end_city => city_a})
      c.save
    end
  end
end

# connection = Connection.first
json = Connection.geojson_feature_collection.to_json

File.open('../template/connections.geojson', 'w') {|f| f.write("var connections = "+json) }