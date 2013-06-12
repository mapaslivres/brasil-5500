require './routing_helper.rb'

class Connection < Sequel::Model

  many_to_one :start_city, :class=>:City, :key => :start_city_id
  many_to_one :end_city, :class=>:City, :key => :end_city_id
    
  set_allowed_columns :start_city, :end_city, :geographic_distance
  
  
  def before_save

    # calculate direct distance
    self.geographic_distance = start_city.geographic_dist_to(end_city)
    
    # Create a linestring to represent the connection.
    # Uses city ids to compute linestring offset.
    geom_wkt = "linestring(#{start_city.lon} #{start_city.lat},#{end_city.lon} #{end_city.lat})"
    self.line_geometry = DB.select { |o| o.ST_OffsetCurve(o.ST_GeomFromText(geom_wkt, 4326),0.005)}.first[:st_offsetcurve];

    # calculate route
    route_ab = RoutingHelper.between(start_city, end_city)
        
    # evaluate route
    if route_ab["status"] == 0 then # connection exists
      self.ab_connected = true
      self.ab_route_distance = (route_ab["route_summary"]["total_distance"] / 1000).round
      if (self.geographic_distance * 1.5 < self.ab_route_distance) then
        self.ab_tortuous = true
      else 
        self.ab_tortuous = false        
      end
    else # not connected
      self.ab_connected = false
      self.ab_route_distance = 0
      self.ab_tortuous = false              
    end

    # calculate reverse route
    # route_ba = RoutingHelper.between(end_city, start_city)
        
    # evaluate route
    # if route_ba["status"] == 0 then # connection exists
    #   self.ba_connected = true
    #   self.ba_route_distance = (route_ba["route_summary"]["total_distance"] / 1000).round
    #   if (self.geographic_distance * 1.5 < self.ba_route_distance) then
    #     self.ba_tortuous = true
    #   else 
    #     self.ba_tortuous = false        
    #   end
    # else # not connected
    #   self.ba_connected = false
    #   self.ba_route_distance = 0
    #   self.ba_tortuous = false              
    # end

    super
  end
  
  
end