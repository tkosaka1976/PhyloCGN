require 'sequel'
require 'csv'
require 'optparse'

params = ARGV.getopts("","tree_clade:","gene_cluster:","db:")

FILE_RESULTS  = params["tree_clade"]
DB_FILE     = params["db"]
FILE_DIAMOND = params["gene_cluster"]

# ==========================================
# 設定
# ==========================================
#DB_FILE = "analysis.db"

# 入力ファイル名
#FILE_RESULTS = "cluster_result_with_gene_id.csv" # 系統樹側 (gene, gene_cluster_id)
#FILE_DIAMOND = "diamond_hits_clusters_gcf.csv"      # Diamond側 (Sequence_ID, Cluster_ID)

# DBへの接続 (なければ作成されます)
DB = Sequel.sqlite(DB_FILE)

puts "🚀 Initializing Database: #{DB_FILE}..."

# ==========================================
# 1. テーブル定義 (Schema Definition)
# ==========================================

# --- A. cluster_results テーブル ---
# 系統樹のクラスタ結果を格納
DB.create_table! :cluster_results do
  primary_key :id
  String  :represent_gene
  String  :gene
  Integer :gene_cluster_id
  
  # 結合(JOIN)を高速にするためのインデックス
  index :gene
  index :gene_cluster_id
end

# --- B. diamond_clusters テーブル ---
# Diamondのクラスタ結果を格納
DB.create_table! :diamond_clusters do
  primary_key :id
  String  :sequence_id
  Integer :clade_id
  String  :color_hex
  Float   :diameter
  String  :assembly_accession
  
  # 結合(JOIN)を高速にするためのインデックス
  index :sequence_id
  index :clade_id
end

# ==========================================
# 2. データインポート処理
# ==========================================

# 汎用インポート用メソッド
def import_csv(db, table_name, file_path)
  puts "📂 Reading #{file_path}..."
  
  rows = []
  
  # CSV読み込み
  CSV.foreach(file_path, headers: true) do |row|
    # 行データをハッシュに変換して格納
    # ※ Sequelはカラム名(シンボル)と値のハッシュを渡すとよしなに処理してくれます
    
    data = {}
    
    if table_name == :cluster_results
      # カラムマッピング: CSVヘッダー -> DBカラム
      data[:represent_gene]  = row["represent_gene"]
      data[:gene]            = row["gene"]
      data[:gene_cluster_id] = row["gene_cluster_id"].to_i
      
    elsif table_name == :diamond_clusters
      # カラムマッピング
      data[:sequence_id]      = row["Sequence_ID"]
      data[:clade_id]       = row["Clade_ID"].to_i
      data[:color_hex]        = row["Color_Hex"]
      data[:diameter]         = row["Clade_AvgPairDist"].to_f
      data[:assembly_accession] = row["Assembly_Accession"]
    end
    
    rows << data
    
    # メモリ節約のため、1000行ごとに書き込み (バッチ処理)
    if rows.size >= 1000
      db[table_name].multi_insert(rows)
      rows.clear
    end
  end
  
  # 残りの行を書き込み
  db[table_name].multi_insert(rows) unless rows.empty?
  puts "   -> Imported into :#{table_name}"
end

# ==========================================
# 実行
# ==========================================
DB.transaction do
  import_csv(DB, :cluster_results, FILE_RESULTS)
  import_csv(DB, :diamond_clusters, FILE_DIAMOND)
end

puts "✅ Done! Database is ready."