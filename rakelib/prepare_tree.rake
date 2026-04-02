# =============================================================================
# Phase 1: prepare_tree_single
# ゲノムDL → ホモログ検索（単一query） → MSA → 系統樹作成
# =============================================================================

desc "【Phase 1 / single】 prepare_tree_single: 単一queryでゲノムDL→ホモログ検索→系統樹作成"
task :prepare_tree_single do
  begin
    RunManager.create_new_run!
    Logger.step("Phase 1 (single): prepare_tree_single 開始")
    Logger.info("出力ディレクトリ: #{RunManager.current_run_dir}")
    Rake::Task[:create_accession_list_reference_genomes].invoke unless File.exist?(CONFIG[:files][:accessions])
    Rake::Task[:download_genomes].invoke
    Rake::Task[:homologs_search_single].invoke
    Rake::Task[:make_tree].invoke
    RunManager.save_run_params(phase: "prepare_tree_single")
    Logger.step("✅ Phase 1 (single) 完了 → 次は rake tree_analysis で閾値を確認してください")
  rescue => e
    RunManager.mark_failed(e.message)
    Logger.error("Phase 1 (single) 失敗: #{e.message}")
    Logger.error(e.backtrace.first)
    raise
  end
end

# =============================================================================
# Phase 1: prepare_tree_multi
# ゲノムDL → ホモログ検索（mfasta複数query） → MSA → 系統樹作成
# =============================================================================

desc "【Phase 1 / multi】 prepare_tree_multi: mfasta複数queryでゲノムDL→ホモログ検索→系統樹作成"
task :prepare_tree_multi do
  begin
    RunManager.create_new_run!
    Logger.step("Phase 1 (multi): prepare_tree_multi 開始")
    Logger.info("出力ディレクトリ: #{RunManager.current_run_dir}")
    Rake::Task[:create_accession_list_reference_genomes].invoke unless File.exist?(CONFIG[:files][:accessions])
    Rake::Task[:download_genomes].invoke
    Rake::Task[:homologs_search_multi].invoke
    Rake::Task[:make_tree].invoke
    RunManager.save_run_params(phase: "prepare_tree_multi")
    Logger.step("✅ Phase 1 (multi) 完了 → 次は rake tree_analysis で閾値を確認してください")
  rescue => e
    RunManager.mark_failed(e.message)
    Logger.error("Phase 1 (multi) 失敗: #{e.message}")
    Logger.error(e.backtrace.first)
    raise
  end
end

# -----------------------------------------------------------------------------
# サブタスク
# -----------------------------------------------------------------------------

desc "AccessionリストをNCBI FTPより取得・生成"
task :create_accession_list_reference_genomes do
  Logger.step("Accessionリスト作成")
  puts "Fetching list from FTP..."

  unless File.exist?(CONFIG[:files][:bacteria_accessions])
    sh "curl -s https://ftp.ncbi.nlm.nih.gov/genomes/refseq/bacteria/assembly_summary.txt |\
    awk -F \"\t\" '$5==\"reference genome\" && $12==\"Complete Genome\" {print $1}' \
    > #{CONFIG[:files][:bacteria_accessions]}"
  end

  unless File.exist?(CONFIG[:files][:archaea_accessions])
    sh "curl -s https://ftp.ncbi.nlm.nih.gov/genomes/refseq/archaea/assembly_summary.txt |\
    awk -F \"\t\" '$5==\"reference genome\" && $12==\"Complete Genome\" {print $1}' \
    > #{CONFIG[:files][:archaea_accessions]}"
  end

  accessions_file = CONFIG[:files][:accessions]
  unless File.exist?(accessions_file)
    File.open(accessions_file, "w") { it.write File.read(CONFIG[:files][:bacteria_accessions]) }
    File.open(accessions_file, "a") { it.write File.read(CONFIG[:files][:archaea_accessions]) }
  end

  Logger.success("Accessionリスト作成完了")
end

desc "ゲノムデータをNCBI ftpよりダウンロード"
task :download_genomes do
  Logger.step("ゲノムデータダウンロード")

  accessions_file = CONFIG[:files][:accessions]
  unless File.exist?(accessions_file)
    Logger.error("Accessionリストが見つかりません。先に rake create_accession_list を実行してください。")
    raise "Missing accessions file: #{accessions_file}"
  end

  FileUtils.mkdir_p(CONFIG[:dirs][:downloads])

  lines      = File.readlines(accessions_file, chomp: true)
  accessions = lines.map(&:strip).reject(&:empty?)
  Logger.info("全 #{accessions.size} 件のダウンロードを開始")

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
    env = CONFIG[:download][:http2_disabled] ? { 'GODEBUG' => 'http2client=0' } : {}

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

