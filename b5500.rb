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

def no_mais_proximo(lon, lat)
  
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


def atualiza_nos_proximos

  $db.execute("SELECT CreateSpatialIndex('roads_nodes', 'geometry');") rescue puts 'Spatial index already defined.';  

  puts "Updating cities' entry nodes in network:"
  # busca nó da rede mais próximo para cidades que tem coordenadas
  $db.execute( "select * from cities where lon != '' and lat != ''" ) do |city|

    # puts "Encontrando nó mais próximo para #{cidade['nome']} (#{cidade['uf']}):"
    lon = city["lon"].to_f
    lat = city["lat"].to_f
    $db.execute("update cities set node_id = ? where id = ?", no_mais_proximo(lon, lat), city['id'])
    print '.'
  end
  
  puts 'Done.'
  
end

def total_distance(node_a, node_b)
  
  sql = <<SQL
        select cost/1000 as distance from roads_net where nodefrom = #{node_a} and nodeto = #{node_b} limit 1
SQL

  row = $db.get_first_row(sql) 
  row['distance']
end


def calculate_distances
  
  # set algorithm and clear distances table
  sql = <<SQL
    update roads_net set Algorithm = 'A*';
    drop table if exists distances;
    create table distances (city_id_from integer, city_id_to integer, route_distance number, direct_distance number, connected boolean, tortuous boolean);
    select AddGeometryColumn('distances', 'geometry', 4326, 'LINESTRING', 'XY');
SQL
  $db.execute_batch(sql)
  
  # get capitals
  capitais = $db.execute( "select * from cities where capital = 'true' and lon != '' and lat != ''" ) 

  # find distances to other capitals 
  for i in 0..capitais.length-1
    puts "Calculando rotas a partir de #{capitais[i]['nome']} (#{capitais[i]['uf']})"
    for j in 0..capitais.length-1
      if i == j then 
        next
      end
      from_node_id  = capitais[i]['node_id']
      from_city_id  = capitais[i]['id']
      from_x        = capitais[i]['lon']
      from_y        = capitais[i]['lat']
      
      to_node_id       = capitais[j]['node_id']
      to_city_id  = capitais[j]['id']
      to_x        = capitais[j]['lon']
      to_y        = capitais[j]['lat']
      
      distance = total_distance(from_node_id, to_node_id)
      geometry_wkt = "LINESTRING(#{from_x} #{from_y}, #{to_x} #{to_y})"
            
      $db.execute("insert into distances values (?,?,?,'','','',GeomFromText(?))",from_city_id, to_city_id, distance, geometry_wkt)
      print " #{capitais[j]['nome']}: #{distance} km "
    end
    puts ""
  end
  
  # find straight distances between cities
  $db.execute("update distances set direct_distance = GLength(geometry)*100")

  # update sinuosity status
  $db.execute("update distances set tortuous = case when route_distance / direct_distance > 1.5 then 'yes' else 'no' end;")

  # update connection status
  $db.execute("update distances set connected = case when route_distance > 0 then 'yes' else 'no' end;")

  
end

def import_cities_csv

  # Import cities.csv
  sql = <<SQL
    drop table if exists cities_csv; 
    create virtual table cities_csv using VirtualText(cities.csv, UTF-8, 1, COMMA, DOUBLEQUOTE, ',');

    drop table if exists cities;   
    create table cities as select * from cities_csv;
    alter table cities add column node_id integer;

SQL
  $db.execute_batch( sql )
  
  # Find nearest nodes on network for each city
  atualiza_nos_proximos()
  
end

def generate_distances_geojson
    
  sql = <<SQL
    select 
      d.city_id_from,
      c1.nome, 
      c1.uf,
      d.city_id_to,
      c2.nome,
      c2.uf,
      connected,
      tortuous,
      route_distance,
      direct_distance,
      aswkt(geometry) as wkt 
    from distances  d 
    left join cities as c1 on d.city_id_from = c1.id 
    left join cities as c2 on d.city_id_to = c2.id ;
SQL
  geo_factory = RGeo::Geographic.spherical_factory(:srid => 4326)
  features = []
  $db.execute(sql) do |row|
    geometry = geo_factory.parse_wkt(row['wkt'])
    properties = { 
      "city_from_id"          => row[0],
      "city_from_name"        => row[1],
      "uf_from"               => row[2],
      "city_to_id"            => row[3],
      "city_to_name"          => row[4],
      "uf_to"                 => row[5],      
      "connected"             => row[6],
      "tortuous"              => row[7],
      "route_distance"        => row[8],
      "great_circle_distance" => row[9],
      "distance_ratio"  => row[8].to_f / row[9].to_f * 100
    }
    feature = RGeo::GeoJSON::Feature.new(geometry, nil ,properties)
    features << feature
  end
  features_collection = RGeo::GeoJSON::FeatureCollection.new(features)
  
  File.open("connections.geojson","w") do |f|
    f.write(RGeo::GeoJSON.encode(features_collection).to_json)
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
  
  # on 'p', 'password', 'An optional password', argument: :optional
  # on 'v', 'verbose', 'Enable verbose mode'
end

if opts.import_cities? then
  import_cities_csv()
end

if opts.distances? then
  calculate_distances()
end



generate_distances_geojson()

$db.close