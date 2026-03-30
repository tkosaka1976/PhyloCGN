# =============================================================================
# 便利タスク: do_all, list_runs, init, cleanup_*, version
# =============================================================================

desc [
  " 全Phase[1,2,3]を一括実行（新runフォルダを作成）",
  "使用法:",
  "  rake do_all MODE=single UPDOWN=10 DIST=3.0 SCORE=0.9             # 全Phase実行（single mode）",
  "  rake do_all MODE=multi  UPDOWN=10 DIST=3.0 SCORE=0.9             # 全Phase実行（multi mode）",
  "  rake do_all MODE=single REUSE_TREE=20260315_001 UPDOWN=10 DIST=3.0 SCORE=0.9  # Phase1をスキップ",
  "  rake do_all MODE=single REUSE_NEIGHBOR=20260315_001 DIST=3.0 SCORE=0.9        # Phase1+2をスキップ",
].join("\n")

task :do_all do
  dist   = ENV['DIST']   ? ENV['DIST'].to_f  : CONFIG[:params_default][:dist]
  score  = ENV['SCORE']  ? ENV['SCORE'].to_f : CONFIG[:params_default][:score]
  updown = ENV['UPDOWN'] ? ENV['UPDOWN'].to_i : CONFIG[:params_default][:updown]
  mode   = ENV['MODE']

  reuse_tree     = ENV['REUSE_TREE']
  reuse_neighbor = ENV['REUSE_NEIGHBOR']

  begin
    # 必ず新しいrunフォルダを作成
    RunManager.create_new_run!
    Logger.step("PhyloCGN 全解析パイプライン開始")
    Logger.info("出力ディレクトリ: #{RunManager.current_run_dir}")

    # ------------------------------------------------------------------
    # Phase 1: prepare_tree
    # ------------------------------------------------------------------
    if reuse_tree || reuse_neighbor
      # treeを別runから再利用
      source = reuse_neighbor || reuse_tree
      Logger.step("Phase 1: スキップ（#{source} から再利用）")
      source_dir = File.join(CONFIG[:dirs][:output], "runs", source)
      raise "再利用元が見つかりません: #{source_dir}" unless Dir.exist?(source_dir)

      # 必要なファイルをコピー
      {
        "results/diamond_results_full.tsv"  => Paths.output("diamond_results_full.tsv"),
        "results/query_homolog_list.txt"    => Paths.output("query_homolog_list.txt"),
        "results/diamond_hits.tree"         => Paths.output("diamond_hits.tree"),
        "intermediate/diamond_hits.fasta"   => Paths.intermediate("diamond_hits.fasta"),
        "intermediate/diamond_hits.afa"     => Paths.intermediate("diamond_hits.afa"),
      }.each do |src_rel, dest|
        src = File.join(source_dir, src_rel)
        if File.exist?(src)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
          Logger.info("  ✓ #{File.basename(src_rel)} をコピー")
        else
          Logger.error("  ✗ #{src_rel} が見つかりません")
        end
      end

      RunManager.save_run_params(phase: "prepare_tree(reused)", extra: { reused_tree: source })
    else
      unless %w[single multi].include?(mode)
        Logger.error("MODE の指定が必要です。MODE=single または MODE=multi を指定してください。")
        raise "Missing or invalid MODE: #{mode.inspect}"
      end

      Logger.step("Phase 1: prepare_tree_#{mode}")
      Rake::Task[:download_genomes].invoke
      Rake::Task[mode == "single" ? :homologs_search_single : :homologs_search_multi].invoke
      Rake::Task[:make_tree].invoke
      RunManager.save_run_params(phase: "prepare_tree_#{mode}")
    end

    # ------------------------------------------------------------------
    # Phase 2: neighborhood
    # ------------------------------------------------------------------
    if reuse_neighbor
      Logger.step("Phase 2: スキップ（#{reuse_neighbor} から再利用）")
      source_dir = File.join(CONFIG[:dirs][:output], "runs", reuse_neighbor)

      {
        "results/neighborhoods_metadata.csv"          => Paths.output("neighborhoods_metadata.csv"),
        "results/cluster_stat_cluster_id.csv"         => Paths.output("cluster_stat_cluster_id.csv"),
        "results/cluster_result_gene_id.csv"          => Paths.output("cluster_result_gene_id.csv"),
        "results/cluster_representative_functions.csv"=> Paths.output("cluster_representative_functions.csv"),
        "intermediate/neighborhoods_list.txt"         => Paths.intermediate("neighborhoods_list.txt"),
        "intermediate/neighborhoods_list.mfasta"      => Paths.intermediate("neighborhoods_list.mfasta"),
      }.each do |src_rel, dest|
        src = File.join(source_dir, src_rel)
        if File.exist?(src)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
          Logger.info("  ✓ #{File.basename(src_rel)} をコピー")
        else
          Logger.error("  ✗ #{src_rel} が見つかりません")
        end
      end

      RunManager.save_run_params(phase: "neighborhood(reused)", extra: { reused_neighbor: reuse_neighbor, updown: updown })
    else
      # ENVを一時的にセットしてサブタスクに渡す
      ENV['UPDOWN'] ||= updown.to_s
      Rake::Task[:gathering_genomic_neiborhood].invoke
      Rake::Task[:clustering_genomic_neiborhood].invoke
      RunManager.save_run_params(phase: "neighborhood", extra: { updown: updown })
    end

    # ------------------------------------------------------------------
    # Phase 3: analyze_pcgn
    # ------------------------------------------------------------------
    ENV['DIST']  = dist.to_s
    ENV['SCORE'] = score.to_s
    Rake::Task[:tree_clustering].invoke
    Rake::Task[:make_gene_cluster_db].invoke
    Rake::Task[:gene_cluster_db_analysis].invoke
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

    # run_params.ymlから条件を読む
    params_file = File.join(CONFIG[:dirs][:output], "runs", row['run_directory'], "run_params.yml")
    if File.exist?(params_file)
      params = YAML.load_file(params_file)
      cond = "DIST=#{params[:dist]} UPDOWN=#{params[:updown]} SCORE=#{params[:score]} phase=#{params[:last_phase]}"
    else
      cond = "(params不明)"
    end

    puts "#{status_icon} #{row['timestamp']} | #{row['run_directory']} | #{cond}"
  end
end


desc "特定の実行結果のパラメータを表示\n使用法: rake show_run_params DIR=20260315_001"
task :show_run_params do
  run_dir = ENV['DIR']
  unless run_dir
    puts "使用法: rake show_run_params DIR=20260315_001"
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


desc "中間ファイルを削除してディスク容量を節約\n使用法: rake cleanup_intermediate [DIR=フォルダ名]"
task :cleanup_intermediate do
  run_dir = ENV['DIR']
  target  = if run_dir
              File.join(CONFIG[:dirs][:output], "runs", run_dir)
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