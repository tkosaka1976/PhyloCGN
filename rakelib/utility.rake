# =============================================================================
# 便利タスク: do_all, list_runs, init, cleanup_*, version
# =============================================================================

desc <<~DESC
  全Phase[1,2,3]を一括実行（新runフォルダを作成）
  使用法: rake do_all[updown,dist,score,reuse_tree,reuse_neighbor]
    updown        : 近傍遺伝子の上下範囲（整数）  ※省略時: config デフォルト値
    dist          : クラスタリング距離閾値（小数）  ※省略時: config デフォルト値
    score         : 保存遺伝子スコア閾値（小数）    ※省略時: config デフォルト値
    reuse_tree    : Phase1 をスキップして再利用する run フォルダ名  ※省略可
    reuse_neighbor: Phase1+2 をスキップして再利用する run フォルダ名  ※省略可
  例:
    rake do_all[10,3.0,0.9]
    rake do_all[10,3.0,0.9,20260315_001]
    rake do_all[,,0.9,,20260315_001]
DESC
task :do_all, [:updown, :dist, :score, :reuse_tree, :reuse_neighbor] do |_t, args|
  updown         = args[:updown].to_s.strip.then        { |v| v.empty? ? CONFIG[:params_default][:updown] : v.to_i }
  dist           = args[:dist].to_s.strip.then          { |v| v.empty? ? CONFIG[:params_default][:dist]   : v.to_f }
  score          = args[:score].to_s.strip.then         { |v| v.empty? ? CONFIG[:params_default][:score]  : v.to_f }
  reuse_tree     = args[:reuse_tree].to_s.strip.then    { |v| v.empty? ? nil : v }
  reuse_neighbor = args[:reuse_neighbor].to_s.strip.then { |v| v.empty? ? nil : v }

  begin
    RunManager.create_new_run!
    Logger.step("PhyloCGN 全解析パイプライン開始")
    Logger.info("出力ディレクトリ: #{RunManager.current_run_dir}")

    # ------------------------------------------------------------------
    # Phase 1: prepare_tree
    # ------------------------------------------------------------------
    if reuse_tree || reuse_neighbor
      source = reuse_neighbor || reuse_tree
      Logger.step("Phase 1: スキップ（#{source} から再利用）")
      source_dir = File.join(CONFIG[:dirs][:output], "runs", source)
      raise "再利用元が見つかりません: #{source_dir}" unless Dir.exist?(source_dir)

      # reuse_neighbor の場合は Phase 1+2 をまとめて後でコピーするため、ここでは Phase 1 のみコピー
      RunManager.copy_phase1_from!(source_dir) unless reuse_neighbor
      RunManager.save_run_params(phase: "prepare_tree(reused)", extra: { reused_tree: source })
    else
      Rake::Task[:download_genomes].invoke
      Rake::Task[:homologs_search_single].invoke
      Rake::Task[:make_tree].invoke
      RunManager.save_run_params(phase: "prepare_tree")
    end

    # ------------------------------------------------------------------
    # Phase 2: neighborhood
    # ------------------------------------------------------------------
    if reuse_neighbor
      Logger.step("Phase 2: スキップ（#{reuse_neighbor} から再利用）")
      source_dir = File.join(CONFIG[:dirs][:output], "runs", reuse_neighbor)
      raise "再利用元が見つかりません: #{source_dir}" unless Dir.exist?(source_dir)

      RunManager.copy_phase1_and_2_from!(source_dir)
      RunManager.save_run_params(phase: "neighborhood(reused)", extra: { reused_neighbor: reuse_neighbor, updown: updown })
    else
      Rake::Task[:gathering_genomic_neiborhood].invoke(updown)
      Rake::Task[:clustering_genomic_neiborhood].invoke
      RunManager.save_run_params(phase: "neighborhood", extra: { updown: updown })
    end

    # ------------------------------------------------------------------
    # Phase 3: analyze_pcgn
    # ------------------------------------------------------------------
    Rake::Task[:tree_clustering].invoke(dist)
    Rake::Task[:make_gene_cluster_db].invoke
    Rake::Task[:gene_cluster_db_analysis].invoke(score)
    RunManager.save_run_params(phase: "analyze_pcgn", extra: { dist: dist, score: score, updown: updown })

    RunManager.mark_completed

    Logger.step("✅ 全解析完了!")
    Logger.info("結果の場所: #{RunManager.current_run_dir}/results/")

  rescue => e
    RunManager.mark_failed(e.message)
    Logger.error("解析失敗: #{e.message}")
    Logger.error(e.backtrace.first)
    raise
  end
