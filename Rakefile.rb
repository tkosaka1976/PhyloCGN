require 'rake/clean'
require 'shellwords'
require 'fileutils'
require 'csv'
require 'yaml'

# =============================================================================
# 設定セクション（ここを編集してパラメータ調整）
# =============================================================================

VERSION = "0.9.1"

CONFIG = {
  
  # 入力ファイル
  files: {
    query_protein: "",
    accessions: "accessions.txt",
    bacteria_accessions: "bacteria_accessions.txt",
    archaea_accessions: "archaea_accessions.txt"
  },
  
  # ディレクトリ構成
  dirs: {
    input: "input",
    output: "output",
    downloads: "downloads",
    shared_resources: "shared_resources"
  },
  
  # クラスタリングとゲノム近傍解析のパラメータ
  # ★変更点: ENV['XXX'] があればそれを優先
  tree_distance_threshold: ENV['DIST'] ? ENV['DIST'].to_f : 2.0,
  neighborhood_updown_size: ENV['UPDOWN'] ? ENV['UPDOWN'].to_f : 10,
  neighborhood_conservation_score: ENV['SCORE'] ? ENV['SCORE'].to_f : 0.9,
  
  # 再実行設定
  reuse: {
    enabled: false,
    source_run: "",
    skip_tasks: [
      :download_genomes, 
      :homologs_search, 
      
      :make_tree,
      #:tree_clustering,
      #
      #:gathering_genomic_neiborhood,
      #:clustering_genomic_neiborhood,
      #
      #:make_gene_cluster_db,
      #:gene_cluster_db_analysis,
    ]
  },
    
  # Diamond検索パラメータ
  diamond: {
    subject_size: 0, # 0: infinity
    block: 0.7,
    evalue: 1e-10,
    coverage: 80,
    identity: 35,
    sensitivity: "very-sensitive"
  },
  
  # mmseqs
  mmseqs:{
    cluster_mode: 1,
    sensitivity: 7.5,
    identity: 0.3,
    coverage: 0.6,
  },

  # ダウンロード設定
  download: {
    retry_wait: 0.5,
    http2_disabled: true
  },
  
  # ツール固有設定
  tools: {
    veryfasttree: {
      model: "lg",
      gamma: true,
      spr: 4,
      threads: 2
    },
    muscle_version: "5",
    muscle: {
      super5_threshold: 1000
    }
  },
  
  # API設定
  ncbi_api_key: ENV['NCBI_API_KEY'],
  
  # ファイル管理設定
  file_management: {
    keep_intermediate: true,
    cleanup_temp_on_success: true
  },
  
}#.freeze

raise "NCBI_API_KEY is not set" unless CONFIG[:ncbi_api_key]

# =============================================================================
# パス管理・ログ・再利用モジュール
# =============================================================================

# 再実行管理モジュール
module ReuseManager
  class << self
    def enabled?
      CONFIG[:reuse][:enabled] && CONFIG[:reuse][:source_run]
    end
    
    def source_run_dir
      return nil unless enabled?
      File.join(CONFIG[:dirs][:output], "runs", CONFIG[:reuse][:source_run])
    end
    
    def validate_source!
      return unless enabled?
      
      unless Dir.exist?(source_run_dir)
        raise "再利用元が見つかりません: #{CONFIG[:reuse][:source_run]}\n" \
              "利用可能な実行を確認: rake list_runs"
      end
      
      Logger.info("再利用モード有効: #{CONFIG[:reuse][:source_run]}")
    end
    
    # 指定されたファイルが再利用元に存在するかチェック
    def file_exists?(relative_path)
      return false unless enabled?
      File.exist?(File.join(source_run_dir, relative_path))
    end
    
    # ファイルをコピー
    def copy_file(relative_path, dest_path)
      src = File.join(source_run_dir, relative_path)
      
      if File.exist?(src)
        FileUtils.mkdir_p(File.dirname(dest_path))
        FileUtils.cp(src, dest_path)
        Logger.info("  ✓ #{File.basename(relative_path)} を再利用")
        true
      else
        Logger.error("  ✗ #{relative_path} が見つかりません")
        false
      end
    end
    
    # タスクをスキップすべきか判定
    def should_skip_task?(task_name)
      enabled? && CONFIG[:reuse][:skip_tasks].include?(task_name)
    end
  end
end

