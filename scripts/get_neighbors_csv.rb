require 'csv'
require 'optparse'


params = ARGV.getopts('', "input:", "data_d:", "output:", "updown:5")

# 設定
TARGET_LIST = params["input"]
DATA_DIR    = params["data_d"]
UP_DOWN     = params["updown"].to_i

# 出力CSVのヘッダー
headers = %w[
  Combined_ID
  Genome_ID
  Accession
  Target_Original
  Distance_from_Target
  Strand
  Start
  End
  Product
]

# CSVを標準出力へ
csv_out = CSV.open(params["output"], "w", headers: headers, write_headers: true)

# 1. ターゲットリスト読み込み
targets_by_genome = Hash.new { |h, k| h[k] = [] }
File.foreach(TARGET_LIST) do |line|
  line.chomp!
  next if line.empty?
  if line =~ /^(GCF_[\d\.]+)[_\t](.+)$/
    targets_by_genome[$1] << $2
  end
end

# 2. GFF処理
targets_by_genome.each do |genome, target_ids|
  gff_path = File.join(DATA_DIR, genome, "genomic.gff")
  next unless File.exist?(gff_path)

  cds_data = []
  File.foreach(gff_path) do |line|
    next if line.start_with?("#")
    cols = line.chomp.split("\t")
    if cols[2] == "CDS"
      attrs = cols[8]
      name = if attrs =~ /Name=([^;]+)/; $1
             elsif attrs =~ /protein_id=([^;]+)/; $1
             else; nil; end
      product = attrs =~ /product=([^;]+)/ ? $1 : "hypothetical protein"
      
      if name
        cds_data << {
          name: name,
          start: cols[3].to_i,
          end: cols[4].to_i,
          strand: cols[6],
          product: product
        }
      end
    end
  end

  cds_data.sort_by! { |cds| cds[:start] }

  target_ids.each do |target|
    idx = cds_data.index { |cds| cds[:name] == target }
    if idx
      start_i = [0, idx - UP_DOWN].max
      end_i   = [cds_data.size - 1, idx + UP_DOWN].min
      
      (start_i..end_i).each do |i|
        cds = cds_data[i]
        dist = i - idx
        
        # 以前作った all_methanogens_proteins.faa のヘッダー形式に合わせる
        # 形式: GCF_xxxxx_WP_xxxxx
        combined_id = "#{genome}_#{cds[:name]}"

        csv_out << [
          combined_id,
          genome,
          cds[:name],
          target,
          dist,
          cds[:strand],
          cds[:start],
          cds[:end],
          cds[:product]
        ]
      end
    end
  end
end
