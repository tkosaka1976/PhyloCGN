require 'csv'
require 'optparse'


params = ARGV.getopts("","input:","output:")

in_fn = params["input"]
# Representative_ID	Cluster_Size	gene_cluster_id


ids = Hash.new
CSV.foreach(in_fn,headers:true) do |row|
  row["Representative_ID"] =~ /(GCF\_\d{9}\.\d)\_([YWN]P\_\d{6,9}\.\d)/
  ids[$2] = $1
end

out_f = File.open(params["output"],"w")
out_f.puts %w(cluster_id protein_accession product).to_csv
ids.compact!

ids.each_with_index do |(gene,genome),i|
  gff_path = "./downloads/ncbi_dataset/data/#{genome}/genomic.gff"
  File.foreach(gff_path) do |line|
    next if line.start_with?("#")
    if line.include? gene
      line =~ /;product=(.+?);/
      out_f.puts [i+1, gene, $1].to_csv
      break
    end
  end
end