# 実行管理モジュール
module RunManager
  class << self
    def current_run_dir
      @current_run_dir ||= create_run_directory
    end
    
    def create_run_directory
      date_str = Time.now.strftime("%Y%m%d")

      runs_base = File.join(CONFIG[:dirs][:output], "runs")
      FileUtils.mkdir_p(runs_base) unless Dir.exist?(runs_base)

      counter = 1
      dir_name = nil
      run_dir = nil
      loop do
          suffix = sprintf("_%03d", counter)
          dir_name = "#{date_str}#{suffix}"  # ← シンプルに
          run_dir = File.join(runs_base, dir_name)
          break unless Dir.exist?(run_dir)
          counter += 1
      end
      
      # ディレクトリ作成
      Logger.info("実行ディレクトリを作成中: #{dir_name}")
      FileUtils.mkdir_p(run_dir)
      
      # サブディレクトリ作成
      subdirs = ["results", "intermediate", "temp"]
      subdirs.each do |subdir|
        path = File.join(run_dir, subdir)
        FileUtils.mkdir_p(path)
        Logger.info("  ✓ #{subdir}/")
      end
      
      # パラメータ情報を保存
      save_run_params(run_dir)
      
      # latestシンボリックリンクを更新
      update_latest_link(run_dir)
      
      # 実行履歴に追加
      append_to_summary(dir_name)
      
      Logger.success("実行ディレクトリ準備完了: #{File.basename(run_dir)}")
      
      run_dir
    end
    
    def save_run_params(run_dir)
      # YAML形式で保存
      params_file = File.join(run_dir, "run_params.yml")
      params_data = {
        timestamp: Time.now.iso8601,
        config: CONFIG.dup,
        ruby_version: RUBY_VERSION,
        git_commit: `git rev-parse HEAD 2>/dev/null`.chomp,
        hostname: `hostname`.chomp
      }
      
      File.open(params_file, "w") do |f|
        f.write(params_data.to_yaml)
      end
      
      # 人間が読みやすいテキスト版
      readme = File.join(run_dir, "README.txt")
      File.open(readme, "w") do |f|
        f.puts "=" * 70
        f.puts "解析実行パラメータ"
        f.puts "=" * 70
        f.puts "実行日時: #{params_data[:timestamp]}"
        f.puts "ホスト: #{params_data[:hostname]}"
        f.puts ""
        
        if ReuseManager.enabled?
          f.puts "【再利用設定】"
          f.puts "  再利用元: #{CONFIG[:reuse][:source_run]}"
          f.puts "  スキップタスク: #{CONFIG[:reuse][:skip_tasks].join(', ')}"
          f.puts ""
        end
        
        f.puts "【クエリ】"
        f.puts "  タンパク質: #{CONFIG[:files][:query_protein]}"
        f.puts ""
        
        f.puts "【Diamond検索】"
        f.puts "  E-value閾値: #{CONFIG[:diamond][:evalue]}"
        f.puts "  Identity: #{CONFIG[:diamond][:identity]}%"
        f.puts "  Coverage: #{CONFIG[:diamond][:coverage]}%"
        f.puts ""
        
        f.puts "【クラスタリング】"
        f.puts "  系統樹距離閾値: #{CONFIG[:tree_distance_threshold]}"
        f.puts "  MMseqs2 evalue: #{CONFIG[:mmseqs][:evalue]}"
        f.puts "  MMseqs2 Coverage: #{CONFIG[:mmseqs][:coverage]}"
        f.puts ""
        
        f.puts "【ゲノム近傍解析】"
        f.puts "  上下流遺伝子数: #{CONFIG[:neighborhood_updown_size]}"
        f.puts "  保存度スコア: #{CONFIG[:neighborhood_conservation_score]}"
        f.puts ""
        
        f.puts "【Muscle設定】"
        f.puts "  Super5モード閾値: #{CONFIG[:tools][:muscle][:super5_threshold]}配列"
        f.puts ""
      end
    end
    
    def update_latest_link(run_dir)
      latest_link = File.join(CONFIG[:dirs][:output], "latest")
      
      # Windowsの場合はシンボリックリンク作成をスキップ
      return if Gem.win_platform?
      
      File.delete(latest_link) if File.symlink?(latest_link) || File.exist?(latest_link)
      
      # 相対パスでシンボリックリンクを作成
      relative_path = File.join("runs", File.basename(run_dir))
      File.symlink(relative_path, latest_link)
    end
    
    def append_to_summary(dir_name)
      summary_file = File.join(CONFIG[:dirs][:output], "runs_summary.csv")
      
      # 親ディレクトリを作成
      FileUtils.mkdir_p(File.dirname(summary_file)) unless Dir.exist?(File.dirname(summary_file))
      
      unless File.exist?(summary_file)
        File.open(summary_file, "w") do |f|
          f.puts "timestamp,run_directory,tree_distance,updown_size,conservation_score,diamond_evalue,diamond_identity,reused_from,status"
        end
      end
      
      reused_from = ReuseManager.enabled? ? CONFIG[:reuse][:source_run] : ""
      
      File.open(summary_file, "a") do |f|
        f.puts [
          Time.now.iso8601,
          dir_name,
          CONFIG[:tree_distance_threshold],
          CONFIG[:neighborhood_updown_size],
          CONFIG[:neighborhood_conservation_score],
          CONFIG[:diamond][:evalue],
          CONFIG[:diamond][:identity],
          reused_from,
          "running"
        ].join(",")
      end
    end
    
    def mark_completed
      update_status("completed")
      cleanup_temp_files if CONFIG[:file_management][:cleanup_temp_on_success]
    end
    
    def mark_failed(error_message)
      update_status("failed: #{error_message}")
    end
    
    def cleanup_temp_files
      temp_dir = File.join(current_run_dir, "temp")
      if Dir.exist?(temp_dir)
        FileUtils.rm_rf(temp_dir)
        Logger.info("一時ファイルを削除しました")
      end
    end
    
    def cleanup_intermediate_files
      intermediate_dir = File.join(current_run_dir, "intermediate")
      if Dir.exist?(intermediate_dir)
        FileUtils.rm_rf(intermediate_dir)
        Logger.info("中間ファイルを削除しました")
      end
    end
    
    # 既存のディレクトリを強制的にセットするメソッド（再解析用）
    def set_existing_run_dir(path)
      unless Dir.exist?(path)
        raise "指定されたディレクトリが存在しません: #{path}"
      end
      @current_run_dir = path
      Logger.info("実行ディレクトリを固定: #{@current_run_dir}")
    end
    
    private
    
    def update_status(status)
      summary_file = File.join(CONFIG[:dirs][:output], "runs_summary.csv")
      return unless File.exist?(summary_file)
      
      # 単純なテキスト置換（最後の行の running を書き換える）
      lines = File.readlines(summary_file)
      if lines.last&.include?("running")
        lines[-1] = lines[-1].gsub("running", status)
        File.write(summary_file, lines.join)
      end
    end
  end
