# =============================================================================
# Phase 3: analyze_pcgn
# tree_clustering → DB構築 → DB解析 → 結果出力
# デフォルト: latestのrunフォルダに上書き
# base指定 または new_run="1" 指定時: 新runフォルダを作成
# =============================================================================

desc <<~DESC
  【Phase 3】 系統樹クラスタリング→保存遺伝子解析→結果出力
  使用法: rake analyze_pcgn[dist,score,base,new_run]
    dist    : クラスタリング距離閾値（小数）  ※省略時: config デフォルト値
    score   : 保存遺伝子スコア閾値（小数）    ※省略時: config デフォルト値
    base    : コピー元 run フォルダ名         ※省略時: latest を使用、指定時は新 run
    new_run : "1" 指定で強制的に新 run 作成   ※省略可
  例:
    rake analyze_pcgn[3.0,0.9]
    rake analyze_pcgn[3.0,0.9,20260316_001]
    rake analyze_pcgn[3.0,0.9,,1]
    rake analyze_pcgn
DESC
task :analyze_pcgn, [:dist, :score, :base, :new_run] do |_t, args|
  dist    = args[:dist].to_s.strip.then  { |v| v.empty? ? CONFIG[:params_default][:dist]  : v.to_f }
  score   = args[:score].to_s.strip.then { |v| v.empty? ? CONFIG[:params_default][:score] : v.to_f }
  base    = args[:base].to_s.strip.then  { |v| v.empty? ? nil : v }
  new_run = !args[:new_run].to_s.strip.empty? || base

  begin
    if new_run
      source_dir = if base
                     path = File.join(CONFIG[:dirs][:output], "runs", base)
                     raise "base で指定されたディレクトリが見つかりません: #{path}" unless Dir.exist?(path)
                     path
                   else
                     dir = RunManager.resolve_latest_dir
                     raise "コピー元(latest)が見つかりません。base=xxx で指定してください。" unless dir && Dir.exist?(dir)
                     dir
                   end

      RunManager.create_new_run!
      Logger.step("Phase 3: analyze_pcgn 開始 (dist=#{dist}, score=#{score}) ★新runフォルダ")
      Logger.info("コピー元: #{File.basename(source_dir)}")
      RunManager.copy_phase1_and_2_from!(source_dir)
    else
      RunManager.use_latest_run!
      Logger.step("Phase 3: analyze_pcgn 開始 (dist=#{dist}, score=#{score})")
    end

    Rake::Task[:tree_clustering].invoke(dist)
    Rake::Task[:make_gene_cluster_db].invoke
    Rake::Task[:gene_cluster_db_analysis].invoke(score)

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

desc <<~DESC
  系統樹クラスタリング
  使用法: rake tree_clustering[dist]
    dist : クラスタリング距離閾値（小数）  ※省略時: config デフォルト値
DESC
task :tree_clustering, [:dist] do |_t, args|
  Logger.step("系統樹クラスタリング")

  dist = args[:dist].to_s.strip.then { |v| v.empty? ? CONFIG[:params_default][:dist] : v.to_f }

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


desc <<~DESC
  保存遺伝子クラスター解析
  使用法: rake gene_cluster_db_analysis[score]
    score : 保存遺伝子スコア閾値（小数）  ※省略時: config デフォルト値
DESC
task :gene_cluster_db_analysis, [:score] do |_t, args|
  Logger.step("保存遺伝子クラスター解析")

  score = args[:score].to_s.strip.then { |v| v.empty? ? CONFIG[:params_default][:score] : v.to_f }

  sh "ruby scripts/show-conserved_gene_cluster.rb \
  --score #{score} \
  --db #{Paths.intermediate('analysis.sqlite')} \
  --output #{Paths.output('conserved_gene_ids_cut.csv')}"

  sh "ruby scripts/tree_cluster-taxonomy_analysis.rb \
  --genome_db #{Paths.shared('genomes.db')} \
  --tree_db #{Paths.intermediate('analysis.sqlite')} \
  --taxonomy #{CONFIG[:params_default][:taxonomy]} \
  --output #{Paths.output('tree_cluster_taxonomy.csv')}"

  Logger.success("解析完了")
end
