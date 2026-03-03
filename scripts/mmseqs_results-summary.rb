require 'csv'
require 'optparse'

params = ARGV.getopts("","input:","output:")

input_file  = params["input"]
output_file = params["output"]


cluster_counts = Hash.new(0)
CSV::TSV.foreach(input_file) do |row|
  rep_id = row[0]
  next if rep_id.nil? || rep_id.empty?
  cluster_counts[rep_id] += 1
end

sorted_clusters = cluster_counts.sort_by { |k, v| -v }

CSV.open(output_file, "w") do |csv|
  csv << %w"Representative_ID Cluster_Size gene_cluster_id"

  sorted_clusters.each_with_index do |(rep_id, size), i|
    csv << [rep_id, size, i+1]
  end
end