end

# パス生成ヘルパー
module Paths
  class << self
    # 現在の実行用出力パス（最終結果）
    def output(filename)
      dir = File.join(RunManager.current_run_dir, "results")
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      File.join(dir, filename)
    end
    
    # 中間ファイル用パス
    def intermediate(filename)
      dir = File.join(RunManager.current_run_dir, "intermediate")
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      File.join(dir, filename)
    end
    
    # 共有リソース用パス（全実行で共通）
    def shared(filename)
      dir = CONFIG[:dirs][:shared_resources]
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      File.join(dir, filename)
    end
    
    def input(filename)
      File.join(CONFIG[:dirs][:input], filename)
    end
    
    def downloads(*parts)
      File.join(CONFIG[:dirs][:downloads], *parts)
    end
    
    # 最新の実行結果へのパス
    def latest(filename)
      File.join(CONFIG[:dirs][:output], "latest", "results", filename)
    end
    
    # 一時ファイル用（実行後削除される）
    def temp(filename)
      temp_dir = File.join(RunManager.current_run_dir, "temp")
      FileUtils.mkdir_p(temp_dir) unless Dir.exist?(temp_dir)
      File.join(temp_dir, filename)
    end
  end
end

# ログ出力ヘルパー
module Logger
  def self.step(message)
    puts "\n" + "=" * 70
    puts "▶ #{message}"
    puts "=" * 70
  end
  
  def self.info(message)
    puts "  ℹ #{message}"
  end
  
  def self.success(message)
    puts "  ✅ #{message}"
  end
  
  def self.error(message)
    puts "  ❌ #{message}"
  end
  
  def self.progress(current, total, item)
    percentage = (current.to_f / total * 100).round(1)
    puts "  [#{current}/#{total}] (#{percentage}%) #{item}"
  end
end

# =============================================================================
# メインタスク
# =============================================================================

desc "ゲノムデータをNCBI ftpよりダウンロード。error_list.txt に何か残っていたら、再実行。"
task :download_genomes do
  Logger.step("ゲノムデータダウンロード")
  
  puts "Fetching list from FTP..."

  unless File.exist? CONFIG[:files][:bacteria_accessions]
    sh "curl -s https://ftp.ncbi.nlm.nih.gov/genomes/refseq/bacteria/assembly_summary.txt |\
    awk -F \"\t\" '$5==\"reference genome\" && $12==\"Complete Genome\" {print $1}' \
    > #{CONFIG[:files][:bacteria_accessions]}"
  end
  
  unless File.exist? CONFIG[:files][:archaea_accessions]
    sh "curl -s https://ftp.ncbi.nlm.nih.gov/genomes/refseq/archaea/assembly_summary.txt |\
    awk -F \"\t\" '$5==\"reference genome\" && $12==\"Complete Genome\" {print $1}' \
    > #{CONFIG[:files][:archaea_accessions]}"
  end
  
  accessions_file = CONFIG[:files][:accessions]
  unless File.exist? accessions_file
    File.open(accessions_file,"w") { |it| it.write File.read(CONFIG[:files][:bacteria_accessions])}
    File.open(accessions_file,"a") { |it| it.write File.read(CONFIG[:files][:archaea_accessions])}
  end

  puts "Downloading dehydrated zip..."
  download_d = CONFIG[:dirs][:downloads]
  Dir.mkdir download_d unless Dir.exist? download_d
  
  lines = File.readlines(accessions_file, chomp: true)
  accessions = lines.map(&:strip).reject(&:empty?)

  Logger.info("全 #{accessions.size} 件の個別ダウンロードを開始")
  accessions.each_with_index do |acc, index|
    target_data_dir = Paths.downloads("ncbi_dataset", "data", acc)

    if Dir.exist?(target_data_dir) && !Dir.empty?(target_data_dir)
      Logger.progress(index + 1, accessions.size, "#{acc}: ✅ 完了済み (スキップ)")
      next
    end

    zip_path = Paths.downloads("#{acc}.zip")
    File.delete(zip_path) if File.exist?(zip_path)

    Logger.progress(index + 1, accessions.size, "#{acc}: ⬇️ ダウンロード開始")

    cmd = "datasets download genome accession #{acc} \
    --api-key #{CONFIG[:ncbi_api_key]} \
    --include protein,gff3 \
    --filename #{zip_path}"
    
    env = CONFIG[:download][:http2_disabled] ? {'GODEBUG' => 'http2client=0'} : {}
    
    if system(env, cmd)
      if system("unzip -q -o #{zip_path} -d #{CONFIG[:dirs][:downloads]}")
        File.delete(zip_path)
      else
        Logger.error("#{acc}: 解凍失敗")
        File.delete(zip_path)
      end
    else
      Logger.error("#{acc}: ダウンロード失敗")
      File.open("error_list.txt", "a") { |f| f.puts acc }
    end
    sleep CONFIG[:download][:retry_wait]
  end
  
  Logger.success("ダウンロード完了")
