require 'shellwords'
require 'fileutils'
require 'csv'
require 'yaml'
require 'bio'
require 'tempfile'
require 'open3'
require 'json'

VERSION = "0.9.8"

# =============================================================================
# 解析条件は input/condition.yaml を編集してください
# （テンプレート: input/condition_template.yaml）
# =============================================================================

_condition_path = File.join(__dir__, '..', 'input', 'condition.yaml')

unless File.exist?(_condition_path)
  abort <<~MSG
    [ERROR] input/condition.yaml が見つかりません。
    テンプレートからコピーして作成してください:
      cp input/condition_template.yaml input/condition.yaml
  MSG
end

_condition = YAML.load_file(_condition_path, symbolize_names: true)

CONFIG = {
  # YAMLから読み込む解析条件
  files:         _condition[:files],
  params_default: _condition[:params_default],
  diamond:       _condition[:diamond],
  mmseqs:        _condition[:mmseqs],
  tools:         _condition[:tools],

  # コード側で固定する環境設定
  dirs: {
    input:            "input",
    output:           "output",
    downloads:        "downloads",
    shared_resources: "shared_resources"
  },
  download: {
    retry_wait: 0.5,
    http2_disabled: true
  },
  file_management: {
    keep_intermediate: true,
    cleanup_temp_on_success: true
  },

  ncbi_api_key: ENV['NCBI_API_KEY'],
}

raise "NCBI_API_KEY is not set" unless CONFIG[:ncbi_api_key]