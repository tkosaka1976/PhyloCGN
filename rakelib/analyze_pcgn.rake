# =============================================================================
# Phase 3: analyze_pcgn
# tree_clustering → DB構築 → DB解析 → 結果出力
# デフォルト: latestのrunフォルダに上書き
# NEW=1 または BASE=xxx 指定時: 新runフォルダを作成
# =============================================================================

desc " 【Phase 3】 系統樹クラスタリング→保存遺伝子解析→結果出力\n使用法: rake analyze_pcgn DIST=3.0 SCORE=0.9 [NEW=1] [BASE=20260316_001]"
task :analyze_pcgn do
  dist    = ENV['DIST']  ? ENV['DIST'].to_f  : CONFIG[:params_default][:dist]
  score   = ENV['SCORE'] ? ENV['SCORE'].to_f : CONFIG[:params_default][:score]
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
      Logger.step("Phase 3: analyze_pcgn 開始 (DIST=#{dist}, SCORE=#{score}) ★新runフォルダ")
      Logger.info("コピー元: #{File.basename(source_dir)}")
      RunManager.copy_phase1_and_2_from!(source_dir)
    else
      RunManager.use_latest_run!
      Logger.step("Phase 3: analyze_pcgn 開始 (DIST=#{dist}, SCORE=#{score})")
    end

    Rake::Task[:tree_clustering].invoke
    Rake::Task[:make_gene_cluster_db].invoke
    Rake::Task[:gene_cluster_db_analysis].invoke

    RunManager.save_run_params(phase: "analyze_pcgn", extra: { dist: dist, score: score })
    RunManager.mark_completed

    Logger.step("✅ Phase 3 完了！")
    Logger.info("結果の場所: #{RunManager.current_run_dir}/results/")

  rescue => e
    RunManager.mark_failed(e.message)
    Logger.error("Phase 3 失敗: #{e.message}")
    Logger.error(e.backtrace.first)
    raise
  end
end

# -----------------------------------------------------------------------------
# サブタスク
# -----------------------------------------------------------------------------

task :tree_clustering do
  Logger.step("系統樹クラスタリング")

  dist = ENV['DIST'] ? ENV['DIST'].to_f : CONFIG[:params_default][:dist]

  sh "ruby #{Shellwords.shellescape('scripts/treeclustering2json&csv.rb')} \
  --threshold #{dist} \
  --input #{Paths.output('diamond_hits.tree')} \
  --output #{Paths.output('diamond_hits')}"

  sh "ruby scripts/add_gcf_column.rb \
  --input #{Paths.output('diamond_hits_cut.csv')} \
  --output #{Paths.output('diamond_hits_cut_genomeid.csv')}"

  sh "ruby scripts/treetrim.rb \
  --input #{Paths.output('diamond_hits_cut.json')} \
  --output #{Paths.output('diamond_hits_cut_trim.json')}"

  sh "ruby scripts/json2newick.rb \
  --input #{Paths.output('diamond_hits_cut_trim.json')} \
  --output #{Paths.output('diamond_hits_cut_trim.tree')}"

  Logger.success("クラスタリング完了")
end


task :gene_cluster_db_analysis do
  Logger.step("保存遺伝子クラスター解析")

  score = ENV['SCORE'] ? ENV['SCORE'].to_f : CONFIG[:params_default][:score]

  sh "ruby scripts/show-conserved_gene_cluster.rb \
  --score #{score} \
  --db #{Paths.intermediate('analysis.sqlite')} \
  --output #{Paths.output('conserved_gene_ids_cut.csv')}"

  sh "ruby scripts/tree_cluster-taxonomy_analysis.rb \
  --genome_db #{Paths.shared('genomes.db')} \
  --tree_db #{Paths.intermediate('analysis.sqlite')} \
  --output #{Paths.output('tree_cluster_taxonomy.csv')}"

  Logger.success("解析完了")
end
