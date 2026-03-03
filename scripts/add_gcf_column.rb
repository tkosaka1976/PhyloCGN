require 'csv'
require 'optparse'

params = ARGV.getopts("","input:","output:")

INPUT_FILE  = params["input"]
OUTPUT_FILE = params["output"]
NEW_COLUMN  = "Assembly_Accession"

# CSVを読み込み（ヘッダーあり）
csv = CSV.read(INPUT_FILE, headers: true)

CSV.open(OUTPUT_FILE, "w") do |n_csv|

  n_csv << csv.headers + [NEW_COLUMN]

  csv.each do |row|
    seq_id = row["Sequence_ID"]
    match = seq_id.match(/^(GCF_\d+\.\d+)/)
    gcf_id = match ? match[1] : ""
    n_csv << row.fields + [gcf_id]
  end
end
