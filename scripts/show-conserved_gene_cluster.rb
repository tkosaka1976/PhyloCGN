require 'sequel'
require 'csv'
require 'optparse'

params = ARGV.getopts("","db:","score:","output:")


score_t = params["score"].to_f
input_db = params["db"]
output_fn = params["output"]

DB = Sequel.sqlite input_db

id2genomes = Hash.new{|h,k|h[k]=[]}

DB[:diamond_clusters].each do |recode|
  id2genomes[recode[:cluster_id]] << recode[:genome_id]
end

out_f = File.open(output_fn,"w")
out_f.puts %w(Clade_id GCL).to_csv

id2genomes.each do |id, genomes|
  data = DB[:cluster_results].where(genome_id: genomes).select_map(:gene_cluster_id)
  cgc = data.tally.select{|g_c_id, size| size.to_f / genomes.size >= score_t }.map(&:first).sort
  out_f.puts [id, cgc.join("|")].to_csv
end