end


desc "queryのホモログをgenome dbよりdiamondで探す"
task :homologs_search do
  
  if ReuseManager.should_skip_task?(:homologs_search)
    Logger.step("ホモログ検索")
    Logger.info("再利用モード: #{CONFIG[:reuse][:source_run]} から結果を取得")
    
    # 過去の実行結果からコピーすべきファイル
    files_to_copy = {
      "results/diamond_results_full.tsv" => Paths.output('diamond_results_full.tsv'),
      "results/query_homolog_list.txt"   => Paths.output('query_homolog_list.txt')
    }
    
    all_copied = true
    files_to_copy.each do |src_relative, dest|
      unless ReuseManager.copy_file(src_relative, dest)
        all_copied = false
      end
    end
    
    if all_copied
      Logger.success("ホモログリスト作成完了（再利用）")
      next # ここでタスクを終了し、以降の重い処理をスキップ
    else
      Logger.error("一部のファイルが見つかりませんでした。通常モードで実行します")
    end
  end
  
  
  Logger.step("ホモログ検索")
  
  query = CONFIG[:files][:query_protein]
  
  # 共有リソース（全実行で使い回し）
  unless File.exist? Paths.shared("all_genome_proteins.faa")
    Logger.info("全ゲノムタンパク質ファイルを結合中...")
    faa = File.open(Paths.shared("all_genome_proteins.faa"),"w")
    Dir.glob(Paths.downloads("ncbi_dataset", "data", "**", "protein.faa")).each do |fp|
      /\/data\/(.+)\/protein\.faa/ =~ fp
      acc = $1
      File.foreach(fp) do |line|
        new_line = line.sub(/^>/, ">#{acc}_")
        faa.puts new_line
      end
    end
    faa.close
  end
  
  unless File.exist? Paths.shared("reference_genomes_db.dmnd")
    Logger.info("Diamondデータベース構築中...")
    sh "diamond makedb --in #{Paths.shared('all_genome_proteins.faa')} -d #{Paths.shared('reference_genomes_db')}"
  end
  
  Logger.info("Diamond検索実行中...")
  sh "diamond blastp \
  -k #{CONFIG[:diamond][:subject_size]} \
  -b #{CONFIG[:diamond][:block]} \
  -q #{Paths.input(query)} \
  -d #{Paths.shared('reference_genomes_db')} \
  -o #{Paths.output('diamond_results_full.tsv')} \
  -e #{CONFIG[:diamond][:evalue]} \
  --id #{CONFIG[:diamond][:identity]} \
  --subject-cover #{CONFIG[:diamond][:coverage]} \
  --query-cover #{CONFIG[:diamond][:coverage]} \
  --#{CONFIG[:diamond][:sensitivity]} \
  --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qcovhsp"
  
  Logger.info("結果フィルタリング中...")
  File.open(Paths.output("query_homolog_list.txt"),"w") do |f|
    CSV.foreach(Paths.output("diamond_results_full.tsv"), col_sep: "\t") do |row|
      if row[10].to_f <= CONFIG[:diamond][:evalue] && row[12].to_f > CONFIG[:diamond][:coverage]
        f.puts row[1]
      end
    end
  end
  
  Logger.success("ホモログリスト作成完了")
end

