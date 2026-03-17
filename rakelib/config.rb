require 'shellwords'
require 'fileutils'
require 'csv'
require 'yaml'

# =============================================================================
# 設定セクション（ここを編集してパラメータ調整）
# =============================================================================

VERSION = "0.9.2"

CONFIG = {

  # 入力ファイル
  files: {
    query_protein: "",
    accessions: "accessions.txt",
    bacteria_accessions: "bacteria_accessions.txt",
    archaea_accessions: "archaea_accessions.txt"
  },

  # ディレクトリ構成
  # downloads と shared_resources は大容量のため外部ディスク指定可能
  dirs: {
    input:            "input",
    output:           "output",
    downloads:        "downloads",
    shared_resources: "shared_resources"
  },
  
  # デフォルトパラメーター for do_all
  
  params_default: {
    updown: 10,
    dist:   2.0,
    score:  0.9,
  },

  # Diamond検索パラメータ
  diamond: {
    subject_size: 0, # 0: infinity
    block: 0.7,
    evalue: 1e-10,
    coverage: 80,
    identity: 35,
    sensitivity: "very-sensitive"
  },

  # mmseqs
  mmseqs: {
    cluster_mode: 1,
    sensitivity: 7.5,
    identity: 0.3,
    coverage: 0.6,
  },

  # ダウンロード設定
  download: {
    retry_wait: 0.5,
    http2_disabled: true
  },

  # ツール固有設定
  tools: {
    veryfasttree: {
      model: "lg",
      gamma: true,
      spr: 4,
      threads: 2
    },
    muscle_version: "5",
    muscle: {
      super5_threshold: 1000
    }
  },

  # API設定
  ncbi_api_key: ENV['NCBI_API_KEY'],

  # ファイル管理設定
  file_management: {
    keep_intermediate: true,
    cleanup_temp_on_success: true
  },

}

raise "NCBI_API_KEY is not set" unless CONFIG[:ncbi_api_key]
