# Brasil 5500

Este projeto tem como objetivo garantir o mapeamento da conexão entre todas as cidades brasileiras.

Um script verifica se existe uma rota válida entre as cidades, e gera uma visualização das conexões corretas, tortuosas ou quebradas em um mapa.

## Criando a rede a partir dos dados do OpenStreetMap

O script utiliza a biblioteca [OSM Tools](https://www.gaia-gis.it/fossil/spatialite-tools/wiki?name=OSM+tools) do [Spatialite](http://www.gaia-gis.it/gaia-sins/) para calcular rotas. O Spatialite é uma extensão GIS para o banco de dados [SQLite](http://www.sqlite.org/).

Passos para a execução do script:

1. Baixe o arquivo [brazil-latest.pbf.osm](http://download.geofabrik.de/south-america/brazil-latest.osm.pbf) na área de [downloads](http://download.geofabrik.de) da [Geofabrik](http://www.geofabrik.de).

2. Gere o banco de dados Spatialite com a rede, utilizando o [spatialite_osm_net](https://www.gaia-gis.it/fossil/spatialite-tools/wiki?name=spatialite_osm_net):

      spatialite_osm_net -o ~/data/brazil-latest.osm.pbf -d brasil.sqlite -T roads
      
3. Abra o arquivo resultante no spatialite_gui e construa a rede:

4. Rode o script para gerar os resultados:

spatialite brasil.sqlite < cidades.sql

SELECT node_id, osm_id, geometry, distance(PointFromText("POINT(-46.6375468 -23.5561782)"), geometry) as distance from roads_nodes order by distance limit 1;