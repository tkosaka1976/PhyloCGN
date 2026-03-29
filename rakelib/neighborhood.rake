# =============================================================================
# Phase 2: neighborhood
# ホモログ一覧 → 周囲の遺伝子検索 → クラスタリング
# デフォルト: latestのrunフォルダに上書き
# NEW=1 または BASE=xxx 指定時: 新runフォルダを作成
# =============================================================================

desc " 【Phase 2】 近傍遺伝子収集→クラスタリング\n使用法: rake neighborhood UPDOWN=10 [NEW=1] [BASE=20260316_001]"
task :neighborhood do
  updown  = ENV['UPDOWN'] ? ENV['UPDOWN'].to_i : CONFIG[:params_default][:updown]
  base    = ENV['BASE']
  new_run = ENV.key?('NEW') || base

  begin
    if new_run
      # コピー元を決定（BASE指定 > latest）
      source_dir = if base
                     path = File.join(CONFIG[:dirs][:output], "runs", base)
                     raise "BASE で指定されたディレクトリが見つかりません: #{path}" unless Dir.exist?(path)
                     path
                   else
                     dir = RunManager.resolve_latest_dir
                     raise "コピー元(latest)が見つかりません。BASE=xxx で指定してください。" unless dir && Dir.exist?(dir)
                     dir
                   end

      RunManager.create_new_run!
      Logger.step("Phase 2: neighborhood 開始 (UPDOWN=#{updown}) ★新runフォルダ")
      Logger.info("コピー元: #{File.basename(source_dir)}")
      RunManager.copy_phase1_from!(source_dir)
    else
      RunManager.use_latest_run!
      Logger.step("Phase 2: neighborhood 開始 (UPDOWN=#{updown})")
    end

    Rake::Task[:gathering_genomic_neiborhood].invoke
    Rake::Task[:clustering_genomic_neiborhood].invoke

    RunManager.save_run_params(phase: "neighborhood", extra: { updown: updown })
    Logger.step("✅ Phase 2 完了 → 次は rake analyze_pgc DIST=xx SCORE=xx を実行してください")

  rescue => e
    RunManager.mark_failed(e.message)
    Logger.error("Phase 2 失敗: #{e.message}")
    Logger.error(e.backtrace.first)
    raise
  end
end

# -----------------------------------------------------------------------------
# サブタスク
# -----------------------------------------------------------------------------

desc "近傍遺伝子を集める"
task :gathering_genomic_neiborhood do
  Logger.step("ゲノム近傍遺伝子収集")

  updown = ENV['UPDOWN'] ? ENV['UPDOWN'].to_i : CONFIG[:params_default][:updown]

  sh "ruby scripts/get_neighbors_csv.rb \
  --updown #{updown} \
  --input #{Paths.output('all_query_homolog_list.txt')} \
  --data_d #{Paths.downloads('ncbi_dataset', 'data')} \
  --output #{Paths.output('neighborhoods_metadata.csv')}"

  sh "ruby scripts/CSV-save_target_col_uniq.rb \
  #{Paths.output('neighborhoods_metadata.csv')} \
  Combined_ID \
  #{Paths.intermediate('neighborhoods_list.txt')}"

  sh "seqkit grep -f #{Paths.intermediate('neighborhoods_list.txt')} \
   #{Paths.shared('all_genome_proteins.faa')} \
   > #{Paths.intermediate('neighborhoods_list.mfasta')}"

  Logger.success("近傍遺伝子収集完了")
end


desc "genomic neighborhood のクラスター構築"
task :clustering_genomic_neiborhood do
  Logger.step("近傍遺伝子クラスタリング")

  sh "mmseqs easy-cluster \
  #{Paths.intermediate('neighborhoods_list.mfasta')} \
  #{Paths.intermediate('cluster_result')} \
  #{Paths.temp('mmseqs_tmp')} \
  -s #{CONFIG[:mmseqs][:sensitivity]} \
  -c #{CONFIG[:mmseqs][:coverage]} \
  --min-seq-id #{CONFIG[:mmseqs][:identity]} \
  --cluster-mode #{CONFIG[:mmseqs][:cluster_mode]} \
  --single-step-clustering \
  --cov-mode 0"

  sh "ruby scripts/mmseqs_results-summary.rb \
  --input #{Paths.intermediate('cluster_result_cluster.tsv')} \
  --output #{Paths.output('cluster_stat_cluster_id.csv')}"

  sh "ruby scripts/merge_ids.rb \
  --input #{Paths.intermediate('cluster_result_cluster.tsv')} \
  --ref #{Paths.output('cluster_stat_cluster_id.csv')} \
  --output #{Paths.output('cluster_result_gene_id.csv')}"

  sh "ruby scripts/gathering_gene_products.rb \
  --input #{Paths.output('cluster_stat_cluster_id.csv')} \
  --output #{Paths.output('cluster_representative_functions.csv')} \
  --downloads_d #{CONFIG[:dirs][:downloads]}"

  Logger.success("クラスタリング完了")
end


desc "遺伝子クラスターDBを構築"
task :make_gene_cluster_db do
  Logger.step("遺伝子クラスターデータベース構築")

  db_path = Paths.intermediate("analysis.sqlite")

  sh "ruby scripts/import_to_sqlite_sequel.rb \
  --db #{db_path} \
  --tree_clade #{Paths.output('cluster_result_gene_id.csv')} \
  --gene_cluster #{Paths.output('diamond_hits_cut_genomeid.csv')}"

  sh "ruby scripts/split_gene_ids_v2.rb \
  --db #{db_path}"

  Logger.success("データベース構築完了")
end
