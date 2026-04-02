require 'json'
require 'csv'
require 'optparse'

# ==========================================
# 設定
# ==========================================

params = ARGV.getopts("","threshold:0.5","input:","output:")

THRESHOLD   = params["threshold"].to_f
INPUT_FILE  = params["input"]
OUTPUT_CSV  = "#{params["output"]}_cut.csv"
OUTPUT_JSON = "#{params["output"]}_cut.json"


# ==========================================
# クラス定義
# ==========================================

class Node
  attr_accessor :name, :length, :children
  # 解析用プロパティ
  attr_accessor :cluster_id   # 割り当てられたクラスタID
  attr_accessor :color        # 色

  # avg_clade 用プロパティ
  attr_accessor :num_leaves        # このノード以下の葉の数
  attr_accessor :total_leaf_dist   # 各葉からこのノードまでの距離合計
  attr_accessor :total_pair_dist   # クレード内の全ペアワイズ距離合計
  attr_accessor :avg_pair_dist     # 平均ペアワイズ距離

  def initialize
    @name = ""
    @length = 0.0
    @children = []
    @cluster_id = nil
    @num_leaves = 0
    @total_leaf_dist = 0.0
    @total_pair_dist = 0.0
    @avg_pair_dist = 0.0
  end

  def is_leaf?
    @children.empty?
  end

  def get_leaves
    return [self] if is_leaf?
    @children.flat_map(&:get_leaves)
  end

  def to_h
    {
      name: @name,
      length: @length,
      cluster: @cluster_id,
      avg_pair_dist: @avg_pair_dist.round(6),
      children: @children.map(&:to_h)
    }
  end
end

