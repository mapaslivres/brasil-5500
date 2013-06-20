require 'csv'

class City < Sequel::Model
  
  plugin :validation_helpers

  def validate
   super
   validates_presence [:uf, :name, :lon, :lat]
   validates_unique([:uf, :name],[:lon, :lat])
  end
  
  set_allowed_columns :lon, :lat

  def nearest(depth)
    City.unrestrict_primary_key
    result = []
    DB.fetch("select id from cities where id != #{id} order by ST_Distance(ST_SetSRID(ST_Point(#{lon}, #{lat}),4326), ST_SetSRID(ST_Point(lon, lat),4326)) limit #{depth} ") do |row|
      result << City[row[:id]]
    end
    result
  end
  
  def geographic_dist_to(another_city)
    (DB.fetch("select ST_Distance(ST_SetSRID(ST_Point(#{self.lon}, #{self.lat}),4326), ST_SetSRID(ST_Point(#{another_city.lon}, #{another_city.lat}),4326)) as distance").first[:distance] * 100).round
  end

  def make_point
    "ST_SetSRID(ST_Point(#{lon}, #{lat}),4326)"
  end
  
  def self.init_db_from_csv(filename)
    Connection.dataset.delete
    City.dataset.delete
    $stdout.puts 'Initializing cities from ' + filename + ':'
    invalid_cities = 0
    total_cities = 0
    CSV.foreach(filename, :headers => true) do |row|
      c = City.new
      c.id         = row['id']
      c.name       = row['name']      
      c.uf         = row['uf']
      c.lon        = row['lon']
      c.lat        = row['lat']
      c.is_capital = row['is_capital']
      if c.valid? then 
        c.point       = "POINT(#{c.lon} #{c.lat})"
        c.save 
        $stdout.print '.'
      else
        invalid_cities = invalid_cities + 1
        $stdout.print 'E'        
      end
      total_cities = total_cities + 1
    end
    $stdout.puts "\nCities with invalid data: " + invalid_cities.to_s
    $stdout.puts "Cities imported: " + (total_cities - invalid_cities).to_s + " out of " + total_cities.to_s
  end
  
end