# -----------------------------------------------------------------------------
# ホモログ検索
# -----------------------------------------------------------------------------

desc "【single mode】単一queryタンパク質でDiamond検索"
task :homologs_search_single do
  Logger.step("ホモログ検索 (single mode)")

  query = CONFIG[:files][:query_protein]

  _build_genome_db_if_needed

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
  File.open(Paths.output("query_homolog_list.txt"), "w") do |f|
    CSV.foreach(Paths.output("diamond_results_full.tsv"), col_sep: "\t") do |row|
      if row[10].to_f <= CONFIG[:diamond][:evalue] && row[12].to_f > CONFIG[:diamond][:coverage]
        f.puts row[1]
      end
    end
  end

  # multiモードとファイル名を統一するためコピーを作成
  FileUtils.cp(Paths.output("query_homolog_list.txt"), Paths.output("all_query_homolog_list.txt"))
  Logger.info("all_query_homolog_list.txt を作成 (query_homolog_list.txt のコピー)")

  Logger.success("ホモログリスト作成完了 (single mode)")
end

desc "【multi mode】mfastaの各配列をThreadで並列Diamond検索\n  CONFIG[:files][:multi_query_mfasta] を使用"
task :homologs_search_multi do
  Logger.step("ホモログ検索 (multi mode)")

  mfasta_path = Paths.input(CONFIG[:files][:multi_query_mfasta])
  unless File.exist?(mfasta_path)
    Logger.error("mfastaファイルが見つかりません: #{mfasta_path}")
    raise "Missing mfasta: #{mfasta_path}"
  end

  _build_genome_db_if_needed

  # 全エントリを先に読み込む
  entries = []
  Bio::FlatFile.auto(mfasta_path).each_with_index do |ff, i|
    entries << { index: i, entry_id: ff.entry_id, seq: ff.seq.to_s }
  end
  Logger.info("#{entries.size} 配列を並列処理します (Thread)")

  mutex = Mutex.new
  threads = entries.map do |entry|
    Thread.new do
      i         = entry[:index]
      entry_id  = entry[:entry_id]
      tsv_path  = Paths.output("diamond_results_#{i}.tsv")
      list_path = Paths.output("query_homolog_list_#{i}.txt")

      Tempfile.create(["seq_#{i}_", ".fasta"]) do |tmpfile|
        tmpfile.puts ">#{entry_id}"
        tmpfile.puts entry[:seq]
        tmpfile.flush

        cmd = "diamond blastp \
        -k #{CONFIG[:diamond][:subject_size]} \
        -b #{CONFIG[:diamond][:block]} \
        -q #{tmpfile.path} \
        -d #{Paths.shared('reference_genomes_db')} \
        -o #{tsv_path} \
        -e #{CONFIG[:diamond][:evalue]} \
        --id #{CONFIG[:diamond][:identity]} \
        --subject-cover #{CONFIG[:diamond][:coverage]} \
        --query-cover #{CONFIG[:diamond][:coverage]} \
        --#{CONFIG[:diamond][:sensitivity]} \
        --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qcovhsp"

        stdout, stderr, status = Open3.capture3(cmd)
        mutex.synchronize do
          if status.success?
            Logger.info("#{entry_id} (index: #{i}): Diamond完了")
          else
            Logger.error("#{entry_id} (index: #{i}): Diamond失敗\n#{stderr}")
            raise "Diamond failed for entry #{i} (#{entry_id})"
          end
        end
      end

      File.open(list_path, "w") do |f|
        CSV.foreach(tsv_path, col_sep: "\t") do |row|
          if row[10].to_f <= CONFIG[:diamond][:evalue] && row[12].to_f > CONFIG[:diamond][:coverage]
            f.puts row[1]
          end
        end
      end
    end
  end
  threads.each(&:join)

  # primary query のリストを query_homolog_list.txt としてコピー
  primary_idx  = CONFIG[:files][:multi_primary_query_position]
  primary_list = Paths.output("query_homolog_list_#{primary_idx}.txt")
  unless File.exist?(primary_list)
    raise "primary query (index: #{primary_idx}) のhomolog listが見つかりません: #{primary_list}"
  end
  FileUtils.cp(primary_list, Paths.output("query_homolog_list.txt"))
  Logger.info("primary query (index: #{primary_idx}) → query_homolog_list.txt にコピー")

  # 全配列のhomologをマージした all_query_homolog_list.txt を作成
  all_subjects = []
    Dir.glob(Paths.output("query_homolog_list_*.txt")).each do |path|
      all_subjects.concat(File.readlines(path, chomp: true))
    end
    all_subjects.uniq!
    File.open(Paths.output("all_query_homolog_list.txt"), "w") do |f|
      f.write(all_subjects.join("\n"))
    end
  Logger.info("全配列マージ (#{all_subjects.size} unique) → all_query_homolog_list.txt")
  Logger.success("ホモログリスト作成完了 (multi mode)")
