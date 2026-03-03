require 'json'

# --- 設定 ---
INPUT_FILE = ARGV.shift

# --- クラス定義 ---
class Node
  attr_accessor :name, :length, :children
  def initialize; @children = []; @length = 0.0; end
  def is_leaf?; @children.empty?; end
  
  def get_leaves
    return [self] if is_leaf?
    @children.flat_map(&:get_leaves)
  end

  # デバッグ用: ツリー全体の枝の長さをリストアップ
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
  end

  # メイン処理
  def analyze
    puts "=== 1. Data Statistics ==="
    
    # 全枝の長さを取得して統計を出す
    all_lengths = @root.collect_lengths
    # ルートの長さ(0)や極小の誤差を除外して統計を見る
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
    puts "   Max Length:    #{max_len.round(6)}"
    puts "   Avg Length:    #{avg_len.round(6)}"
    puts "   Median Length: #{median.round(6)}"
    puts "   Total Nodes:   #{all_lengths.size}"
    puts ""

    puts "=== 2. Threshold Simulation ==="
    puts "閾値(Threshold)を変えた時のクラスタ数をシミュレーションします。"
    puts "目標のクラスタ数（例: 20〜50個）に近い行の Threshold を選んでください。"
    puts ""
    puts "Threshold | Clusters | Singletons | Avg Size"
    puts "-" * 45

    # 中央値や最大値を基準にスイープ範囲を決める
    # (極端に小さい値から最大値の半分くらいまでを試す)
    
    # 範囲設定: 中央値の1/10 〜 最大値の間で対数的に刻む
    start_val = median > 0 ? median / 5.0 : 0.0001
    end_val = max_len
    
    # 10段階で試す
    steps = []
    curr = start_val
    while curr <= end_val
      steps << curr
      curr *= 1.8 # 倍々で増やしていく
    end
    # きりのいい数字を追加
    steps += [0.001, 0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0, 10.0]
    steps = steps.uniq.sort.select { |v| v > 0 }

    steps.each do |th|
      clusters = simulate_clustering(@root, th)
      count = clusters.size
      singletons = clusters.count { |c| c[:count] == 1 }
      avg_size = count > 0 ? (clusters.map { |c| c[:count] }.sum.to_f / count) : 0

      # 見やすくフォーマット出力
      printf "%9.5f | %8d | %10d | %8.1f\n", th, count, singletons, avg_size
    end
    puts "-" * 45
  end

  private

  # クラスタリングシミュレーション (AvgCladeの簡易版として直径を使用)
  def simulate_clustering(node, threshold)
    dist = get_max_diameter(node)
    if dist <= threshold
      return [{ node: node, count: count_leaves(node) }]
    else
      results = []
      node.children.each do |child|
        results += simulate_clustering(child, threshold)
      end
      return results
    end
  end

  def count_leaves(node)
    return 1 if node.is_leaf?
    node.children.sum { |c| count_leaves(c) }
  end

  def get_max_diameter(node)
    return 0.0 if node.is_leaf?
    depths = node.children.map { |c| get_max_depth(c) + c.length }
    # 子が1つの場合はその深さ、2つ以上の場合は最も深い2つの和（直径）
    if depths.size == 1
      depths[0]
    else
      depths.sort.last(2).sum
    end
  end

  def get_max_depth(node)
    return 0.0 if node.is_leaf?
    node.children.map { |c| get_max_depth(c) + c.length }.max
  end

  # --- 改良版 Newick Parser ---
  # トークン分割をより堅牢に変更しました
  def parse_newick(str)
    # 1. 改行などを除去
    str = str.strip.gsub(/[\r\n]/, '')
    # 2. 構造記号の前後にスペースを入れてからsplit (数値と記号を確実に分離)
    tokens = str.gsub(/([(),:;])/, ' \1 ').split(/\s+/).reject(&:empty?)

    root = Node.new
    root.name = "root"
    current = root
    ancestors = []
    
    # 状態管理
    state = :start # :start, :name, :length

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
        # 名前 または 長さ
        if state == :length
          # 数値変換 (エラーなら0.0)
          val = Float(token) rescue 0.0
          current.length = val
          state = :start
        else
          current.name = token
        end
      end
    end

    # ルートの整形（ルート直下に1つしか子供がいない場合、その子供をルートとみなす処理）
    if root.children.size == 1 && root.name == "root"
      # ルート自体に長さがついていた場合、子に加算
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