end


# -----------------------------------------------------------------------------
# 管理タスク
# -----------------------------------------------------------------------------

namespace :utility do

desc "過去の実行結果を一覧表示"
task :list_runs do
  summary_file = File.join(CONFIG[:dirs][:output], "runs_summary.csv")
  unless File.exist?(summary_file)
    puts "実行履歴がありません"
    puts "新しく解析を開始するには、以下のコマンドを実行してください："
    puts "  rake do_all"
    puts "  (パラメータ指定例: rake do_all[10,3.0,0.9])"
    puts "  rake prepare_tree_single"
    puts "  rake prepare_tree_multi"
    next
  end
  puts "\n過去の実行履歴:"
  puts "=" * 100
  CSV.foreach(summary_file, headers: true) do |row|
    status_icon = case row['status']
    when 'completed' then '✅'
    when /^running/  then '🔄'
    else                  '❌'
    end
    params_file = File.join(CONFIG[:dirs][:output], "runs", row['run_directory'], "Condition.txt")
    if File.exist?(params_file)
      lines = File.readlines(params_file)
      extract = ->(label) { lines.find { |l| l.include?(label) }&.split(":", 2)&.last&.strip }
      cond = "dist=#{extract.("dist")} updown=#{extract.("updown")} score=#{extract.("score")} phase=#{extract.("最終Phase")}"
    else
      cond = "(params不明)"
    end
    puts "#{status_icon} #{row['timestamp']} | #{row['run_directory']} | #{cond}"
  end
end

desc <<~DESC
  特定の実行結果のパラメータを表示
  使用法: rake utility:show_run_params[dir]
    dir : 対象 run フォルダ名  ※省略時: 履歴一覧を表示
  例:
    rake utility:show_run_params[20260315_001]
DESC
task :show_run_params, [:dir] do |_t, args|
  dir = args[:dir].to_s.strip.then { |v| v.empty? ? nil : v }

  unless dir
    puts "使用法: rake utility:show_run_params[20260315_001]"
    puts ""
    Rake::Task["utility:list_runs"].invoke
    next
  end

  params_file = File.join(CONFIG[:dirs][:output], "runs", dir, "Condition.txt")
  if File.exist?(params_file)
    puts File.read(params_file)
  else
    puts "パラメータファイルが見つかりません: #{params_file}"
  end
end


desc <<~DESC
  中間ファイルを削除してディスク容量を節約
  使用法: rake utility:cleanup_intermediate[dir]
    dir : 対象 run フォルダ名  ※省略時: latest を対象
  例:
    rake utility:cleanup_intermediate[20260315_001]
    rake utility:cleanup_intermediate
DESC
task :cleanup_intermediate, [:dir] do |_t, args|
  dir = args[:dir].to_s.strip.then { |v| v.empty? ? nil : v }

  target = if dir
             File.join(CONFIG[:dirs][:output], "runs", dir)
           else
             File.join(CONFIG[:dirs][:output], "latest")
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
  runs_dir      = File.join(CONFIG[:dirs][:output], "runs")
  deleted_count = 0
  total_size    = 0

  Dir.glob(File.join(runs_dir, "*/intermediate")).each do |inter_dir|
    if Dir.exist?(inter_dir)
      size        = `du -sk #{Shellwords.escape(inter_dir)} 2>/dev/null`.split.first.to_i rescue 0
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
  CONFIG[:dirs].each do |_name, path|
    FileUtils.mkdir_p(path)
    puts "✅ #{path}/"
  end

  runs_dir = File.join(CONFIG[:dirs][:output], "runs")
  FileUtils.mkdir_p(runs_dir)
  puts "✅ #{runs_dir}/"

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


desc "PhyloCGN バージョン確認"
task :version do
  puts "PhyloCGN v#{VERSION}"
end

end