desc "MSAからのTree作成"
task :make_tree do
  Logger.step("系統樹作成")
  
  # 再利用モードチェック
  if ReuseManager.should_skip_task?(:make_tree)
    Logger.info("再利用モード: #{CONFIG[:reuse][:source_run]} から結果を取得")
    
    # 必要なファイルをコピー
    files_to_copy = {
      "intermediate/diamond_hits.fasta" => Paths.intermediate('diamond_hits.fasta'),
      "intermediate/diamond_hits.afa" => Paths.intermediate('diamond_hits.afa'),
      "results/diamond_hits.tree" => Paths.output('diamond_hits.tree')
    }
    
    all_copied = true
    files_to_copy.each do |src_relative, dest|
      unless ReuseManager.copy_file(src_relative, dest)
        all_copied = false
      end
    end
    
    if all_copied
      # 配列数を表示
      fasta_file = Paths.intermediate('diamond_hits.fasta')
      if File.exist?(fasta_file)
        sequence_count = `seqkit stats -T #{Shellwords.escape(fasta_file)} | tail -n 1 | cut -f 4`.strip.to_i
        Logger.info("配列数: #{sequence_count}")
      end
      
      Logger.success("系統樹作成完了（再利用）")
      next
    else
      Logger.error("一部のファイルが見つかりませんでした。通常モードで実行します")
    end
  end
  
  # 通常の処理
  Logger.info("配列抽出中...")
  sh "seqkit grep -f #{Paths.output('query_homolog_list.txt')} \
   #{Paths.shared('all_genome_proteins.faa')} \
   > #{Paths.intermediate('diamond_hits.fasta')}"
  
  # seqkitで配列数をカウント
  fasta_file = Paths.intermediate('diamond_hits.fasta')
  sequence_count = `seqkit stats -T #{Shellwords.escape(fasta_file)} | tail -n 1 | cut -f 4`.strip.to_i
  Logger.info("配列数: #{sequence_count}")
  
  # 閾値を超えている場合は-super5オプションを追加
  threshold = CONFIG[:tools][:muscle][:super5_threshold]
  muscle_opts = "-align"
  if sequence_count > threshold
    muscle_opts = "-super5"
    Logger.info("配列数が#{threshold}を超えているため、-super5オプションを使用します")
  else
    Logger.info("標準モードでアライメントを実行します")
  end
  
  Logger.info("マルチプルアライメント実行中...")
  sh "muscle#{CONFIG[:tools][:muscle_version]} \
  #{muscle_opts} #{Paths.intermediate('diamond_hits.fasta')} \
  -output #{Paths.intermediate('diamond_hits.afa')}"
  
  Logger.info("系統樹構築中...")
  tree_opts = CONFIG[:tools][:veryfasttree]
  gamma_flag = tree_opts[:gamma] ? "-gamma" : ""
  sh "VeryFastTree \
  -#{tree_opts[:model]} #{gamma_flag} -spr #{tree_opts[:spr]} -threads #{tree_opts[:threads]} \
  #{Paths.intermediate('diamond_hits.afa')} \
  > #{Paths.output('diamond_hits.tree')}"
  
  Logger.success("系統樹作成完了")
end

desc "系統樹の閾値調整 (使用法: rake tree_analysis [DIR=フォルダ名])"
task :tree_analysis do
  # 1. ターゲットとなるRunディレクトリを決定
  #    (A) 引数で DIR=... が指定されていればそれを使う
  #    (B) 指定がなければ latest (最新の実行結果) を使う
  if ENV['DIR']
    # 特定の過去ログを指定する場合
    target_dir = File.join(CONFIG[:dirs][:output], "runs", ENV['DIR'])
  elsif File.exist?(File.join(CONFIG[:dirs][:output], "latest"))
    # 指定がない場合は最新のリンク先を使う
    target_dir = File.join(CONFIG[:dirs][:output], "latest")
  else
    Logger.error("解析対象のディレクトリが見つかりません。")
    exit 1
  end

  # 2. ファイルパスを構築 (resultsフォルダ内にあると仮定)
  tree_file = File.join(target_dir, "results", "diamond_hits.tree")

  # 3. ファイルの存在確認
  unless File.exist?(tree_file)
    Logger.error("Treeファイルが見つかりません: #{tree_file}")
    Logger.info("ヒント: 正しいフォルダ名を指定してください")
    Logger.info("例: rake tree_analysis DIR=20260212_001_dist7.5_...")
    exit 1
  end

  Logger.info("解析対象: #{tree_file}")
  Logger.step("閾値調整スクリプトを実行")

  # 4. スクリプト実行
  sh "ruby scripts/tune_threshold.rb #{tree_file}"
end

