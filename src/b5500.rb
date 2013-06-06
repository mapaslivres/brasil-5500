#!/usr/bin/ruby

require 'rubygems'
gem 'activerecord'

require 'active_record'
require './models/city.rb'

# Conexão com o banco de dados
DB_SPEC = {
  :adapter  => 'spatialite',
  :database => 'b5500.db',
}
ActiveRecord::Base.establish_connection(DB_SPEC)
conn_ = ::ActiveRecord::Base.connection


if (not (ActiveRecord::Base.connection.table_exists? 'cities')) or (not (ActiveRecord::Base.connection.table_exists? 'pairs')) then
  `spatialite b5500.db < ./db/init.sql`
end

puts City.first.name