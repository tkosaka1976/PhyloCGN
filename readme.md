

# PhyloCGN (Phylogeny and Conserved Genomic Neighborhood)

### **Discover the "Functional Partners" of Your Protein via Evolutionary Context.**

**Version 0.9.0 (Beta)**  
> 💡 **Note:** This is a pre-release version. Final adjustments are ongoing.

## 💡 What is PhyloCGN?
**PhyloCGN** is a bioinformatics tool designed to identify functionally related gene sets (such as **protein complexes** or **maturation factors**) by integrating two powerful evolutionary signals:

1.  **Phylogeny:** How genes have co-evolved across different species.
2.  **Genomic Neighborhood:** How genes are physically clustered on the genome.

Based on the analytical framework described in [JSME (2024)](https://www.jstage.jst.go.jp/article/jsme2/40/4/40_ME25018/_html/-char/en), this application automates the complex process of identifying conserved gene clusters that are likely to work together in the same biological pathway.

## 🎯 Target Audience
If you are an experimental biologist asking these questions, **PhyloCGN** is for you:
* *"What are the missing components of this protein complex?"*
* *"Which genes are essential for the maturation or assembly of my protein of interest?"*
* *"Is this gene cluster conserved across specific lineages, and what is its minimal functional unit?"*

## 🛠 Prerequisites & Installation

This tool requires the following command-line tools.

### 1. Software Dependencies
Please consider to install these tools into your machine.

- System: curl, unzip, ruby (sequel via gem), sqlite3 
- Bioinformatics:
  - datasets (NCBI Command Line Tool)
  - diamond (Sequence Aligner)
  - mmseqs2 (Sequence Search & Clustering)
  - seqkit (FASTA/Q Manipulation)
  - muscle5 (Multiple Sequence Alignment)
  - VeryFastTree (Phylogenetic Tree Construction)
 
### 2. Clone the Repository

```
git clone https://github.com/your_username/PhyloCGN.git
cd PhyloCGN
```

## 🚀 Usage
### 1. Prepare Input
Place your query protein sequence (FASTA format) into the "input" folder. Please make "input" folder before do that.
### 2. Configure Rakefile
Open Rakefile and ensure the file name matches your input:

```ruby
 # Edit this section in Rakefile
files: {
  query_protein: "your_protein_file.fasta"
  # Must match the file in /input
}
```

### 3. Run Analysis
Execute the full pipeline with a single command:

```bash
rake do_all
```

_To see all available tasks, run:_ ```rake -T```
### 4. Check Results
All results, including phylogenetic trees and conserved genomic neighborhood data, will be stored in the output folder.

### 5. showing the results in Web browser
view_app/read_input-tree&gcl.html can be used for showing the results. Please use this in some web browser.

## 📝 Reference
This tool implements the methodology developed in:
> Tomoyuki Kosaka and Minenosuke Matsutani, Japanese Journal of Science and Mechanical Engineering (JSME), 2024 ([https://doi.org/10.1264/jsme2.ME25018](https://doi.org/10.1264/jsme2.ME25018)).

## 🛠 Development Process & AI Collaboration
This project leverages AI assistants (Gemini and Claude) to enhance development efficiency while maintaining rigorous human oversight.  
Logic & Design: The core analytical logic and the initial architecture of the Rakefile were designed and authored by the lead developer.  
Code Generation (Gemini): Many standard modules and functional components were scaffolded using Gemini.  
Refactoring (Claude): Final refactoring and code optimization of the Rakefile were performed using Claude 3.5 Sonnet.  
  
Note: All AI-generated code has been thoroughly reviewed, modified, and validated by the developer to ensure scientific accuracy and reliability.

## ⚖️ License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.