end

# -----------------------------------------------------------------------------
# 内部ヘルパー: DBがなければ構築（single/multi共通）
# -----------------------------------------------------------------------------
def _build_genome_db_if_needed
  unless File.exist?(Paths.shared("all_genome_proteins.faa"))
    Logger.info("全ゲノムタンパク質ファイルを結合中...")
    File.open(Paths.shared("all_genome_proteins.faa"), "w") do |faa|
      Dir.glob(Paths.downloads("ncbi_dataset", "data", "**", "protein.faa")).each do |fp|
        /\/data\/(.+)\/protein\.faa/ =~ fp
        acc = $1
        File.foreach(fp) do |line|
          faa.puts line.sub(/^>/, ">#{acc}_")
        end
      end
    end
  end

  unless File.exist?(Paths.shared("reference_genomes_db.dmnd"))
    Logger.info("Diamondデータベース構築中...")
    sh "diamond makedb --in #{Paths.shared('all_genome_proteins.faa')} -d #{Paths.shared('reference_genomes_db')}"
  end
end

# -----------------------------------------------------------------------------
# MSA → 系統樹（single/multi共通）
# -----------------------------------------------------------------------------

desc "MSAからのTree作成"
task :make_tree do
  Logger.step("系統樹作成")

  Logger.info("配列抽出中...")
  sh "seqkit grep -f #{Paths.output('query_homolog_list.txt')} \
   #{Paths.shared('all_genome_proteins.faa')} \
   > #{Paths.intermediate('diamond_hits.fasta')}"

  fasta_file     = Paths.intermediate('diamond_hits.fasta')
  sequence_count = `seqkit stats -T #{Shellwords.escape(fasta_file)} | tail -n 1 | cut -f 4`.strip.to_i
  Logger.info("配列数: #{sequence_count}")

  threshold   = CONFIG[:tools][:muscle][:super5_threshold]
  muscle_opts = sequence_count > threshold ? "-super5" : "-align"
  Logger.info(sequence_count > threshold ? "-super5 モードで実行" : "標準モードで実行")

  Logger.info("マルチプルアライメント実行中...")
  sh "muscle#{CONFIG[:tools][:muscle_version]} \
  #{muscle_opts} #{Paths.intermediate('diamond_hits.fasta')} \
  -output #{Paths.intermediate('diamond_hits.afa')}"

  Logger.info("系統樹構築中...")
  tree_opts  = CONFIG[:tools][:veryfasttree]
  gamma_flag = tree_opts[:gamma] ? "-gamma" : ""
  sh "VeryFastTree \
  -#{tree_opts[:model]} #{gamma_flag} -threads #{tree_opts[:threads]} \
  #{Paths.intermediate('diamond_hits.afa')} \
  > #{Paths.output('diamond_hits.tree')}"

  Logger.success("系統樹作成完了")
end

desc " [Do This!] 系統樹の距離分布を確認して閾値を決める（runフォルダを作らない）\n使用法: rake tree_analysis [DIR=フォルダ名]"
task :tree_analysis do
  if ENV['DIR']
    target_dir = File.join(CONFIG[:dirs][:output], "runs", ENV['DIR'])
  elsif File.exist?(File.join(CONFIG[:dirs][:output], "latest"))
    target_dir = File.join(CONFIG[:dirs][:output], "latest")
  else
    Logger.error("解析対象が見つかりません。先に rake prepare_tree_single または rake prepare_tree_multi を実行してください。")
    exit 1
  end

  tree_file = File.join(target_dir, "results", "diamond_hits.tree")

  unless File.exist?(tree_file)
    Logger.error("Treeファイルが見つかりません: #{tree_file}")
    Logger.info("例: rake tree_analysis DIR=20260315_001")
    exit 1
  end

  Logger.info("解析対象: #{tree_file}")
  Logger.step("閾値調整スクリプトを実行")
  sh "ruby scripts/tune_threshold.rb #{tree_file}"
end
