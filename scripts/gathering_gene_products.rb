require 'csv'
require 'optparse'


params = ARGV.getopts("","input:","output:","downloads_d:")

ids = Hash.new
CSV.foreach(params["input"], headers:true) do |row|
  row["Representative_ID"] =~ /(GCF\_\d{9}\.\d)\_([YWN]P\_\d{6,9}\.\d)/
  ids[$2] = $1
end

out_f = File.open(params["output"],"w")
out_f.puts %w(gene_cluster_id protein_accession product).to_csv
ids.compact!

ids.each_with_index do |(gene,genome),i|
  gff_path = File.join(params["downloads_d"],"ncbi_dataset","data",genome,"genomic.gff")
  File.foreach(gff_path) do |line|
    next if line.start_with?("#")
    if line.include? gene
      line =~ /;product=(.+?);/
      out_f.puts [i+1, gene, $1].to_csv
      break
    end
  end
end