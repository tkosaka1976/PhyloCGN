require 'json'
require 'optparse'


# ==========================================
# 1. 司令塔（ exclude_clusters: [] と、コロンにする ）
# ==========================================
def process_tree_node(node, exclude_clusters: [])
  if is_leaf?(node)
    process_leaf_node(node)
  else
    # 内部ノードに渡すときも、キーワードを指定して渡す
    process_internal_node(node, exclude_clusters: exclude_clusters)
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
    return { clusters: [node['cluster']], tip_count: 1, is_pure: true }
  else
    return { clusters: [], tip_count: 0, is_pure: false }
  end
end

# ==========================================
# 4. 内部ノード（ここもキーワード引数で受け取る）
# ==========================================
def process_internal_node(node, exclude_clusters: [])
  # ① 子供たちへ再帰（キーワード付きでバケツリレー）
  children_results = node['children'].map do |child|
    process_tree_node(child, exclude_clusters: exclude_clusters)
  end
  # ② 集計
  all_clusters = children_results.flat_map { |r| r[:clusters] }.uniq.compact
  all_pure     = children_results.all? { |r| r[:is_pure] }
  total_tips   = children_results.sum  { |r| r[:tip_count] }

  # ★ ここが追加ポイント！
  # 集計されたクラスタが1種類であり、かつ、それが「除外リスト」に入っていないかチェック
  target_cluster = all_clusters.first
  is_excluded = exclude_clusters.include?(target_cluster)

  # ③ 折りたたみ判定（除外リストに入っていなければ折りたたむ）
  if all_pure && all_clusters.size == 1 && total_tips > 0 && !is_excluded
    # 実行
    collapse_action!(node, target_cluster, total_tips)
    return { clusters: all_clusters, tip_count: total_tips, is_pure: true }
  else
    # 混ざっている、もしくは「除外対象のクラスタ」だった場合は折りたたまず上へ報告
    return { clusters: all_clusters, tip_count: total_tips, is_pure: false }
  end
end

# ==========================================
# 5. 折りたたみ操作そのものを行う関数
# ==========================================
def collapse_action!(node, target_cluster, total_tips)
  node['name'] = total_tips.to_s + " genes"
  node['children'] = []
  node['cluster'] = target_cluster
end

# ==========================================


# main

params = ARGV.getopts("","input:","output:","exclude:")

in_fn = params["input"]#"diamond_hits-cut[9.5].json"
exclude_clusters = []#%w(6 8).map(&:to_i)


tree_data = JSON.parse(File.read(in_fn), max_nesting: false)
process_tree_node(tree_data, exclude_clusters: exclude_clusters)

out_fn = params["output"]#"#{File.basename(in_fn,".json")}-trim.json"
File.open(out_fn, "w") { 
  it.puts JSON.pretty_generate(tree_data, max_nesting: false) 
}