task :tree_clustering do
  # 再利用モードチェック
  if ReuseManager.should_skip_task?(:tree_clustering)
    Logger.step("系統樹クラスタリング")
    Logger.info("再利用モード: #{CONFIG[:reuse][:source_run]} から結果を取得")
    
    files_to_copy = {
      "results/diamond_hits_cut.csv" => 
        Paths.output("diamond_hits_cut.csv"),
      "results/diamond_hits_cut_genomeid.csv" => 
        Paths.output("diamond_hits_cut_genomeid.csv")
    }
    
    all_copied = true
    files_to_copy.each do |src_relative, dest|
      unless ReuseManager.copy_file(src_relative, dest)
        all_copied = false
      end
    end
    
    if all_copied
      Logger.success("クラスタリング完了（再利用）")
      next
    else
      Logger.error("一部のファイルが見つかりませんでした。通常モードで実行します")
    end
  end
  
  # 通常の処理
  Logger.step("系統樹クラスタリング")
  
  threshold = CONFIG[:tree_distance_threshold]
  
  sh "ruby #{Shellwords.shellescape('scripts/treeclustering2json&csv.rb')} \
  --threshold #{threshold} \
  --input #{Paths.output('diamond_hits.tree')} \
  --output #{Paths.output('diamond_hits')}"
  
  sh "ruby scripts/add_gcf_column.rb \
  --input #{Paths.output("diamond_hits_cut.csv")} \
  --output #{Paths.output("diamond_hits_cut_genomeid.csv")}"
  
  sh "ruby scripts/treetrim.rb \
  --input #{Paths.output("diamond_hits_cut.json")} \
  --output #{Paths.output("diamond_hits_cut_trim.json")}"
  
  sh "ruby scripts/json2newick.rb \
  --input #{Paths.output("diamond_hits_cut_trim.json")} \
  --output #{Paths.output("diamond_hits_cut_trim.tree")}"
  
  Logger.success("クラスタリング完了")
end


desc "近傍遺伝子を集める"
task :gathering_genomic_neiborhood do
  Logger.step("ゲノム近傍遺伝子収集")
  
  updown = CONFIG[:neighborhood_updown_size]
  
  sh "ruby scripts/get_neighbors_csv.rb \
  --updown #{updown} \
  --input #{Paths.output('query_homolog_list.txt')} \
  --data_d #{Paths.downloads('ncbi_dataset', 'data')} \
  --output #{Paths.output("neighborhoods_metadata.csv")}"
  
  sh "ruby scripts/CSV-save_target_col.rb \
  #{Paths.output("neighborhoods_metadata.csv")} \
  Combined_ID \
  #{Paths.intermediate("neighborhoods_list.txt")}"
  
  sh "seqkit grep -f #{Paths.intermediate("neighborhoods_list.txt")} \
   #{Paths.shared('all_genome_proteins.faa')} \
   > #{Paths.intermediate("neighborhoods_list.mfasta")}"
  
  Logger.success("近傍遺伝子収集完了")
end

desc "genomic neiborhood のクラスター構築"
task :clustering_genomic_neiborhood do
  Logger.step("近傍遺伝子クラスタリング")
  
  sh "mmseqs easy-cluster \
  #{Paths.intermediate("neighborhoods_list.mfasta")} \
  #{Paths.intermediate("cluster_result")} \
  #{Paths.temp('mmseqs_tmp')} \
  -s #{CONFIG[:mmseqs][:sensitivity]} \
  -c #{CONFIG[:mmseqs][:coverage]} \
  --min-seq-id #{CONFIG[:mmseqs][:identity]} \
  --cluster-mode #{CONFIG[:mmseqs][:cluster_mode]} \
  --single-step-clustering \
  --cov-mode 0"
  
  sh "ruby scripts/mmseqs_results-summary.rb \
  --input #{Paths.intermediate("cluster_result_cluster.tsv")} \
  --output #{Paths.output("cluster_stat_cluster_id.csv")}"
  
  sh "ruby scripts/merge_ids.rb \
  --input #{Paths.intermediate("cluster_result_cluster.tsv")} \
  --ref #{Paths.output("cluster_stat_cluster_id.csv")} \
  --output #{Paths.output("cluster_result_gene_id.csv")}"

  sh "ruby scripts/gathering_gene_products.rb \
  --input #{Paths.output("cluster_stat_cluster_id.csv")} \
  --output #{Paths.output("cluster_representative_functions.csv")} \
  --downloads_d #{CONFIG[:dirs][:downloads]}"  
  
  Logger.success("クラスタリング完了")
end

task :make_gene_cluster_db do
  Logger.step("遺伝子クラスターデータベース構築")
  
  db_path = Paths.intermediate("analysis.sqlite")
  
  sh "ruby scripts/import_to_sqlite_sequel.rb \
  --db #{db_path} \
  --tree_clade #{Paths.output("cluster_result_gene_id.csv")} \
  --gene_cluster #{Paths.output("diamond_hits_cut_genomeid.csv")}"
  
  sh "ruby scripts/split_gene_ids_v2.rb \
  --db #{db_path}"
  
  Logger.success("データベース構築完了")
end

task :gene_cluster_db_analysis do
  Logger.step("保存遺伝子クラスター解析")
  
  score = CONFIG[:neighborhood_conservation_score]
  
  sh "ruby scripts/show-conserved_gene_cluster.rb \
  --score #{score} \
  --db #{Paths.intermediate("analysis.sqlite")} \
  --output #{Paths.output("conserved_gene_ids_cut.csv")}"
  
  sh "ruby scripts/tree_cluster-taxonomy_analysis.rb \
  --genome_db #{Paths.shared("genomes.db")} \
  --tree_db #{Paths.intermediate("analysis.sqlite")} \
  --output #{Paths.output("tree_cluster_taxonomy.csv")}"
  
  Logger.success("解析完了")
end


