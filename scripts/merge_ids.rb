require 'csv'
require 'optparse'

params = ARGV.getopts("","input:","output:","ref:")

TARGET_FILE  = params["input"]
ID_FILE     = params["ref"]
OUTPUT_FILE = params["output"]

# ==========================================
# 実行処理
# ==========================================
puts "Loading ID map from #{ID_FILE}..."

# 1. IDマップの作成
# Representative_ID => gene_cluster_id のハッシュを作成
id_map = {}
CSV.foreach(ID_FILE, headers: true) do |row|
  rep_id = row["Representative_ID"]
  gene_id = row["gene_cluster_id"]
  id_map[rep_id] = gene_id
end

puts " -> Loaded #{id_map.size} IDs."
puts "Processing #{TARGET_FILE} and writing to #{OUTPUT_FILE}..."

# 2. TSVを読み込み、ヘッダーを付けてCSV書き出し
CSV.open(OUTPUT_FILE, "w") do |csv_out|
  
  # ★ここでヘッダーを追加
  csv_out << ["represent_gene", "gene", "gene_cluster_id"]

  # TSVファイルを行ごとに読み込む (タブ区切り)
  CSV.foreach(TARGET_FILE, col_sep: "\t") do |row|
    # row は配列になっています (例: ["GCF_...", "Member_..."])
    
    # 一番左のカラム (row[0]) をキーとしてマップから検索
    key_id = row[0]
    found_gene_id = id_map[key_id]

    # TSVの元の列に gene_cluster_id を追加してCSVに書き込む
    csv_out << row + [found_gene_id]
  end
end

puts "✅ Done! Created: #{OUTPUT_FILE} with headers."