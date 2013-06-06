--
-- init.sql
-- 
-- Initialize database by creating tables and importing cities info

-- enable geospatial features
SELECT InitSpatialMetaData();

-- open cities.csv
drop table if exists cities_csv; 
create virtual table cities_csv using VirtualText(
  '../data/cities.csv', 
  UTF-8, 1, 
  COMMA, 
  DOUBLEQUOTE, 
  ','
);

-- initialize cities table from csv
drop table if exists cities;   
create table cities as select * from cities_csv;
  
-- add needed columns to cities table
alter table cities add column node_id integer;
select AddGeometryColumn('cities', 'geometry', 4326, 'POINT', 'XY');
select CreateSpatialIndex('cities', 'geometry');
update cities set geometry = makepoint(cast(lon as real), cast(lat as real), 4326) where lat != '' and lon != '';

-- drop csv
drop table cities_csv; 

-- create pairs table
create table if not exists pairs (
  a_id integer, 
  b_id integer, 
  ab_route_length number, 
  ba_route_length number,
  ab_distance number, 
  ab_connected boolean, 
  ba_connected boolean, 
  ab_tortuous boolean, 
  ba_tortuous boolean
);
select AddGeometryColumn('pairs', 'geometry', 4326, 'LINESTRING', 'XY');

