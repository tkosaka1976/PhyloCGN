#!/usr/bin/env ruby
require 'json'
require 'optparse'

# JSONのノードをNewick文字列に再帰的に変換するメソッド
def to_newick(node, parent_cluster = nil)
  # ノード名を取得してスペースを置換
  raw_name = node['name'] || node['id'] || ''
  name = raw_name.to_s.gsub(' ', '_')
  
  # 現在のノードのクラスター情報を取得（なければ親から引き継いだものを使用）
  current_cluster = node['cluster'] || node['cluster_id'] || parent_cluster
  
  # 名前があり、かつクラスター情報が存在する場合は、前に追加する
  if current_cluster && !name.empty?
    clean_cluster = current_cluster.to_s.gsub(' ', '_')
    # 「クラスター名_元の名前」の形にする
    name = "#{clean_cluster}_#{name}"
  end
  
  # 枝の長さ
  length = node['length'] || node['distance']
  
  # 子ノードの処理
  if node['children'] && !node['children'].empty?
    # 子ノードを処理する際、現在のクラスター情報（current_cluster）を引き継がせる
    children_newick = node['children'].map { |child| to_newick(child, current_cluster) }.join(',')
    result = "(#{children_newick})#{name}"
  else
    result = "#{name}"
  end
  
  # 枝の長さがあれば追加
  result += ":#{length}" if length
  
  result
end

params = ARGV.getopts("","input:","output:")


in_fn = params["input"]#"/Volumes/Extreme\ SSD/APGNC/output/runs/20260220_03_dist2.0_up5_score0.8/results/diamond_hits-cut\[2.0\]-trim-45.json"

out_f = File.open(params["output"],"w")

begin
  # 標準入力または引数のファイルからJSONを読み込む
  #input_data = ARGF.read
  input_data = File.read(in_fn)
  json_data = JSON.parse(input_data, max_nesting: false)

  # 最後にセミコロンをつけて出力
  newick_string = to_newick(json_data) + ";"
  out_f.puts newick_string
rescue JSON::ParserError => e
  STDERR.puts "エラー: 有効なJSONデータではありません。"
  exit 1
end