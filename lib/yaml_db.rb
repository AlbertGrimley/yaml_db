require 'rubygems'
require 'yaml'
require 'active_record'
require 'serialization_helper'
require 'active_support/core_ext/kernel/reporting'
require 'rails/railtie'

module YamlDb
  module Helper
    def self.loader
      YamlDb::Load
    end

    def self.dumper
      YamlDb::Dump
    end

    def self.extension
      "yml"
    end
  end


  module Utils
    def self.chunk_records(records)
      yaml = [ records ].to_yaml
      yaml.sub!(/---\s\n|---\n/, '')
      yaml.sub!('- - -', '  - -')
      yaml
    end

  end

  class Dump < SerializationHelper::Dump

    def self.dump_table_columns(io, table)
      io.write("\n")
      io.write({ table => { 'columns' => table_column_names(table) } }.to_yaml)
    end

    def self.dump_table_records(io, table)
      table_record_header(io)

      column_names = table_column_names(table)

      each_table_page(table) do |records|
        rows = SerializationHelper::Utils.unhash_records(records, column_names)
        io.write(YamlDb::Utils.chunk_records(records))
      end
    end

    def self.table_record_header(io)
      io.write("  records: \n")
    end

  end

  class AssetDump < Dump

    def self.dump(io)
      before_table(io, "asset_libraries")
      dump_table(io, "asset_libraries")
      after_table(io, "asset_libraries")
    end

    def self.dump_table_records(io, table)
      table_record_header(io)

      column_names = table_column_names(table)

      each_table_page(table) do |records|
        records.each do |record|
          record["image_url"] = AssetLibrary.find(record["id"]).blog_asset.url
        end
        rows = SerializationHelper::Utils.unhash_records(records, column_names)
        io.write(YamlDb::Utils.chunk_records(records))
      end
    end

    def self.table_column_names(table)
      ActiveRecord::Base.connection.columns(table).map { |c| c.name }.concat(["image_url"])
    end

  end

  class Load < SerializationHelper::Load
    def self.load_documents(io, truncate = true)
      YAML.load_documents(io) do |ydoc|
        ydoc.keys.each do |table_name|
          next if ydoc[table_name].nil? || table_name == "asset_libraries"
          load_table(table_name, ydoc[table_name], truncate)
        end
      end
    end
  end

  class AssetLoad < Load
    def self.load_documents(io, truncate = true)
      YAML.load_documents(io) do |ydoc|
        ydoc.keys.each do |table_name|
          next unless table_name == "asset_libraries"
          load_table(table_name, ydoc[table_name], truncate)
        end
      end
    end

    def self.load_records(table, column_names, records)
      if column_names.nil?
        return
      end
      image_url_index = column_names.index("image_url")
      columns = column_names.map{|cn| cn == "image_url" ? nil : ActiveRecord::Base.connection.columns(table).detect{|c| c.name == cn}}.compact
      quoted_column_names = column_names.map { |column| column == "image_url" ? nil : ActiveRecord::Base.connection.quote_column_name(column) }.compact.join(',')
      quoted_table_name = SerializationHelper::Utils.quote_table(table)
      records.each do |record|
        quoted_values = record.zip(columns).map{|c| c.last.nil? ? nil : ActiveRecord::Base.connection.quote(c.first, c.last)}.compact.join(',')
        ActiveRecord::Base.connection.execute("INSERT INTO #{quoted_table_name} (#{quoted_column_names}) VALUES (#{quoted_values})")
        asset = AssetLibrary.find(record[0])
        asset.blog_asset = URI.parse(record[image_url_index])
        asset.save
      end
    end
  end

  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path('../tasks/yaml_db_tasks.rake',
__FILE__)
    end
  end

end
