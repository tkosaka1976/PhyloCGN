require 'json'
require 'optparse'

# ==========================================
# 1. 司令塔
# ==========================================
def process_tree_node(node, exclude_clusters: [], mode: 'max')
  if is_leaf?(node)
    process_leaf_node(node)
  else
    process_internal_node(node, exclude_clusters: exclude_clusters, mode: mode)
  end
end

# ==========================================
# 2. 判定用ヘルパー関数
# ==========================================
def is_leaf?(node)
  node['children'].nil? || node['children'].empty?
end

def is_numeric_name?(name)
  name.to_s.match?(/^\d+(\.\d+)?$/) || name.to_s.empty?
end

# ==========================================
# 3. 葉（末端）だった場合の処理
# ==========================================
def process_leaf_node(node)
  if !is_numeric_name?(node['name']) && !node['cluster'].nil?
    node['name'] = "1 gene"
    return { 
      clusters: [node['cluster']], 
      tip_count: 1, 
      is_pure: true, 
      max_depth: 0.0, 
      min_depth: 0.0, 
      depth_sum: 0.0  # 平均計算用の距離の合計
    }
  else
    return { 
      clusters: [], 
      tip_count: 0, 
      is_pure: false, 
      max_depth: 0.0, 
      min_depth: 0.0, 
      depth_sum: 0.0 
    }
  end
end

# ==========================================
# 4. 内部ノード
# ==========================================
def process_internal_node(node, exclude_clusters: [], mode: 'max')
  # ① 子供たちへ再帰
  children_results = node['children'].map do |child|
    res = process_tree_node(child, exclude_clusters: exclude_clusters, mode: mode)
    
    # JSONで枝の長さが入っているキー（branch_length または length を想定）
    branch_len = child['branch_length'] || child['length'] || 0.0
    
    # このノードから子孫末端までの距離をそれぞれ計算
    res[:depth_from_here_max] = res[:max_depth] + branch_len
    res[:depth_from_here_min] = res[:min_depth] + branch_len
    # 平均用: (枝の長さ × その枝の先のtip数) を足し合わせる
    res[:depth_from_here_sum] = res[:depth_sum] + (branch_len * res[:tip_count])
    res
  end

  # ② 集計
  all_clusters = children_results.flat_map { |r| r[:clusters] }.uniq.compact
  all_pure     = children_results.all? { |r| r[:is_pure] }
  total_tips   = children_results.sum  { |r| r[:tip_count] }

  if total_tips > 0
    max_depth = children_results.map { |r| r[:depth_from_here_max] }.max || 0.0
    min_depth = children_results.map { |r| r[:depth_from_here_min] }.min || 0.0
    depth_sum = children_results.sum { |r| r[:depth_from_here_sum] }
    avg_depth = depth_sum / total_tips.to_f
  else
    max_depth = 0.0
    min_depth = 0.0
    depth_sum = 0.0
    avg_depth = 0.0
  end

  target_cluster = all_clusters.first
  is_excluded = exclude_clusters.include?(target_cluster)

  # ③ 折りたたみ判定
  if all_pure && all_clusters.size == 1 && total_tips > 0 && !is_excluded
    collapse_action!(node, target_cluster, total_tips, max_depth, min_depth, avg_depth, mode)
    return { 
      clusters: all_clusters, tip_count: total_tips, is_pure: true, 
      max_depth: max_depth, min_depth: min_depth, depth_sum: depth_sum 
    }
  else
    return { 
      clusters: all_clusters, tip_count: total_tips, is_pure: false, 
      max_depth: max_depth, min_depth: min_depth, depth_sum: depth_sum 
    }
  end
end

# ==========================================
# 5. 折りたたみ操作そのものを行う関数
# ==========================================
def collapse_action!(node, target_cluster, total_tips, max_depth, min_depth, avg_depth, mode)
  node['name'] = "#{total_tips} genes"
  node['children'] = []
  node['cluster'] = target_cluster
  
  # 全ての計算結果をJSONにメタデータとして残す（他のツールで読み込む用）
  node['max_depth'] = max_depth
  node['min_depth'] = min_depth
  node['avg_depth'] = avg_depth

  # スイッチ（mode）で指定された値を、ノード自身の枝の長さに足し合わせる
  # （これによってNewickに変換した際、木が縮まないようにする）
  added_length = case mode
                 when 'max' then max_depth
                 when 'min' then min_depth
                 when 'avg' then avg_depth
                 else max_depth # デフォルトは max にフォールバック
                 end

  # JSONのキーが 'branch_length' か 'length' かに合わせて加算
  if node.key?('branch_length')
    node['branch_length'] += added_length
  elsif node.key?('length')
    node['length'] += added_length
  else
    node['branch_length'] = added_length
  end
end

# ==========================================
# main
# ==========================================
# --mode オプションを追加 (max, min, avg)
params = ARGV.getopts("", "input:", "output:", "exclude:", "mode:")

in_fn = params["input"]
out_fn = params["output"]
exclude_clusters = params["exclude"] ? params["exclude"].split(',').map(&:to_i) : []

# モードの取得。指定がなければ 'max' をデフォルトにする。max:min:avg
mode = params["mode"] || "max"

tree_data = JSON.parse(File.read(in_fn), max_nesting: false)
process_tree_node(tree_data, exclude_clusters: exclude_clusters, mode: mode)

File.open(out_fn, "w") do |f|
  f.puts JSON.pretty_generate(tree_data, max_nesting: false) 
end