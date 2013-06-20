require './routing_helper.rb'
require 'rgeo/geo_json'

class Connection < Sequel::Model

  many_to_one :start_city, :class=>:City, :key => :start_city_id
  many_to_one :end_city, :class=>:City, :key => :end_city_id
    
  set_allowed_columns :start_city, :end_city, :geographic_distance
  
  @@geojson_entity_factory = RGeo::GeoJSON::EntityFactory.instance
  
  def before_save

    # calculate direct distance
    self.geographic_distance = start_city.geographic_dist_to(end_city)
    
    # Create a linestring to represent the connection.
    # Uses city ids to compute linestring offset.
    geom_wkt = "linestring(#{start_city.lon} #{start_city.lat},#{end_city.lon} #{end_city.lat})"
    puts "wkt: " + geom_wkt
    self.line_geometry = DB.select { |o| o.ST_OffsetCurve(o.ST_GeomFromText(geom_wkt, 4326),-0.005)}.first[:st_offsetcurve];

    # calculate route
    route_ab = RoutingHelper.between(start_city, end_city)
        
    # evaluate route
    if route_ab["status"] == 0 then # connection exists
      self.is_connected = true
      self.route_distance = (route_ab["route_summary"]["total_distance"] / 1000).round
      if (self.geographic_distance * 1.5 < self.route_distance) then
        self.is_tortuous = true
      else 
        self.is_tortuous = false        
      end
    else # not connected
      self.is_connected = false
      self.route_distance = 0
      self.is_tortuous = false              
    end

    super
  end
  
  def as_wkt
    DB.fetch("select ST_asText('#{self.line_geometry}') as wkt;").first[:wkt]
  end

  def as_geojson
    DB.fetch("select ST_asGeoJSON('#{self.line_geometry}') as geojson;").first[:geojson]
  end
  
  def as_geojson_hash
    hash = JSON.parse(as_geojson)
    
    # fix geojson provided by postgis
    hash['type'] = 'Feature'
    hash.merge!({ 
        "geometry" => { 
          "type" => "LineString", 
          "coordinates" => hash['coordinates']
        }
    })
    hash.delete("coordinates")

    # add properties with connection info
    hash.merge!({
      "properties" => {
        "start_city_uf"       => self.start_city.uf,      
        "start_city"          => self.start_city.name,
        "end_city_uf"         => self.end_city.uf,      
        "end_city"            => self.end_city.name,
        "geo_distance"        => self.geographic_distance, 
        "route_distance"      => self.route_distance,
        "is_connected"        => self.is_connected,
        "is_tortuous"         => self.is_tortuous,
        "color"               => '',
        "width"               => ''
        }
    })

    # set color from connection status
    # if is_connected then
    #   hash["properties"]["color"] = "green"
    #   if is_tortuous then
    #     hash["properties"]["color"] = "orange"
    #   end
    # else
    #   hash["properties"]["color"] = "red"      
    # end
    
    hash
  end
  
  # retrive a geojson with all features in DB
  def self.geojson_feature_collection
    features = []
    all.each do |connection|
      features << connection.as_geojson_hash
    end    
    
    feature_collection = {
      "type" => "FeatureCollection",
      "features" => features
    }
  end
  
  
  
end