require 'json'

# --- 設定 ---
INPUT_FILE = ARGV.shift

# --- クラス定義 ---
class Node
  attr_accessor :name, :length, :children
  # avg_clade用プロパティ
  attr_accessor :num_leaves, :total_leaf_dist, :total_pair_dist, :avg_pair_dist

  def initialize
    @children = []
    @length = 0.0
    @num_leaves = 0
    @total_leaf_dist = 0.0
    @total_pair_dist = 0.0
    @avg_pair_dist = 0.0
  end

  def is_leaf?; @children.empty?; end

  def get_leaves
    return [self] if is_leaf?
    @children.flat_map(&:get_leaves)
  end

  def collect_lengths
    my_len = [@length]
    @children.each { |c| my_len += c.collect_lengths }
    my_len
  end
end

class ThresholdTuner
  def initialize(file_path)
    content = File.read(file_path).strip
    @root = parse_newick(content)
    # ボトムアップでavg_pair_distを事前計算
    calculate_avg_geometry(@root)
  end

  def analyze
    puts "=== 1. Data Statistics ==="

    all_lengths = @root.collect_lengths
    valid_lengths = all_lengths.select { |l| l > 0.0 }

    if valid_lengths.empty?
      puts "❌ Error: Branch lengths are all 0.0 or could not be parsed."
      return
    end

    max_len = valid_lengths.max
    avg_len = valid_lengths.sum / valid_lengths.size
    sorted = valid_lengths.sort
    median = sorted[sorted.size / 2]

    puts "✅ Successfully parsed branch lengths!"
    puts "   Max Length:        #{max_len.round(6)}"
    puts "   Avg Length:        #{avg_len.round(6)}"
    puts "   Median Length:     #{median.round(6)}"
    puts "   Total Nodes:       #{all_lengths.size}"
    puts "   Root avg_pair_dist: #{@root.avg_pair_dist.round(6)}"
    puts ""

    puts "=== 2. Threshold Simulation (Avg-Clade) ==="
    puts "閾値(Threshold)を変えた時のクラスタ数をシミュレーションします。"
    puts "判定基準: クレード内の平均ペアワイズ距離 <= Threshold"
    puts "目標のクラスタ数（例: 20〜50個）に近い行の Threshold を選んでください。"
    puts ""
    puts "Threshold | Clusters | Singletons | Avg Size"
    puts "-" * 45

    start_val = median > 0 ? median / 5.0 : 0.0001
    end_val = max_len

    steps = []
    curr = start_val
    while curr <= end_val
      steps << curr
      curr *= 1.8
    end
    steps += [0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0, 10.0]
    steps = steps.uniq.sort.select { |v| v > 0 }

    steps.each do |th|
      clusters = simulate_avg_clade(@root, th)
      count = clusters.size
      singletons = clusters.count { |c| c[:count] == 1 }
      avg_size = count > 0 ? (clusters.map { |c| c[:count] }.sum.to_f / count) : 0

      printf "%9.5f | %8d | %10d | %8.1f\n", th, count, singletons, avg_size
    end
    puts "-" * 45
  end

  private

  # --- avg_clade幾何計算 (Bottom-Up) ---
  # TreeCluster.py の min_clusters_threshold_avg_clade と同じロジック
  def calculate_avg_geometry(node)
    if node.is_leaf?
      node.num_leaves      = 1
      node.total_leaf_dist = 0.0
      node.total_pair_dist = 0.0
      node.avg_pair_dist   = 0.0
      return
    end

    node.children.each { |c| calculate_avg_geometry(c) }

    node.num_leaves = node.children.sum(&:num_leaves)

    # 各子のtotal_leaf_distをこのノード基準に換算
    total_leaf_dist_thru = node.children.map do |c|
      c.total_leaf_dist + (c.num_leaves * c.length)
    end

    node.total_leaf_dist = total_leaf_dist_thru.sum

    # クレード内ペアワイズ距離合計
    # = 各子クレード内のペア合計 + クレードをまたぐペア合計
    within = node.children.sum(&:total_pair_dist)

    across = 0.0
    node.children.each_with_index do |ci, i|
      node.children.each_with_index do |cj, j|
        next if j <= i
        across += total_leaf_dist_thru[i] * cj.num_leaves
        across += total_leaf_dist_thru[j] * ci.num_leaves
      end
    end

    node.total_pair_dist = within + across

    n = node.num_leaves
    pair_count = (n * (n - 1)) / 2.0
    node.avg_pair_dist = pair_count > 0 ? node.total_pair_dist / pair_count : 0.0
  end

  # --- avg_cladeシミュレーション (Top-Down) ---
  # avg_pair_dist <= threshold のクレードをクラスタとする
  def simulate_avg_clade(node, threshold)
    if node.avg_pair_dist <= threshold
      return [{ node: node, count: node.num_leaves }]
    elsif node.is_leaf?
      return [{ node: node, count: 1 }]
    else
      results = []
      node.children.each { |c| results += simulate_avg_clade(c, threshold) }
      results
    end
  end

  # --- Newick Parser ---
  def parse_newick(str)
    str = str.strip.gsub(/[\r\n]/, '')
    tokens = str.gsub(/([(),:;])/, ' \1 ').split(/\s+/).reject(&:empty?)

    root = Node.new
    root.name = "root"
    current = root
    ancestors = []
    state = :start

    tokens.each do |token|
      case token
      when '('
        new_node = Node.new
        current.children << new_node
        ancestors.push(current)
        current = new_node
        state = :start
      when ','
        current = ancestors.last
        new_node = Node.new
        current.children << new_node
        current = new_node
        state = :start
      when ')'
        current = ancestors.pop
        state = :name_or_length
      when ':'
        state = :length
      when ';'
        break
      else
        if state == :length
          current.length = Float(token) rescue 0.0
          state = :start
        else
          current.name = token
        end
      end
    end

    if root.children.size == 1 && root.name == "root"
      root.children[0].length += root.length
      return root.children[0]
    end

    root
  end
end

# --- 実行 ---
puts "Checking #{INPUT_FILE} ..."
tuner = ThresholdTuner.new(INPUT_FILE)
tuner.analyze
