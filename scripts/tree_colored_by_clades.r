library(ggtree)
library(ggplot2)
library(optparse)

optslist <- list(
    make_option("--nwk",    type="character"),
    make_option("--info",   type="character"),
    make_option("--outpng", type="character")
    )

parser <- OptionParser(option_list=optslist)
opts <- parse_args(parser)

# --- ファイル読み込み ---
tree    <- read.tree(opts$nwk)
info_df <- read.csv(opts$info)

# CSVの列名: Sequence_ID, Cluster_ID, Color_Hex, Cluster_AvgPairDist, Assembly_Accession

# --- クラスターごとの色テーブル ---
tc2color <- unique(info_df[, c("Clade_ID", "Color_Hex")])
tc2color <- tc2color[order(tc2color$Clade_ID), ]

# --- ブランチをグループ化 ---
branches <- list()
for (cl in tc2color$Clade_ID) {
  seqs <- info_df$Sequence_ID[info_df$Clade_ID == cl]
  seqs <- seqs[seqs %in% tree$tip.label]
  branches[[as.character(cl)]] <- seqs
}
tree <- groupOTU(tree, branches)

# --- 色ベクトル ---
color_values <- c("0" = "black",
                  setNames(tc2color$Color_Hex, as.character(tc2color$Clade_ID)))

# --- MRCAノードの取得（マルチとシングルトンを分離） ---
clades_multi     <- data.frame(clade=character(), node=integer(), stringsAsFactors=FALSE)
clades_singleton <- data.frame(clade=character(), node=integer(), stringsAsFactors=FALSE)

for (i in seq_len(nrow(tc2color))) {
  cl   <- tc2color$Clade_ID[i]
  seqs <- info_df$Sequence_ID[info_df$Clade_ID == cl]
  seqs <- seqs[seqs %in% tree$tip.label]
  cat("Clade", cl, ":", length(seqs), "tips\n")

  if (length(seqs) >= 2) {
    nd <- MRCA(tree, seqs)
    clades_multi <- rbind(clades_multi,
                          data.frame(clade=as.character(cl), node=nd, stringsAsFactors=FALSE))
  } else if (length(seqs) == 1) {
    nd <- which(tree$tip.label == seqs)
    clades_singleton <- rbind(clades_singleton,
                              data.frame(clade=as.character(cl), node=nd, stringsAsFactors=FALSE))
  }
}

# --- 描画 ---
g <- ggtree(
    tree,
    layout = "equal_angle",
    aes(color = group),
    show.legend = FALSE
  ) +
  scale_color_manual(values = color_values) +
  geom_treescale()

# マルチ配列クラスター: geom_cladelab
if (nrow(clades_multi) > 0) {
  g <- g + geom_cladelab(
    data    = clades_multi,
    mapping = aes(node = node, label = clade),
    fontsize = 2,
    offset   = 0
  )
}

# シングルトンクラスター: チップ座標を取得してテキストラベルを付与
if (nrow(clades_singleton) > 0) {
  tip_coords       <- g$data[g$data$isTip == TRUE, c("node", "x", "y")]
  singleton_coords <- merge(clades_singleton, tip_coords, by = "node")
  g <- g + geom_text(
    data        = singleton_coords,
    mapping     = aes(x = x, y = y, label = clade),
    inherit.aes = FALSE,
    size        = 2,
    hjust       = -0.3,
    color       = "black"
  )
}

ggsave(opts$outpng, plot = g, dpi = 300)
cat("Saved:", opts$outpng, "\n")
