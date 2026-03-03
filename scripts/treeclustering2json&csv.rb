require 'json'
require 'csv'
require 'optparse'

# ==========================================
# 設定
# ==========================================

# ★閾値 (TreeClusterの -t オプションに相当)
params = ARGV.getopts("","threshold:0.5","input:","output:")

THRESHOLD   = params["threshold"].to_f

INPUT_FILE  = params["input"]
OUTPUT_CSV  = "#{params["output"]}_cut.csv"
OUTPUT_JSON = "#{params["output"]}_cut.json"
#OUTPUT_CSV  = "#{params["output"]}-cut[#{THRESHOLD}].csv"
#OUTPUT_JSON = "#{params["output"]}-cut[#{THRESHOLD}].json"


# ==========================================
# クラス定義
# ==========================================

class Node
  attr_accessor :name, :length, :children
  # 解析用プロパティ
  attr_accessor :height         # このノードから最も遠い葉までの距離
  attr_accessor :diameter       # このノード以下の最大ペア距離（直径）
  attr_accessor :cluster_id     # 割り当てられたクラスタID
  attr_accessor :color          # 色

  def initialize
    @name = ""
    @length = 0.0
    @children = []
    @cluster_id = nil
    @height = 0.0
    @diameter = 0.0
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
      diameter: @diameter.round(6),
      children: @children.map(&:to_h)
    }
  end
end

class StrictTreeClusterer
  def initialize(file_path)
    content = File.read(file_path).strip
    puts "Parsing Newick file..."
    @root = parse_newick_robust(content)
    puts " -> Total leaves: #{@root.get_leaves.size}"
    
    # クラスタごとの情報を保存するハッシュ { id => { diameter: 0.123, ... } }
    @cluster_stats = {}

    # 1. 幾何情報の計算（ボトムアップ）
    puts "Calculating node heights and diameters..."
    calculate_geometry(@root)
    puts " -> Root Diameter: #{@root.diameter.round(6)}"
  end

  def run(threshold)
    puts "Clustering with Threshold = #{threshold} (Max-Clade Method)..."
    @cluster_counter = 0
    @threshold = threshold
    @cluster_stats = {} # リセット

    # 2. クラスタリング判定（トップダウン）
    decompose_tree(@root)
    
    # 3. シングルトン処理（漏れ防止）
    assign_singletons(@root)
    
    puts " -> Generated #{@cluster_counter} clusters."
  end
  
  def save_outputs
    # 色付け
    color_map = generate_colors(@cluster_counter)
    leaves = @root.get_leaves
    
    # CSV出力
    CSV.open(OUTPUT_CSV, "w") do |csv|
      # ヘッダー
      csv << %w"Sequence_ID Cluster_ID Color_Hex Cluster_Diameter"
      
      leaves.each do |leaf|
        # クラスタIDに対応する色
        cid = leaf.cluster_id
        color = color_map[cid] || "#000000"
        
        # ★ここで保存しておいた直径を取り出す
        diam_val = @cluster_stats[cid] ? @cluster_stats[cid][:diameter] : 0.0
        
        name_str = (leaf.name.nil? || leaf.name.strip.empty?) ? "Unnamed" : leaf.name
        
        # CSV書き込み
        csv << [name_str, cid, color, diam_val.round(6)]
      end
    end
    puts "✅ Saved CSV: #{OUTPUT_CSV}"

    # JSON出力
    File.open(OUTPUT_JSON, "w") { |f| f.write(JSON.pretty_generate(@root.to_h, max_nesting: false)) }
    puts "✅ Saved JSON: #{OUTPUT_JSON}"
  end

  private

  # --- A. 幾何計算 (Bottom-Up) ---
  def calculate_geometry(node)
    if node.is_leaf?
      node.height = 0.0
      node.diameter = 0.0
      return
    end

    # 子ノードを再帰計算
    node.children.each { |c| calculate_geometry(c) }

    # Heightの計算: 最も深い子供への距離 (子Height + 子への枝)
    paths_to_tips = node.children.map { |c| c.height + c.length }
    node.height = paths_to_tips.max || 0.0

    # Diameterの計算
    # 1. このノードをまたぐパス (Top 2 heights)
    cross_diameter = 0.0
    if paths_to_tips.size >= 2
      sorted = paths_to_tips.sort.reverse
      cross_diameter = sorted[0] + sorted[1]
    elsif paths_to_tips.size == 1
      cross_diameter = paths_to_tips[0]
    end

    # 2. 子ノード内部の最大直径 (すでに計算済みの子のDiameter)
    max_child_diameter = node.children.map(&:diameter).max || 0.0

    # 大きい方を採用
    node.diameter = [cross_diameter, max_child_diameter].max
  end

  # --- B. 分割ロジック (Top-Down) ---
  def decompose_tree(node)
    return if node.cluster_id # 既に親で処理済みならスキップ

    if node.diameter <= @threshold
      # 条件クリア -> ここをクラスタとする
      @cluster_counter += 1
      
      # ★直径情報を記録
      @cluster_stats[@cluster_counter] = { diameter: node.diameter }
      
      fill_cluster_id(node, @cluster_counter)
    else
      # 条件満たさず -> 子供へ
      if node.is_leaf?
        # 葉なのに閾値を超えている場合（通常ありえないが、負の閾値などのガード）
        @cluster_counter += 1
        @cluster_stats[@cluster_counter] = { diameter: 0.0 }
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
      # シングルトンの直径は0
      @cluster_stats[@cluster_counter] = { diameter: 0.0 }
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
      map[i] = hsl_to_hex(hue, 0.75, 0.45) # 視認しやすいよう彩度・輝度を調整
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
puts "--- Start Strict TreeCluster Logic ---"
clusterer = StrictTreeClusterer.new(INPUT_FILE)
clusterer.run(THRESHOLD)
clusterer.save_outputs
puts "--- Done ---"