require 'sequel'
require 'csv'
require 'optparse'

params = ARGV.getopts("","genome_db:","tree_db:","output:","taxonomy:")

genome_db_pn = params["genome_db"]
tree_db_pn = params["tree_db"]
taxonomy = params["taxonomy"]&.to_sym || :class

db = Sequel.sqlite(tree_db_pn)
db.execute("ATTACH DATABASE '#{genome_db_pn}' AS genome_db")

out_f = File.open(params["output"],"w")

analysis_results = db[:diamond_clusters]
.join(Sequel.qualify(:genome_db, :genome_taxonomy), Assembly_Accession: :genome_id)
.select(:clade_id, taxonomy)
.to_hash_groups(:clade_id, taxonomy)

out_f.puts %w(Clade_id gene_number taxonomy_prop).to_csv
analysis_results.each do |cluster, data|
  contents = data.compact.tally.inject([]) do |cont, (key, count)|
    cont << [key, (count.to_f/data.size*100).round(1)]
  end
  contents = contents.sort_by(&:last).reverse.map{ it.join(" ") }
  out_f.puts [cluster, data.size, contents.join(":")].to_csv
end
