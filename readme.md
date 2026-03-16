# PhyloCGN (Phylogeny and Conserved Genomic Neighborhood)

### **Discover the "Functional Partners" of Your Protein via Evolutionary Context.**

**Version 0.9.1 (Beta)**  
> 💡 **Note:** This is a pre-release version. Final adjustments are ongoing.

**⚠️ Current Limitation (v0.9.1-beta):**
PhyloCGN currently supports a single amino acid sequence as input. This design ensures that the phylogenetic tree is correctly rooted and focused on the specific protein of interest. For multiple targets, please run them as separate tasks. Multi-sequence selection logic is planned for future updates.

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
For genomic data download and database construction, at least **60 GB** of data storage is required. (Because now downloading genomic data is all reference genomes from NCBI ftp server)

### 1. Software Dependencies
This tool requires the following command-line tools.  
Please install these tools on your machine. In addition, these command names should be in the way.

- System: curl, unzip, ruby (sequel via gem), sqlite3 
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
Open Rakefile and ensure the file name matches your input:

```ruby
 # Edit this section in Rakefile
files: {
  query_protein: "your_protein_file.fasta"
  # Must match the file in /input
}
```

### 3. Set NCBI API key
Set env var via `export NCBI_API_KEY="XXX"` in your .zshrc or directly put in the Rakefile. It is required for downloading the genomic data.
NCBI API KEY can be obtained from [ncbi website](https://www.ncbi.nlm.nih.gov) when you make your account.

### 4. Run Analysis
Execute the full pipeline with a single command:

```bash
rake do_all
```

_To see all available tasks, run:_ `rake -T`

- rake clean                          # Remove any temporary products
- rake cleanup_all_intermediate       # 全実行の中間ファイルを一括削除
- rake cleanup_intermediate           # 中間ファイルを削除してディスク容量を節約 [run_dir=DIR_NAM...
- rake clobber                        # Remove any generated files
- rake clustering_genomic_neiborhood  # genomic neiborhood のクラスター構築
- rake do_all                         # 全解析パイプラインを実行
- rake download_genomes               # ゲノムデータをNCBI ftpよりダウンロード。error_list.tx...
- rake gathering_genomic_neiborhood   # 近傍遺伝子を集める
- rake homologs_search                # queryのホモログをgenome dbよりdiamondで探す
- rake init                           # ディレクトリ構造を初期化
- rake list_runs                      # 過去の実行結果を一覧表示
- rake make_tree                      # MSAからのTree作成
- rake reanalyze                      # 最新(latest)の結果を使い、閾値を変更して再計算する
- rake show_run_params                # 特定の実行結果のパラメータを表示 [run_dir=DIR_NAME]
- rake tree_analysis                  # 系統樹の閾値調整 (使用法: rake tree_analysis [DI...

The first run time should require a huge amount of data for downloading genomic data from NCBI and constructing the mmseqs database for analysis.

### 5. Check Results
All results, including phylogenetic trees and conserved genomic neighborhood data, will be stored in the output folder.

_Results files_
- **diamond_hits_cut_trim.json**: JSON file showing query homologs analyzed data (Please use in view_app) 
- **conserved_gene_ids_cut.csv**: CSV file showing GCL of the tree clades (Please use in view_app)
- **diamond_hits_cut_trim.tree**: Newick file of diamond_hits_cut_trim.json already trimmed by the clusterd clade
- **tree_cluster_taxonomy.csv**: tree clade taxonomy of class level
- **cluster_representative_functions.csv**: functions of representative protein in cluster ID are shown in GCL

### 6. Showing the results in Web browser
view_app/read_input-tree&gcl.html can be used for showing the results. Please use this in a web browser.

## Recommended analysis steps
1. rake do_all
2. rake tree_analysis [latest_output_runs_DIR_name]
3. Change the value of tree_distance_threshold: in Rakefile.rb based on the results of tree_analysis
or directly change the env value from the command line.
4. rake reanalyze
(reanalyze only on the latest results; therefore, tree_analysis should be done for the latest data)


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
