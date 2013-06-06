class City < ActiveRecord::Base


  def nearest_cities(depth)
    select id, st_distance(MakePoint(#{lon}, #{lat}), geometry) as distance
    from cities
    where lat != '' and lon != '' and distance > 0
    order by distance
    limit 3;
  end
      
end