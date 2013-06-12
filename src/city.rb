require 'csv'

class City < Sequel::Model
  
  set_allowed_columns :lon, :lat

  def nearest(depth)
    City.unrestrict_primary_key
    result = []
    DB.fetch("select id from cities order by ST_Distance(ST_SetSRID(ST_Point(#{lon}, #{lat}),4326), ST_SetSRID(ST_Point(lon, lat),4326)) limit #{depth} offset 1") do |row|
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
    City.dataset.delete
    puts 'Initializing cities from ' + filename
    unmapped_cities = 0
    total_cities = 0
    CSV.foreach(filename, :headers => true) do |row|
      c = City.new
      c.id         = row['id']
      c.name       = row['name']      
      c.uf         = row['uf']
      c.lon        = row['lon']
      c.lat        = row['lat']
      c.is_capital = row['is_capital']
      # c.geom       = "GeomFromText('POINT(1 1)')" #c.make_point
      if c.lon or c.lat then 
        c.save 
      else
        unmapped_cities = unmapped_cities + 1
      end
      total_cities = total_cities + 1
    end
    puts 'Cities lacking coordinates: ' + unmapped_cities.to_s
    puts 'Cities imported: ' + (total_cities - unmapped_cities).to_s + ' out of ' + total_cities.to_s
  end
  
end