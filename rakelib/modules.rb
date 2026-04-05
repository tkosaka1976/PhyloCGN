# =============================================================================
# モジュール群: Logger, RunManager, Paths
# =============================================================================

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

# 実行管理モジュール
module RunManager
  class << self

    def current_run_dir
      @current_run_dir || raise("RunManagerが初期化されていません。homologs_search_single、homologs_search_multi または do_all を先に実行してください。")
    end

    # create_new_run! の前に呼んでコピー元を確定する
    def resolve_latest_dir
      latest_link = File.join(CONFIG[:dirs][:output], "latest")
      if File.symlink?(latest_link)
        path = File.readlink(latest_link)
        path.start_with?("/") || path.match?(/^[a-zA-Z]:/) ? path : File.join(CONFIG[:dirs][:output], path)
      elsif File.exist?(latest_link)
        latest_link
      end
    end

    # prepare_tree / do_all から呼ぶ（必ず新規フォルダを作る）
    def create_new_run!
      @current_run_dir = create_run_directory
    end

    # neighborhood / analyze_pgc から呼ぶ（latestを使う）
    def use_latest_run!
      latest_link = File.join(CONFIG[:dirs][:output], "latest")

      target = if File.symlink?(latest_link)
                 path = File.readlink(latest_link)
                 # 相対パスなら補完
                 path.start_with?("/") || path.match?(/^[a-zA-Z]:/) ? path : File.join(CONFIG[:dirs][:output], path)
               elsif File.exist?(latest_link)
                 latest_link
               end

      unless target && Dir.exist?(target)
        raise "前回の実行結果(latest)が見つかりません。先に rake homologs_search を実行してください。"
      end

      @current_run_dir = target
      Logger.info("実行ディレクトリ(latest): #{File.basename(@current_run_dir)}")
    end

    # base指定時: 指定ディレクトリからPhase1成果物をコピー
    def copy_phase1_from!(source_dir)
      copy_files_from(source_dir, {
        "results/diamond_results_full.tsv"  => Paths.output("diamond_results_full.tsv"),
        "results/query_homolog_list.txt"    => Paths.output("query_homolog_list.txt"),
        "results/all_query_homolog_list.txt" => Paths.output("all_query_homolog_list.txt"),
        "results/diamond_hits.tree"         => Paths.output("diamond_hits.tree"),
        "intermediate/diamond_hits.fasta"   => Paths.intermediate("diamond_hits.fasta"),
        "intermediate/diamond_hits.afa"     => Paths.intermediate("diamond_hits.afa"),
      })
    end

    # base指定時: 指定ディレクトリからPhase1+2成果物をコピー
    def copy_phase1_and_2_from!(source_dir)
      copy_phase1_from!(source_dir)
      copy_files_from(source_dir, {
        "results/neighborhoods_metadata.csv"           => Paths.output("neighborhoods_metadata.csv"),
        "results/cluster_stat_cluster_id.csv"          => Paths.output("cluster_stat_cluster_id.csv"),
        "results/cluster_result_gene_id.csv"           => Paths.output("cluster_result_gene_id.csv"),
        "results/cluster_representative_functions.csv" => Paths.output("cluster_representative_functions.csv"),
        "intermediate/neighborhoods_list.txt"          => Paths.intermediate("neighborhoods_list.txt"),
        "intermediate/neighborhoods_list.mfasta"       => Paths.intermediate("neighborhoods_list.mfasta"),
      })
    end

    # do_all の reuse_tree / reuse_neighbor 用
    def use_existing_run!(dir_name)
      path = File.join(CONFIG[:dirs][:output], "runs", dir_name)
      raise "指定されたディレクトリが存在しません: #{path}" unless Dir.exist?(path)
      @current_run_dir = path
      Logger.info("実行ディレクトリを固定: #{File.basename(@current_run_dir)}")
    end

    def save_run_params(phase: nil, extra: {})
      run_dir = current_run_dir
      condition_file = File.join(run_dir, "Condition.txt")

      # 既存の Condition.txt があれば created_at だけ引き継ぐ
      existing_created_at = if File.exist?(condition_file)
        line = File.readlines(condition_file).find { |l| l.start_with?("作成日時") }
        line&.split(":", 2)&.last&.strip
      end

      params_data = {
        last_updated:  Time.now.iso8601,
        last_phase:    phase,
        ruby_version:  RUBY_VERSION,
        git_commit:    `git rev-parse HEAD 2>/dev/null`.chomp,
        hostname:      `hostname`.chomp,
        config:        CONFIG.reject { |k, _| k == :ncbi_api_key },
      }.merge(extra)

      # 初回のみ作成タイムスタンプを記録
      params_data[:created_at] = existing_created_at || Time.now.iso8601

      write_condition(run_dir, params_data)

      update_summary_params(params_data[:updown], params_data[:dist], params_data[:score])
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

    private

    def copy_files_from(source_dir, file_map)
      Logger.info("コピー元: #{File.basename(source_dir)}")
      file_map.each do |src_rel, dest|
        src = File.join(source_dir, src_rel)
        if File.exist?(src)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
          Logger.info("  ✓ #{File.basename(src_rel)}")
        else
          Logger.error("  ✗ #{src_rel} が見つかりません")
        end
      end
    end

    def create_run_directory
      date_str  = Time.now.strftime("%Y%m%d")
      runs_base = File.join(CONFIG[:dirs][:output], "runs")
      FileUtils.mkdir_p(runs_base)

      counter  = 1
      dir_name = nil
      run_dir  = nil
      loop do
        dir_name = "#{date_str}_#{sprintf('%03d', counter)}"
        run_dir  = File.join(runs_base, dir_name)
        break unless Dir.exist?(run_dir)
        counter += 1
      end

      Logger.info("実行ディレクトリを作成中: #{dir_name}")
      FileUtils.mkdir_p(run_dir)

      %w[results intermediate temp].each do |subdir|
        FileUtils.mkdir_p(File.join(run_dir, subdir))
        Logger.info("  ✓ #{subdir}/")
      end

      update_latest_link(run_dir)
      append_to_summary(dir_name)

      Logger.success("実行ディレクトリ準備完了: #{dir_name}")
      run_dir
    end

    def update_latest_link(run_dir)
      return if Gem.win_platform?
      latest_link = File.join(CONFIG[:dirs][:output], "latest")
      File.delete(latest_link) if File.symlink?(latest_link) || File.exist?(latest_link)
      File.symlink(File.join("runs", File.basename(run_dir)), latest_link)
    end

    def append_to_summary(dir_name)
      summary_file = File.join(CONFIG[:dirs][:output], "runs_summary.csv")
      FileUtils.mkdir_p(File.dirname(summary_file))

      unless File.exist?(summary_file)
        File.open(summary_file, "w") do |f|
          f.puts "timestamp,run_directory,query_protein,accessions,updown,dist,score,status"
        end
      end

      File.open(summary_file, "a") do |f|
        f.puts [
          Time.now.iso8601,
          dir_name,
          CONFIG[:files][:query_protein],
          CONFIG[:files][:accessions],
          "",   # updown（後で更新）
          "",   # dist（後で更新）
          "",   # score（後で更新）
          "running"
        ].join(",")
      end
    end

    def update_summary_params(updown, dist, score)
      summary_file = File.join(CONFIG[:dirs][:output], "runs_summary.csv")
      return unless File.exist?(summary_file)
      lines = File.readlines(summary_file)
      if lines.last&.include?(File.basename(current_run_dir))
        row = lines.last.chomp.split(",")
        row[4] = updown || CONFIG[:params_default][:updown]
        row[5] = dist   || CONFIG[:params_default][:dist]
        row[6] = score  || CONFIG[:params_default][:score]
        lines[-1] = row.join(",") + "\n"
        File.write(summary_file, lines.join)
      end
    end

    def update_status(status)
      summary_file = File.join(CONFIG[:dirs][:output], "runs_summary.csv")
      return unless File.exist?(summary_file)
      run_dir_name = File.basename(current_run_dir)
      lines = File.readlines(summary_file)
      updated = false
      lines.map! do |line|
        if !updated && line.include?(run_dir_name) && line.include?("running")
          updated = true
          line.gsub("running", status)
        else
          line
        end
      end
      File.write(summary_file, lines.join)
    end

    def write_condition(run_dir, params)
      File.open(File.join(run_dir, "Condition.txt"), "w") do |f|
        f.puts "=" * 70
        f.puts "PhyloCGN 解析実行パラメータ"
        f.puts "=" * 70
        f.puts "作成日時    : #{params[:created_at]}"
        f.puts "最終更新    : #{params[:last_updated]}"
        f.puts "最終Phase   : #{params[:last_phase]}"
        f.puts "ホスト      : #{params[:hostname]}"
        f.puts ""
        f.puts "【クエリ】"
        f.puts "  タンパク質: #{CONFIG[:files][:query_protein]}"
        f.puts ""
        f.puts "【Diamond検索】"
        f.puts "  e-value   : #{CONFIG[:diamond][:evalue]}"
        f.puts "  identity  : #{CONFIG[:diamond][:identity]}%"
        f.puts "  coverage  : #{CONFIG[:diamond][:coverage]}%"
        f.puts ""
        f.puts "【ゲノム近傍解析】"
        f.puts "  updown    : #{params[:updown] || CONFIG[:params_default][:updown]}"
        f.puts ""
        f.puts "【クラスタリング / 解析】"
        f.puts "  dist      : #{params[:dist]  || CONFIG[:params_default][:dist]}"
        f.puts "  score     : #{params[:score] || CONFIG[:params_default][:score]}"
        f.puts ""
        if params[:reused_tree]
          f.puts "【再利用】"
          f.puts "  tree 元   : #{params[:reused_tree]}"
        end
        if params[:reused_neighbor]
          f.puts "  neighbor 元: #{params[:reused_neighbor]}"
        end
      end
    end

  end
end

# パス生成ヘルパー
module Paths
  class << self
    def output(filename)
      dir = File.join(RunManager.current_run_dir, "results")
      FileUtils.mkdir_p(dir)
      File.join(dir, filename)
    end

    def intermediate(filename)
      dir = File.join(RunManager.current_run_dir, "intermediate")
      FileUtils.mkdir_p(dir)
      File.join(dir, filename)
    end

    def shared(filename)
      dir = CONFIG[:dirs][:shared_resources]
      FileUtils.mkdir_p(dir)
      File.join(dir, filename)
    end

    def input(filename)
      File.join(CONFIG[:dirs][:input], filename)
    end

    def downloads(*parts)
      File.join(CONFIG[:dirs][:downloads], *parts)
    end

    def temp(filename)
      dir = File.join(RunManager.current_run_dir, "temp")
      FileUtils.mkdir_p(dir)
      File.join(dir, filename)
    end
  end
end
