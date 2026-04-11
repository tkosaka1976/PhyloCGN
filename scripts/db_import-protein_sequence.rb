require 'sequel'
require 'open3'
require 'optparse'


params = ARGV.getopts("","db:","table:","download_d:")

DB = Sequel.sqlite params["db"]
table_n = params["table"].to_sym

begin
  DB.alter_table(table_n) do
    add_column :sequence, String
  end
rescue Sequel::DatabaseError => e
  puts "(Columns might already exist or error: #{e.message})"
end

data_h = DB[table_n].as_hash(:protein_id, :genome_id)

data_h.each do |protein_id, genome_id|
  
  target = File.join(params["download_d"],"ncbi_dataset", "data", genome_id, "protein.faa")
  data = Open3.capture3("seqkit grep -p #{protein_id} #{target} | seqkit seq -s -w 0")
  DB[table_n].where(protein_id: protein_id).update(sequence: data.first.chomp)
    
end