desc "全解析パイプラインを実行"
task :do_all do
  begin
    Logger.step("解析パイプライン開始")
    
    # 再利用モードの検証
    ReuseManager.validate_source! if ReuseManager.enabled?
    
    Logger.info("出力ディレクトリ: #{RunManager.current_run_dir}")
    Logger.info("パラメータ詳細: #{File.join(RunManager.current_run_dir, 'README.txt')}")
    
    # タスク実行
    Rake::Task[:download_genomes].invoke
    Rake::Task[:homologs_search].invoke
    Rake::Task[:make_tree].invoke
    Rake::Task[:tree_clustering].invoke
    Rake::Task[:gathering_genomic_neiborhood].invoke
    Rake::Task[:clustering_genomic_neiborhood].invoke
    Rake::Task[:make_gene_cluster_db].invoke
    Rake::Task[:gene_cluster_db_analysis].invoke
    
    RunManager.mark_completed
    
    # =========================================================================
    # ★追加: 次回用のコピペ用テキストを出力
    # =========================================================================
    current_dir_name = File.basename(RunManager.current_run_dir)
    puts "\n"
    puts "📋 次回、この結果を再利用する場合の設定（コピペ用）:"
    puts "--------------------------------------------------------"
    puts "  reuse: {"
    puts "    enabled: true,"
    puts "    source_run: \"#{current_dir_name}\","
    puts "    skip_tasks: [:homologs_search, :make_tree]"
    puts "  }"
    puts "--------------------------------------------------------"
    # =========================================================================

    Logger.step("✅ 全解析完了!")
    Logger.info("結果の場所:")
    Logger.info("   - #{RunManager.current_run_dir}")
    Logger.info("   - #{CONFIG[:dirs][:output]}/latest/")
    
  rescue => e
    RunManager.mark_failed(e.message)
    Logger.error("解析失敗: #{e.message}")
    Logger.error(e.backtrace.first)
    raise
  end
end


# =============================================================================
# 便利タスク
# =============================================================================

desc "過去の実行結果を一覧表示"
task :list_runs do
  summary_file = File.join(CONFIG[:dirs][:output], "runs_summary.csv")
  
  unless File.exist?(summary_file)
    puts "実行履歴がありません"
    next
  end
  
  puts "\n過去の実行履歴:"
  puts "=" * 120
  
  CSV.foreach(summary_file, headers: true) do |row|
    status_icon = case row['status']
                  when 'completed' then '✅'
                  when /^running/ then '🔄'
                  else '❌'
                  end
    
    reused_info = row['reused_from'] && !row['reused_from'].empty? ? " [再利用: #{row['reused_from']}]" : ""
    
    puts "#{status_icon} #{row['timestamp']} | #{row['run_directory']}#{reused_info}"
    puts "   距離: #{row['tree_distance']}, 近傍: #{row['updown_size']}, スコア: #{row['conservation_score']}"
  end
end

desc "特定の実行結果のパラメータを表示 [run_dir=DIR_NAME]"
task :show_run_params do
  run_dir = ENV['run_dir']
  unless run_dir
    puts "使用法: rake show_run_params run_dir=20260129_14_dist2.0_up20_score1.0"
    puts ""
    Rake::Task[:list_runs].invoke
    next
  end
  
  params_file = File.join(CONFIG[:dirs][:output], "runs", run_dir, "README.txt")
  
  if File.exist?(params_file)
    puts File.read(params_file)
  else
    puts "パラメータファイルが見つかりません: #{params_file}"
  end
end

desc "中間ファイルを削除してディスク容量を節約 [run_dir=DIR_NAME or latest]"
task :cleanup_intermediate do
  run_dir = ENV['run_dir']
  
  if run_dir == "latest" || run_dir.nil?
    target = RunManager.current_run_dir
  else
    target = File.join(CONFIG[:dirs][:output], "runs", run_dir)
  end
  
  intermediate_dir = File.join(target, "intermediate")
  
  if Dir.exist?(intermediate_dir)
    size_before = `du -sh #{Shellwords.escape(intermediate_dir)} 2>/dev/null`.split.first rescue "不明"
    FileUtils.rm_rf(intermediate_dir)
    puts "✅ 中間ファイルを削除しました: #{intermediate_dir}"
    puts "   節約容量: #{size_before}"
  else
    puts "中間ファイルが見つかりません: #{intermediate_dir}"
  end
end

desc "全実行の中間ファイルを一括削除"
task :cleanup_all_intermediate do
  runs_dir = File.join(CONFIG[:dirs][:output], "runs")
  deleted_count = 0
  total_size = 0
  
  Dir.glob(File.join(runs_dir, "*/intermediate")).each do |inter_dir|
    if Dir.exist?(inter_dir)
      size = `du -sk #{Shellwords.escape(inter_dir)} 2>/dev/null`.split.first.to_i rescue 0
      total_size += size
      FileUtils.rm_rf(inter_dir)
      deleted_count += 1
    end
  end
  
  puts "✅ #{deleted_count}個の実行の中間ファイルを削除しました"
  puts "   節約容量: #{(total_size / 1024.0).round(2)} MB"
