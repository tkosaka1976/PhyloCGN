# PhyloCGN (Phylogeny and Conserved Genomic Neighborhood)

### **Discover the "Functional Partners" of Your Protein via Evolutionary Context.**

**Version 0.9.8 (Beta 2)**  
> 💡 **Note:** This is a nearly pre-release version.

**⚠️ Caution!**
Please use over **v0.9.5** because the tree clustering algorithm was misconstructed. Before the version, the algorithm used was max_clade, not avg_clade. Now be ave_clade calculation.

**✅ Update (v0.9.3):**
PhyloCGN now supports both single and multi-query modes for homolog search.
See **Section 2** for configuration details.

## 💡 What is PhyloCGN?
**PhyloCGN** is a bioinformatics tool designed to identify functionally related gene sets (such as **protein complexes** or **maturation factors**) by integrating two powerful evolutionary signals:

1.  **Phylogeny:** The evolutionary trajectory of protein structure and function.
2.  **Genomic Neighborhood:** How genes are physically clustered on the genome.

Based on the analytical framework described in [Kosaka and Matsutani (2025) Microbes & Environments](https://www.jstage.jst.go.jp/article/jsme2/40/4/40_ME25018/_html/-char/en), this application automates the complex process of identifying conserved gene clusters that are likely to work together in the same biological pathway.

## 🎯 Target Audience
If you are an experimental biologist asking these questions, **PhyloCGN** is for you:
* *"What are the missing components of this protein complex?"*
* *"Which genes are essential for the maturation or assembly of my protein of interest?"*
* *"Is this gene cluster conserved across specific lineages, and what is its minimal functional unit?"*

## 🛠 Prerequisites & Installation

### 0. Storage requirement 
For genomic data download and database construction, at least **60 GB** of data storage is required. (Because now downloading genomic data is all about reference genomes of NCBI)

### 1. Software Dependencies
This tool requires the following command-line tools.  
Please install these tools on your machine. In addition, these command names should be in the way.

- System: curl, unzip, ruby (rake and sequel via gem), sqlite3 
- Bioinformatics:
  - datasets (NCBI Command Line Tool)
  - diamond (Sequence Aligner)
  - mmseqs (Sequence Search & Clustering)
  - seqkit (FASTA/Q Manipulation)
  - muscle5 (Multiple Sequence Alignment)
  - VeryFastTree (Phylogenetic Tree Construction)
 
### 2. Clone the Repository

```bash
git clone https://github.com/tkosaka1976/PhyloCGN.git
cd PhyloCGN
```

## 🚀 Usage
### 1. Prepare Input
Place your query protein sequence (FASTA format) into the "input" folder. Please make the "input" folder before doing that.

### 2. Configure Rakefile
Open `rakelib/config.rb` and ensure the file name matches your input:

```ruby
# Edit this section in rakelib/config.rb
files: {
  query_protein: "your_protein_file.fasta"
  # Must match the file in /input
},
params_default: {
    updown: 10,
    dist:   2.0,
    score:  0.9,
    taxonomy: "genus", # "class", "phylum", "genus", "species"
  },
```

#### Query Mode: single vs. multi
**Single mode** (`rake prepare_tree_single`): Uses a single query protein sequence.
```ruby
files: {
  query_protein: "your_protein_file.fasta",  # used in single mode
}
```

**Multi mode** (`rake prepare_tree_multi`): Searches with multiple query sequences in a mfasta file in parallel, then merges all hits into a unified homolog list.
```ruby
files: {
  multi_query_mfasta: "your_queries.mfasta",  # used in multi mode
  multi_primary_query_position: 1,            # 0-based index; which sequence in the mfasta
                                              # to use as the primary query for tree construction
}
```
> To check the order of sequences in your mfasta: `seqkit seq -n your_queries.mfasta`

### 3. Set NCBI API key
Set env var via `export NCBI_API_KEY="XXX"` in your .zshrc or directly put in the Rakefile. It is required for downloading the genomic data.
NCBI API KEY can be obtained from [ncbi website](https://www.ncbi.nlm.nih.gov) when you make your account.

### 4. Run Analysis

> **Note for zsh users:** zsh treats `[` and `]` as glob characters. Wrap the task name in single quotes when passing arguments:
> ```bash
> rake 'do_all[10,3.0,0.9]'
> rake 'neighborhood[10]'
> rake 'analyze_pcgn[3.0,0.9]'
> ```

#### Quick start — full pipeline at once
```bash
rake do_all[updown,dist,score]

# Examples:
rake do_all[10,3.0,0.9]
rake do_all                   # uses config defaults
```

`do_all` always runs single-query mode (uses `query_protein` in config). For multi-query, use the step-by-step workflow below.

> **Reusing previous results** to skip expensive phases:
> ```bash
> rake do_all[10,3.0,0.9,20260315_001]          # reuse Phase 1 tree from a past run
> rake do_all[,,0.9,,20260315_001]              # reuse Phase 1+2 from a past run
> ```

#### Step-by-step workflow (recommended)

**Phase 1 — Homolog search & tree construction**
```bash
rake prepare_tree_single   # single query mode
rake prepare_tree_multi    # multi query mode
```

**Inspect tree & decide thresholds**
```bash
rake tree_analysis                  # uses latest run
rake tree_analysis[20260315_001]    # specify a run directory
```

**Phase 2 — Genomic neighborhood collection & clustering**
```bash
rake neighborhood[updown]                     # write results into latest run
rake neighborhood[10,20260316_001]            # copy Phase 1 from a past run → new run
rake neighborhood[10,,1]                      # force new run from latest
rake neighborhood                             # uses config defaults, latest run
```

**Phase 3 — Tree clustering & conserved gene analysis**
```bash
rake analyze_pcgn[dist,score]                 # write results into latest run
rake analyze_pcgn[3.0,0.9,20260316_001]       # copy Phase 1+2 from a past run → new run
rake analyze_pcgn[3.0,0.9,,1]                # force new run from latest
rake analyze_pcgn                             # uses config defaults, latest run
```

### 5. Check Results
All results, including phylogenetic trees and conserved genomic neighborhood data, will be stored in the output folder.

_Results files_
- **diamond_hits_cut_trim.json**: JSON file showing query homologs analyzed data (Please use in view_app) 
- **conserved_gene_ids_cut.csv**: CSV file showing GCL of the tree clades (Please use in view_app)
- **diamond_hits_cut_trim.tree**: Newick file of diamond_hits_cut_trim.json already trimmed by the clustered clade
- **tree_cluster_taxonomy.csv**: tree clade taxonomy of class level
- **cluster_representative_functions.csv**: functions of representative protein in cluster ID are shown in GCL

### 6. Showing the results in Web browser
view_app/read_input-tree&gcl.html can be used for showing the results. Please use this in a web browser.

## Available rake tasks

```
rake analyze_pcgn[dist,score,base,new_run]          # 【Phase 3】 系統樹クラスタリング→保存遺伝子解析→結果出力
rake clean                                          # Remove any temporary products
rake clobber                                        # Remove any generated files
rake clustering_genomic_neiborhood                  # genomic neighborhood のクラスター構築
rake create_accession_list_reference_genomes        # AccessionリストをNCBI FTPより取得・生成
rake do_all[updown,dist,score,reuse_tree,reuse_neighbor]  # 全Phase[1,2,3]を一括実行
rake download_genomes                               # ゲノムデータをNCBI ftpよりダウンロード
rake gathering_genomic_neiborhood[updown]           # 近傍遺伝子を集める
rake gene_cluster_db_analysis[score]                # 保存遺伝子クラスター解析
rake homologs_search_multi                          # 【multi mode】mfastaの各配列を並列Diamond検索
rake homologs_search_single                         # 【single mode】単一queryタンパク質でDiamond検索
rake make_gene_cluster_db                           # 遺伝子クラスターDBを構築
rake make_tree                                      # MSAからのTree作成
rake neighborhood[updown,base,new_run]              # 【Phase 2】 近傍遺伝子収集→クラスタリング
rake prepare_tree_multi                             # 【Phase 1 / multi】 ゲノムDL→ホモログ検索→系統樹作成
rake prepare_tree_single                            # 【Phase 1 / single】 ゲノムDL→ホモログ検索→系統樹作成
rake tree_analysis[dir]                             # 系統樹の距離分布を確認して閾値を決める
rake tree_clustering[dist]                          # 系統樹クラスタリング
rake utility:cleanup_all_intermediate               # 全実行の中間ファイルを一括削除
rake utility:cleanup_intermediate[dir]              # 中間ファイルを削除してディスク容量を節約
rake utility:init                                   # ディレクトリ構造を初期化
rake utility:list_runs                              # 過去の実行結果を一覧表示
rake utility:show_run_params[dir]                   # 特定の実行結果のパラメータを表示
rake utility:version                                # PhyloCGN バージョン確認
```

_To see all available tasks, run:_ `rake -T`

The first run time should require a huge amount of data for downloading genomic data from NCBI and constructing the mmseqs database for analysis.

## Recommended analysis steps
1. `rake prepare_tree_single` or `rake prepare_tree_multi`
2. `rake tree_analysis` or `rake tree_analysis[DIR_NAME]`
3. `rake neighborhood[updown]`
4. `rake analyze_pcgn[dist,score]`

> **Tip:** `neighborhood` and `analyze_pcgn` accept an optional `base` argument (e.g. `rake neighborhood[10,20260316_001]`) to copy Phase 1 results from a named run into a fresh run directory, making it easy to re-run later phases with different parameters without overwriting previous results.

## Note
Now, for analysis, genomic data is constructed using "all reference genomes" from the NCBI ftp site. We can change these datasets more a smaller or larger one. Tentatively, I set it like this. If someone wants to do a different dataset, please inform us, or just try it. 

## 📝 Citation & Reference

If you use PhyloCGN in your research, please cite the following paper:

**Tomoyuki Kosaka and Minenosuke Matsutani**, "Using Phylogeny and a Conserved Genomic Neighborhood Analysis to Extract and Visualize Gene Sets Involved in Target Gene Function: The Case of [NiFe]-hydrogenase and Succinate Dehydrogenase." _Microbes and Environments_, 2025, 40: ME25018.  
[https://doi.org/10.1264/jsme2.ME25018](https://doi.org/10.1264/jsme2.ME25018)

This tool implements the core methodology described in the above study with an original integration of modern bioinformatics pipelines.  

## 🛠 Development Process & AI Collaboration
This project leverages AI assistants (Gemini and Claude) to enhance development efficiency while maintaining rigorous human oversight.  
Logic & Design: The core analytical logic and the initial architecture of the Rakefile were designed and authored by the lead developer.  
Code Generation (Gemini): Many standard modules and functional components were scaffolded using Gemini.  
Refactoring (Claude): Final refactoring and code optimization of the Rakefile were performed using Claude 3.5 Sonnet.  
  
Note: All AI-generated code has been thoroughly reviewed, modified, and validated by the developer to ensure scientific accuracy and reliability.

## ⚖️ License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
