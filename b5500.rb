# encoding: UTF-8

# 
# Para rodar este script, é necessário que seu SQLite tenha sido instalado com 
# extensões habilitadas. Isto pode ser feito especificando o diretório do SQLite
# ao instalar a gem, por exemplo:
# 
#   gem install sqlite3 -- --with-sqlite3-dir=/usr/local/Cellar/sqlite/3.7.17
# 

require 'sqlite3'
require 'slop'
require 'json'
require 'rgeo-geojson'

def nearest_cities(lon, lat, limit)
  sql = <<SQL
      select id, st_distance(MakePoint(#{lon}, #{lat}), geometry) as distance
      from cities
      where lat != '' and lon != '' and distance > 0
      order by distance
      limit 3;
SQL
  $db.execute(sql) 
end

def nearest_network_node(lon, lat)
  
  # puts "  Buscando nó mais próximo a #{lon},#{lat}..."
  
  node_id = ''
  
  # busca o nó da rede mais próximo
  (1..10).each do |i|
    search_radius = 0.0001 * 10 ** i
    
    query = <<SQL
        select node_id
        from roads_nodes
        where roads_nodes.ROWID 
          in (
            select pkid 
            from idx_roads_nodes_geometry
            where pkid match RTreeDistWithin(#{lon}, #{lat}, #{search_radius}) 
          )
        order by st_distance(MakePoint(#{lon}, #{lat}), geometry)
        limit 1;
SQL
    
    $db.execute( query ) do |row|
      node_id = row['node_id']
    end
        
    # Se não encontrar nó, expande raio de busca
    if node_id != '' then       
      break 
    end
  end
    
  node_id 
end


def update_nearest_nodes

  $db.execute("SELECT CreateSpatialIndex('roads_nodes', 'geometry');") rescue puts 'Spatial index already defined.';  

  puts "Updating cities' entry nodes in network:"
  # busca nó da rede mais próximo para cidades que tem coordenadas
  $db.execute( "select * from cities where lon != '' and lat != ''" ) do |city|

    # puts "Encontrando nó mais próximo para #{cidade['nome']} (#{cidade['uf']}):"
    lon = city["lon"].to_f
    lat = city["lat"].to_f
    $db.execute("update cities set node_id = ? where id = ?", nearest_network_node(lon, lat), city['id'])
    print '.'
  end
  
  puts 'Done.'
  
end

def total_distance(node_a, node_b)
  
  sql = <<SQL
        select round(cost/1000) as distance from roads_net where nodefrom = #{node_a} and nodeto = #{node_b} limit 1
SQL

  row = $db.get_first_row(sql) 
  row['distance']
end


def calculate_route_distances
  
  # Set algorithm
  $db.execute("update roads_net set Algorithm = 'A*';")
    
  # Join tables 'cities' and 'pairs' 
  sql = <<SQL
    select 
      city_a.id       as city_a_id,
      city_a.node_id  as city_a_node_id, 
      city_b.id       as city_b_id,
      city_b.node_id  as city_b_node_id
    from pairs p 
    left join cities as city_a on p.a_id = city_a.id 
    left join cities as city_b on p.b_id = city_b.id ;
SQL
  
  # Calculate distance by driving
  $db.execute(sql).each do |pair|
    a_id = pair['city_a_id']
    b_id = pair['city_b_id']
    a_node_id = pair['city_a_node_id']
    b_node_id = pair['city_b_node_id']
    ab_distance = total_distance(a_node_id,b_node_id)
    ba_distance = total_distance(b_node_id,a_node_id)

    $db.execute("update pairs set ab_route_dist = #{ab_distance}, ba_route_dist = #{ba_distance} where a_id == #{a_id} and b_id == #{b_id}")
    print '.'
  end
  
end

def calculate_geo_distance
  puts 'Calculating geo distances...'
  
  # Create geometry column for table 'pairs' if not exists
  $db.execute("select AddGeometryColumn('pairs', 'geometry', 4326, 'LINESTRING', 'XY');")
  
  # Join tables 'cities' and 'pairs' 
  sql = <<SQL
    select 
      city_a.id   as a_id,
      city_a.lon  as a_lon, 
      city_a.lat  as a_lat, 
      city_b.id   as b_id,
      city_b.lon  as b_lon, 
      city_b.lat  as b_lat
    from pairs p 
    left join cities as city_a on p.a_id = city_a.id 
    left join cities as city_b on p.b_id = city_b.id ;
SQL

  # Create and save geometry for each pair
  $db.execute(sql).each do |pair|
    print '.'
    $db.execute("update pairs set geometry = GeomFromText('LINESTRING(#{pair['a_lon']} #{pair['a_lat']}, #{pair['b_lon']} #{pair['b_lat']})',4326) where a_id == #{pair['a_id']} and b_id == #{pair['b_id']}")
  end
  
  
end
  
def distances_from_capitals
  
  # get capitals
  capitais = $db.execute( "select * from cities where capital = 'true' and lon != '' and lat != '' order by id" ) 

  # Find distances to other cities. Avoids generate duplicated connections by 
  # iterating over cities' ids ascending.
  capitais.each do |capital|
    puts "Calculando rotas a partir de #{capital['nome']} (#{capital["uf"]})"
    cidades = $db.execute( "select * from cities where capital = 'false' and lon != '' and lat != '' and uf = ? order by id", capital["uf"]) 
    
    cidades.each do |cidade|
      a_node_id  = capital['node_id']
      a_city_id  = capital['id']
      a_x        = capital['lon']
      a_y        = capital['lat']

      b_node_id  = cidade['node_id']
      b_city_id  = cidade['id']
      b_x        = cidade['lon']
      b_y        = cidade['lat']
      
      ab_route_distance = total_distance(a_node_id, b_node_id)
      ba_route_distance = total_distance(b_node_id, a_node_id)
      geometry_wkt = "LINESTRING(#{a_x} #{a_y}, #{b_x} #{b_y})"
            
      $db.execute("insert into distances values (?,?,?,?,'','','','','',GeomFromText(?))",a_city_id, b_city_id, ba_route_distance, ab_route_distance, geometry_wkt)
      print " #{cidade['nome']}: ida=#{ab_route_distance} km volta=#{ba_route_distance} km "

    end
    
    puts ""
  end
  
  # find straight distances between cities
  $db.execute("update distances set direct_distance = round(GLength(geometry)*100)")

  # update connection status
  $db.execute("update distances set ab_connected = case when ab_route_distance > 0 then 'yes' else 'no' end;")
  $db.execute("update distances set ba_connected = case when ba_route_distance > 0 then 'yes' else 'no' end;")

  # update sinuosity status
  $db.execute("update distances set ab_tortuous = case when ab_route_distance / direct_distance > 1.5 then 'yes' else 'no' end;")
  $db.execute("update distances set ba_tortuous = case when ba_route_distance / direct_distance > 1.5 then 'yes' else 'no' end;")

  
end

def import_cities_csv

  # Import cities.csv
  sql = <<SQL
    drop table if exists cities_csv; 
    create virtual table cities_csv using VirtualText(cities.csv, UTF-8, 1, COMMA, DOUBLEQUOTE, ',');

    drop table if exists cities;   
    create table cities as select * from cities_csv;
    alter table cities add column node_id integer;

    select AddGeometryColumn('cities', 'geometry', 4326, 'POINT', 'XY');
    select CreateSpatialIndex('cities', 'geometry');
    update cities set geometry = makepoint(cast(lon as real), cast(lat as real), 4326) where lat != '' and lon != '';
SQL
  
  $db.execute_batch(sql)
  

  
  # Find nearest nodes on network for each city
  update_nearest_nodes()
  
end

# 
# This function setup a 'pair' table and generate pairs between every city and its
# three nearest cities.
# 
def setup_pairs

  # Create table 'pairs' 
  $db.execute("drop table if exists pairs;")  
  $db.execute("create table pairs (a_id integer, b_id integer, ab_route_dist number, ba_route_dist number,direct_distance number, ab_connected boolean, ba_connected boolean, ab_tortuous boolean, ba_tortuous boolean);")
    
  # Generate city pairs to be analised
  cities = $db.execute('select * from cities where lat != "" and lon != "" ;')
  cities.each do |city_a| 
    puts "Cidades próximas a #{city_a['name']}."
    nearest_cities(city_a['lon'], city_a['lat'], 3).each do |city_b|
      # only saves pairs with consecutive ids, to avoid duplicates
      if city_a['id'] < city_b ['id'] then
        $db.execute("insert into pairs (a_id, b_id) values (?,?)",city_a['id'], city_b['id'])
      end
    end
  end
end

def generate_distances_geojson
    
  sql = <<SQL
    select 
      city_a.id   as city_a_id,
      city_a.nome as city_a_name, 
      city_a.uf   as city_a_uf,
      city_b.id   as city_b_id,
      city_b.nome as city_b_name, 
      city_b.uf   as city_b_uf,
      ab_route_distance,
      ba_route_distance,
      direct_distance,
      ab_connected,
      ba_connected,
      ab_tortuous,
      ba_tortuous,      
      aswkt(geometry) as wkt 
    from distances  d 
    left join cities as city_a on d.city_a_id = city_a.id 
    left join cities as city_b on d.city_b_id = city_b.id ;
SQL
  geo_factory = RGeo::Geographic.spherical_factory(:srid => 4326)
  features = []
  $db.execute(sql) do |row|
    geometry = geo_factory.parse_wkt(row['wkt'])
    properties = { 
      "city_a_id"         => row[0],
      "city_a_name"       => row[1],
      "city_a_uf"         => row[2],
      "city_b_id"         => row[3],
      "city_b_name"       => row[4],
      "city_b_uf"         => row[5],      
      "ab_route_distance" => row[6],
      "ba_route_distance" => row[7],
      "direct_distance"   => row[8],
      "ab_connected"      => row[9],
      "ba_connected"      => row[10],
      "ab_tortuous"       => row[11],
      "ba_tortuous"       => row[12],            
      "ab_distance_ratio" => row[6].to_f / row[8].to_f * 100,
      "ba_distance_ratio" => row[7].to_f / row[8].to_f * 100
    }
    feature = RGeo::GeoJSON::Feature.new(geometry, nil ,properties)
    features << feature
  end
  features_collection = RGeo::GeoJSON::FeatureCollection.new(features)
  
  # puts RGeo::GeoJSON.encode(features_collection).to_json
  
  File.open("template/connections.geojson","w") do |f|
    f.write("var connections = " + RGeo::GeoJSON.encode(features_collection).to_json)
  end
end

# puts "Abrindo o banco de dados..."
$db = SQLite3::Database.new File.expand_path("brasil-net.sqlite")

# puts "Carregando extensão Spatialite..."
$db.enable_load_extension 1
$db.load_extension '/usr/local/Cellar/libspatialite/3.0.1/lib/libspatialite.dylib' 
$db.results_as_hash = true


# Rotina para buscar nós mais próximos
opts = Slop.parse(:help => true) do
  banner 'Utilização: b5500.rb [options]'

  on :i, :import_cities, 'Importa cidades do arquivo cidades.csv'
  on :d, :distances, 'Calcula distancias entre cidades'
  on :g, :geodistances, 'Calcula distancias geométrica entre cidades.'
  on :j, :geojson, 'Gera GeoJSON.'
  on :n, :network_nodes, 'Busca nós da rede mais próximos das cidades.'
  
  # on 'p', 'password', 'An optional password', argument: :optional
  # on 'v', 'verbose', 'Enable verbose mode'
end

if opts.import_cities? then
  import_cities_csv()
end

if opts.distances? then
  calculate_pairs_distances()
end

if opts.geodistances? then
  calculate_geo_distance
end

if opts.geojson? then
  generate_distances_geojson()
end

if opts.network_nodes? then
  update_nearest_nodes()
end



$db.close