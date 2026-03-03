require 'sequel'
require 'csv'
require 'optparse'

# ==========================================
# data setting
# ==========================================

params = ARGV.getopts("","genome_db:","tree_db:","output:")

genome_db_pn = params["genome_db"]#"../genomes.db"
tree_db_pn = params["tree_db"]#'/Volumes/Extreme SSD/APGNC/output/runs/20260220_03_dist2.0_up5_score0.8/intermediate/analysis-[5-2.0].sqlite' 

db = Sequel.sqlite(tree_db_pn)
db.execute("ATTACH DATABASE '#{genome_db_pn}' AS genome_db")

out_f = File.open(params["output"],"w")

analysis_results = db[:diamond_clusters]
.join(Sequel.qualify(:genome_db, :genome_taxonomy), Assembly_Accession: :genome_id)
.select(:cluster_id, :class)
.to_hash_groups(:cluster_id, :class)

out_f.puts %w(GCL_id class).to_csv#(col_sep:"\t")
analysis_results.each do |cluster, data|
  size = 
  contents = data.compact.tally.inject([]) do |cont, (key, count)|
    cont << [key, (count.to_f/data.size*100).round(1)]
  end
  contents = contents.sort_by(&:last).reverse.map{ it.join(" ") }
  out_f.puts [cluster, contents.join(":")].to_csv#(col_sep:"\t")
end

=begin
.group(:cluster_id)
.select(
:cluster_id,
Sequel.qualify(:genome_db, :genome_taxonomy)[:Organism],
Sequel.qualify(:genome_db, :genome_taxonomy)[:phylum]
).to_hash(:cluster_id)

.to_hash_groups(:cluster_id, Sequel.qualify(:genome_db, :genome_taxonomy)[:phylum])



=end