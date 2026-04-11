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

    # neighborhood / analyze_pcgn から呼ぶ（latestを使う）
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
    # 実際のファイル配置（prepare_tree.rake）に合わせたパスを使う:
    #   homologs_search_single/multi が書き出す場所:
    #     results/  : diamond_results_full.tsv(*), all_query_homolog_list.tsv, query_homolog_list.txt(multi only)
    #     intermediate/ : diamond_results_full.tsv(single), query_homolog_list.txt(single),
    #                     diamond_hits.fasta, diamond_hits.afa
    #   make_tree が書き出す場所:
    #     results/  : diamond_hits.tree, diamond_hits-converted.tree
    #     intermediate/ : diamond_hits.fasta, diamond_hits.afa
    #
    # (*) single では intermediate に書かれるが、copy元として results を期待するため
    #     homologs_search_single 側で results にもコピーしている前提。
    #     → 下記コピーマップは rake ファイルの実際の出力先に合わせて修正済み。
    def copy_phase1_from!(source_dir)
      copy_files_from(source_dir, {
        # results/ に存在するもの（make_tree, homologs_search_* の出力）
        "results/diamond_results_full.tsv"    => File.join(@current_run_dir, "results",      "diamond_results_full.tsv"),
        "results/query_homolog_list.txt"      => File.join(@current_run_dir, "results",      "query_homolog_list.txt"),
        "results/all_query_homolog_list.txt"  => File.join(@current_run_dir, "results",      "all_query_homolog_list.txt"),
        "results/diamond_hits.tree"           => File.join(@current_run_dir, "results",      "diamond_hits.tree"),
        "results/diamond_hits-converted.tree" => File.join(@current_run_dir, "results",      "diamond_hits-converted.tree"),
        # intermediate/ に存在するもの
        "intermediate/diamond_results_full.tsv" => File.join(@current_run_dir, "intermediate", "diamond_results_full.tsv"),
        "intermediate/query_homolog_list.txt"   => File.join(@current_run_dir, "intermediate", "query_homolog_list.txt"),
        "intermediate/diamond_hits.fasta"       => File.join(@current_run_dir, "intermediate", "diamond_hits.fasta"),
        "intermediate/diamond_hits.afa"         => File.join(@current_run_dir, "intermediate", "diamond_hits.afa"),
      })
    end

    # base指定時: 指定ディレクトリからPhase1+2成果物をコピー
    def copy_phase1_and_2_from!(source_dir)
      copy_phase1_from!(source_dir)
      copy_files_from(source_dir, {
        # results/ に存在するもの（neighborhood.rake の出力）
        "results/neighborhoods_metadata.csv"           => File.join(@current_run_dir, "results", "neighborhoods_metadata.csv"),
        "results/cluster_stat_cluster_id.csv"          => File.join(@current_run_dir, "results", "cluster_stat_cluster_id.csv"),
        "results/cluster_result_gene_id.csv"           => File.join(@current_run_dir, "results", "cluster_result_gene_id.csv"),
        "results/cluster_representative_functions.csv" => File.join(@current_run_dir, "results", "cluster_representative_functions.csv"),
        # intermediate/ に存在するもの
        "intermediate/neighborhoods_list.txt"    => File.join(@current_run_dir, "intermediate", "neighborhoods_list.txt"),
        "intermediate/neighborhoods_list.mfasta" => File.join(@current_run_dir, "intermediate", "neighborhoods_list.mfasta"),
        # clustering_genomic_neiborhood が intermediate に書くもの
        "intermediate/cluster_result_cluster.tsv" => File.join(@current_run_dir, "intermediate", "cluster_result_cluster.tsv"),
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
      run_dir        = current_run_dir
      condition_file = File.join(run_dir, "Condition.json")

      # ------------------------------------------------------------------
      # 既存 Condition.json があれば以下を引き継ぐ:
      #   - created_at  : 初回タイムスタンプ
      #   - updown / dist / score : 前 phase で確定した値（今回渡されなければ流用）
      # ------------------------------------------------------------------
      existing = {}
      if File.exist?(condition_file)
        begin
          existing = JSON.parse(File.read(condition_file), symbolize_names: true)
        rescue JSON::ParserError
          # 壊れていても続行
        end
      end

      # updown / dist / score は extra で明示された値を優先し、
      # なければ既存 JSON の値、なければ CONFIG デフォルトを使う
      resolved_updown = extra[:updown] || existing[:updown] || CONFIG[:params_default][:updown]
      resolved_dist   = extra[:dist]   || existing[:dist]   || CONFIG[:params_default][:dist]
      resolved_score  = extra[:score]  || existing[:score]  || CONFIG[:params_default][:score]

      # CONFIG から ncbi_api_key を除いたものを JSON 化
      config_for_json = deep_symbolize(CONFIG).reject { |k, _| k == :ncbi_api_key }

      condition = {
        created_at:   existing[:created_at] || Time.now.iso8601,
        last_updated: Time.now.iso8601,
        last_phase:   phase,
        ruby_version: RUBY_VERSION,
        git_commit:   `git rev-parse HEAD 2>/dev/null`.chomp,
        hostname:     `hostname`.chomp,
        # 解析パラメータ（途中 phase から始めた場合も含めて常に最新値を保持）
        updown:       resolved_updown,
        dist:         resolved_dist,
        score:        resolved_score,
        # 再利用情報（extra に含まれる場合のみ）
        reused_tree:     extra[:reused_tree],
        reused_neighbor: extra[:reused_neighbor],
        # CONFIG 全体（ncbi_api_key を除く）
        config: config_for_json,
      }.compact  # nil 値（reused_* が未指定の場合）を除去

      require 'json'
      File.write(condition_file, JSON.pretty_generate(condition))

      update_summary_params(resolved_updown, resolved_dist, resolved_score)
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

    # Hash のキーを再帰的にシンボルに変換（CONFIG は既にシンボルキーだが念のため）
    def deep_symbolize(obj)
      case obj
      when Hash  then obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize(v) }
      when Array then obj.map { |v| deep_symbolize(v) }
      else obj
      end
    end

    def copy_files_from(source_dir, file_map)
      Logger.info("コピー元: #{File.basename(source_dir)}")
      file_map.each do |src_rel, dest|
        src = File.join(source_dir, src_rel)
        if File.exist?(src)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
          Logger.info("  ✓ #{src_rel}")
        else
          # 存在しない場合は警告のみ（multi/single でファイル構成が違うものもある）
          Logger.info("  - #{src_rel} (スキップ: 存在しません)")
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
        row[4] = updown
        row[5] = dist
        row[6] = score
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