end

desc "ディレクトリ構造を初期化"
task :init do
  CONFIG[:dirs].each do |name, path|
    FileUtils.mkdir_p(path)   # ← 親ディレクトリも含めて作成
    puts "✅ #{path}/"
  end
  
  # runs ディレクトリも作成
  runs_dir = File.join(CONFIG[:dirs][:output], "runs")
  Dir.mkdir(runs_dir) unless Dir.exist?(runs_dir)
  puts "✅ #{runs_dir}/"
  
  # shared_resourcesにREADMEを作成
  shared_readme = File.join(CONFIG[:dirs][:shared_resources], "README.txt")
  unless File.exist?(shared_readme)
    File.open(shared_readme, "w") do |f|
      f.puts "=" * 70
      f.puts "共有リソースディレクトリ"
      f.puts "=" * 70
      f.puts ""
      f.puts "このディレクトリには全実行で共有されるファイルが格納されます："
      f.puts "- all_genome_proteins.faa: 全ゲノムタンパク質統合ファイル"
      f.puts "- reference_genomes_db.dmnd: Diamondデータベース"
      f.puts ""
      f.puts "これらのファイルは一度作成すれば再利用されます。"
    end
  end
  
  puts "\n初期化完了"
end

# =============================================================================
# 再解析・チューニング用タスク
# =============================================================================

desc "最新(latest)の結果を使い、閾値を変更して再計算する\n使用法: rake reanalyze DIST=5.0 SCORE=0.8"
task :reanalyze do
  # 1. 最新の実行結果(latest)を探す
  latest_link = File.join(CONFIG[:dirs][:output], "latest")
  
  # Windows対応などを含めて実パスを解決
  target_dir = if File.symlink?(latest_link)
                 File.readlink(latest_link)
               elsif File.exist?(latest_link) # Windowsのジャンクション等
                 latest_link
               else
                 nil
               end

  # 相対パスなら絶対パスっぽく補完
  if target_dir && !target_dir.start_with?("/") && !target_dir.match?(/^[a-zA-Z]:/)
     # output/latest -> runs/xxx なので、output/runs/xxx に補正
     target_dir = File.join(CONFIG[:dirs][:output], target_dir)
  end

  unless target_dir && Dir.exist?(target_dir)
    Logger.error("前回の実行結果(latest)が見つかりません。")
    Logger.info("まずは rake do_all を一度実行して、ベースとなるデータを作成してください。")
    exit 1
  end

  Logger.step("再解析(チューニング)モード")
  Logger.info("ターゲット: #{target_dir}")
  Logger.info("設定値: 距離閾値(DIST)=#{CONFIG[:tree_distance_threshold]}")
  Logger.info("設定値: 保存スコア(SCORE)=#{CONFIG[:neighborhood_conservation_score]}")

  # 2. RunManagerにこのディレクトリを使うよう強制
  RunManager.set_existing_run_dir(target_dir)

  # 3. 再利用設定を一時的に無効化（現在のディレクトリで再計算するため）
  #    これをしないと、CONFIG[:reuse][:source_run] の古いファイルを取りに行こうとしてバグる可能性がある
  CONFIG[:reuse][:enabled] = false # cannot modify frozen hash... は起きない(freezeしてなければ)。
  # もしCONFIGがfreezeされていたら、ReuseManager側で制御が必要ですが、今回はタスク側で制御します。

  # 4. タスクを順番に実行
  #    invokeを使うと依存関係も解決されますが、ここでは明示的な順序で実行します。

  begin
    
    RunManager.save_run_params(RunManager.current_run_dir)
    #puts "\n--- [Step 1] 系統樹の距離分布を確認 ---"
    #Rake::Task[:tree_analysis].invoke

    # (2) クラスタリング再実行 (パラメータ DIST が影響)
    puts "\n--- [Step 2] クラスタリング実行 (Threshold: #{CONFIG[:tree_distance_threshold]}) ---"
    # タスクが既に実行済みとマークされている場合があるので reenable する
    Rake::Task[:tree_clustering].reenable
    Rake::Task[:tree_clustering].invoke

    # (3) DB再構築 (パラメータ DIST が影響)
    puts "\n--- [Step 3] 遺伝子クラスターDB構築 ---"
    Rake::Task[:make_gene_cluster_db].reenable
    Rake::Task[:make_gene_cluster_db].invoke

    # (4) 解析実行 (パラメータ SCORE が影響)
    puts "\n--- [Step 4] 保存遺伝子解析 (Score: #{CONFIG[:neighborhood_conservation_score]}) ---"
    Rake::Task[:gene_cluster_db_analysis].reenable
    Rake::Task[:gene_cluster_db_analysis].invoke

    Logger.step("再解析完了")
    Logger.info("結果ファイルは #{target_dir} 内に保存されました。")
    
  rescue => e
    Logger.error("再解析中にエラーが発生しました: #{e.message}")
    puts e.backtrace
  end
end

# バージョン確認タスク（任意）
task :version do
  puts "PhyloCGN v#{VERSION}"
end