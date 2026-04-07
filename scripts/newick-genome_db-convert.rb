require 'sequel'
require 'optparse'

params = ARGV.getopts("","input:","db:","output:")

in_fn = params["input"]#"fdhB-diamond_hits.tree"
ref_db = params["db"]#"genomes.db"
out_fn = params["output"]#"#{File.basename(in_fn,".tree")}-converted.tree"

DB = Sequel.sqlite(ref_db)
accession_to_organism = DB[:genome_taxonomy].select_hash(:Assembly_Accession, :Organism)

newick_str = File.read(in_fn)

replaced = newick_str.gsub(/([^(),;:\s]+)/) do |node|
  next node if node.match?(/\A[\d.eE+\-]+\z/)
  
  m = node.match(/\A(.+?)_(WP_|XP_|NP_|YP_)(.+)\z/)
  next node unless m

  protein_id = "#{m[2]}#{m[3]}"
  organism   = accession_to_organism[m[1]]

  if organism
    clean_organism = organism.strip.gsub(/\s*\(.*?\)\s*/, ' ').strip.gsub(/\s+/, '_')
    "#{clean_organism}_#{protein_id}"
  else
    node
  end
  
end

File.open(out_fn, "w") { it.puts replaced }