class AvgCladeTreeClusterer
  def initialize(file_path)
    content = File.read(file_path).strip
    puts "Parsing Newick file..."
    @root = parse_newick_robust(content)
    puts " -> Total leaves: #{@root.get_leaves.size}"

    @cluster_stats = {}

    # 1. avg_clade用の幾何情報計算（ボトムアップ）
    puts "Calculating avg_clade geometry (bottom-up)..."
    calculate_avg_geometry(@root)
    puts " -> Root avg_pair_dist: #{@root.avg_pair_dist.round(6)}"
  end

  def run(threshold)
    puts "Clustering with Threshold = #{threshold} (Avg-Clade Method)..."
    @cluster_counter = 0
    @threshold = threshold
    @cluster_stats = {}

    # 2. クラスタリング判定（トップダウン）
    decompose_tree(@root)

    # 3. シングルトン処理（漏れ防止）
    assign_singletons(@root)

    puts " -> Generated #{@cluster_counter} clusters."
  end

  def save_outputs
    color_map = generate_colors(@cluster_counter)
    leaves = @root.get_leaves

    CSV.open(OUTPUT_CSV, "w") do |csv|
      csv << %w"Sequence_ID Clade_ID Color_Hex Clade_AvgPairDist"
      leaves.each do |leaf|
        cid = leaf.cluster_id
        color = color_map[cid] || "#000000"
        avg_val = @cluster_stats[cid] ? @cluster_stats[cid][:avg_pair_dist] : 0.0
        name_str = (leaf.name.nil? || leaf.name.strip.empty?) ? "Unnamed" : leaf.name
        csv << [name_str, cid, color, avg_val.round(6)]
      end
    end
    puts "✅ Saved CSV: #{OUTPUT_CSV}"

    File.open(OUTPUT_JSON, "w") { |f| f.write(JSON.pretty_generate(@root.to_h, max_nesting: false)) }
    puts "✅ Saved JSON: #{OUTPUT_JSON}"
  end

  private

  # --- A. avg_clade幾何計算 (Bottom-Up) ---
  # TreeCluster.py の min_clusters_threshold_avg_clade と同じロジック
  def calculate_avg_geometry(node)
    if node.is_leaf?
      node.num_leaves      = 1
      node.total_pair_dist = 0.0
      node.total_leaf_dist = 0.0
      node.avg_pair_dist   = 0.0
      return
    end

    node.children.each { |c| calculate_avg_geometry(c) }

    # 子が2つのみ（prepでpolytomyが解消されている前提）
    # ※ ここでは子が3つ以上でも対応できるよう汎用的に実装
    node.num_leaves = node.children.sum(&:num_leaves)

    # 各子ノードのtotal_leaf_distをこのノード基準に更新
    # total_leaf_dist_thru_c = c.total_leaf_dist + c.num_leaves * c.length
    total_leaf_dist_thru = node.children.map do |c|
      c.total_leaf_dist + (c.num_leaves * c.length)
    end

    node.total_leaf_dist = total_leaf_dist_thru.sum

    # ペアワイズ距離合計の計算
    # = 各子クレード内のペア合計 + クレードをまたぐペア合計
    #
    # クレードをまたぐペア(a in c_i, b in c_j, i≠j)の距離合計:
    #   Σ_{i<j} (total_leaf_dist_thru[i] * num_leaves[j]
    #           + total_leaf_dist_thru[j] * num_leaves[i])
    #
    within_pair_dist = node.children.sum(&:total_pair_dist)

    across_pair_dist = 0.0
    node.children.each_with_index do |ci, i|
      node.children.each_with_index do |cj, j|
        next if j <= i
        across_pair_dist += total_leaf_dist_thru[i] * cj.num_leaves
        across_pair_dist += total_leaf_dist_thru[j] * ci.num_leaves
      end
    end

    node.total_pair_dist = within_pair_dist + across_pair_dist

    # 平均ペアワイズ距離 = 合計 / ペア数(nC2)
    n = node.num_leaves
    pair_count = (n * (n - 1)) / 2.0
    node.avg_pair_dist = pair_count > 0 ? node.total_pair_dist / pair_count : 0.0
  end

  # --- B. 分割ロジック (Top-Down) ---
  def decompose_tree(node)
    return if node.cluster_id

    if node.avg_pair_dist <= @threshold
      # 条件クリア → ここをクラスタとする
      @cluster_counter += 1
      @cluster_stats[@cluster_counter] = { avg_pair_dist: node.avg_pair_dist }
      fill_cluster_id(node, @cluster_counter)
    else
      if node.is_leaf?
        # 葉なのに閾値超え（通常ありえないがガード）
        @cluster_counter += 1
        @cluster_stats[@cluster_counter] = { avg_pair_dist: 0.0 }
        node.cluster_id = @cluster_counter
      else
        node.children.each { |c| decompose_tree(c) }
      end
    end
  end

  def fill_cluster_id(node, id)
    node.cluster_id = id
    node.children.each { |c| fill_cluster_id(c, id) }
  end

  def assign_singletons(node)
    if node.is_leaf? && node.cluster_id.nil?
      @cluster_counter += 1
      @cluster_stats[@cluster_counter] = { avg_pair_dist: 0.0 }
      node.cluster_id = @cluster_counter
    end
    node.children.each { |c| assign_singletons(c) }
  end

  # --- C. Newick Parser ---
  def parse_newick_robust(str)
    str = str.strip.gsub(/[\r\n]/, '')
    tokens = str.gsub(/([(),:;])/, ' \1 ').split(/\s+/).reject(&:empty?)

    root = Node.new
    current = root; ancestors = []; state = :start

    tokens.each do |token|
      case token
      when '('
        n = Node.new; current.children << n; ancestors.push(current); current = n; state = :start
      when ','
        current = ancestors.last; n = Node.new; current.children << n; current = n; state = :start
      when ')'
        current = ancestors.pop; state = :post_node
      when ':'
        state = :length
      when ';'
        break
      else
        if state == :length
          current.length = Float(token) rescue 0.0; state = :start
        else
          current.name = token
        end
      end
    end

    if root.children.size == 1
      real_root = root.children[0]
      real_root.length += root.length
      return real_root
    end
    root
  end

  # --- D. 色生成 ---
  def generate_colors(n)
    map = {}
    (1..n).each do |i|
      hue = ((i * 137.5) % 360).round
      map[i] = hsl_to_hex(hue, 0.75, 0.45)
    end
    map
  end

  def hsl_to_hex(h, s, l)
    c = (1 - (2 * l - 1).abs) * s
    x = c * (1 - ((h / 60.0) % 2 - 1).abs)
    m = l - c / 2.0
    r,g,b=0,0,0
    if h<60;r,g,b=c,x,0;elsif h<120;r,g,b=x,c,0;elsif h<180;r,g,b=0,c,x;elsif h<240;r,g,b=0,x,c;elsif h<300;r,g,b=x,0,c;else;r,g,b=c,0,x;end
    hex = ->(v){ "%02x" % ((v+m)*255).round }
    "##{hex[r]}#{hex[g]}#{hex[b]}"
  end
end

# ==========================================
# 実行
# ==========================================
puts "--- Start Avg-Clade TreeCluster Logic ---"
clusterer = AvgCladeTreeClusterer.new(INPUT_FILE)
clusterer.run(THRESHOLD)
clusterer.save_outputs
puts "--- Done ---"
