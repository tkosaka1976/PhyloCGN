require 'sequel'
require 'optparse'

params = ARGV.getopts("","tree_clade:","gene_cluster:","db:")


# ==========================================
# 設定
# ==========================================

# 正規表現 
REGEX_PATTERN = /^(GCF_[\d\.]+)_+([A-Z]{2}_[\d\.]+)$/

# ==========================================
# 実行
# ==========================================
DB = Sequel.sqlite params["db"]

DB.tables.each do |table|

  begin
    DB.alter_table(table) do
      add_column :genome_id, String
      add_column :protein_id, String
    
      add_index :genome_id
      add_index :protein_id
    end
  rescue Sequel::DatabaseError => e
    puts "   (Columns might already exist or error: #{e.message})"
  end



  # 2. データの更新
  # ------------------------------------------
  puts "Updating rows based on 'gene' column..."
  
  target_table = DB[table]
  count = 0
  updated = 0

  DB.transaction do
    target_table.each do |row|
      original_id = row[:gene] if table == :cluster_results
      original_id = row[:sequence_id] if table == :diamond_clusters
    
      if original_id && (match = original_id.match(REGEX_PATTERN))
        genome_part = match[1]  # GCF_...
        protein_part = match[2] # WP_...
      
        # ID指定で更新
        target_table.where(id: row[:id]).update(
        genome_id: genome_part,
        protein_id: protein_part
        )
        updated += 1
      end
    
      count += 1
      if count % 1000 == 0
        print "\rProcessed: #{count} | Updated: #{updated}"
      end
    end
  end

  puts "\n✅ Done! Updated #{updated} / #{count} rows."

  # 3. 確認用
  # ------------------------------------------
  puts "\n--- Sample Data (cluster_results) ---"
  target_table.limit(5).each do |row|
    puts "Gene    : #{row[:gene]}"
    puts " -> Gen : #{row[:genome_id]}"
    puts " -> Pro : #{row[:protein_id]}"
    puts "-" * 30
  end

end
