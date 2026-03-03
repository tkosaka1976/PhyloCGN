// --- 変数定義 ---
let rootNode = null;
let nodeMap = new Map();
let tableRows = [];
let svg, g, zoom;
    
const colorScale = d3.scaleOrdinal(d3.schemeCategory10);

// --- 初期化 ---
function init() {
  const container = document.getElementById("viz");
  const w = container.clientWidth;
  const h = container.clientHeight;

  svg = d3.select("#viz").append("svg")
  .attr("width", "100%")
  .attr("height", "100%")
  .attr("viewBox", `0 0 ${w} ${h}`);
        
  g = svg.append("g");
        
  zoom = d3.zoom()
  .scaleExtent([0.05, 5]) // 縮小方向の制限を緩める
  .on("zoom", e => g.attr("transform", e.transform));
        
  svg.call(zoom).on("dblclick.zoom", null);
  // 初期位置は仮設定。データ読み込み後にfitTreeで調整される。
  svg.call(zoom.transform, d3.zoomIdentity.translate(40, 20).scale(0.9));
}
init();

// --- イベントリスナー ---
document.getElementById("inputJson").addEventListener("change", loadJson);
document.getElementById("inputCsv").addEventListener("change", loadCsv);
d3.selectAll("input[name='layoutMode']").on("change", updateLayout);
window.addEventListener('resize', () => { if(rootNode) fitTree(); }); // リサイズ時にフィット


// --- 1. JSON読み込み ---
function loadJson(e) {
  const file = e.target.files[0];
  if(!file) return;
  
  // ファイル名からカットオフ値
  const fileName = file.name;
  const cutMatch = fileName.match(/-cut\[(.*?)\]/);
  const infoBox = document.getElementById("tree-threshold");
  const valSpan = document.getElementById("tree-cut-val");

  if (cutMatch && cutMatch[1]) {
    valSpan.textContent = "=< " + cutMatch[1];
    infoBox.style.display = "block";
  } else {
    infoBox.style.display = "none";
  }

  const reader = new FileReader();
  reader.onload = function(evt) {
    try {
      const data = JSON.parse(evt.target.result);
      drawTree(data);
                
      d3.selectAll("input[name='layoutMode']").attr("disabled", null);

      // 既にCSVがあれば注入（上書き）
      if(tableRows.length > 0) injectData(tableRows);
                
      // 描画更新
      updateView();

    } catch(err) { alert("JSON Error: " + err); }
  };
  reader.readAsText(file);
}

// --- 2. CSV読み込み ---
function loadCsv(e) {
  const file = e.target.files[0];
  if(!file) return;
  
  // ファイル名からカットオフ値
  const fileName = file.name;
  const cutMatch = fileName.match(/-cut\[(.*?)\]/);
  const infoBox = document.getElementById("gcl-threshold");
  const valSpan = document.getElementById("gcl-cut-val");

  if (cutMatch && cutMatch[1]) {
    valSpan.textContent = ">= " + cutMatch[1];
    infoBox.style.display = "block";
  } else {
    infoBox.style.display = "none";
  }

  const reader = new FileReader();
  reader.onload = function(evt) {
    const data = d3.csvParse(evt.target.result);
    tableRows = data;
    renderTable(data);
            
    if(rootNode) {
      injectData(data);
      updateView();
    }
  };
  reader.readAsText(file);
}

// --- データ注入処理 ---
function injectData(rows) {
  rows.forEach(row => {
    const cid = row.cluster_id;
    const members = (row.GCL || "").split("|");
            
    members.forEach(m => {
      const cleanName = m.trim();
      if(cleanName && nodeMap.has(cleanName)) {
        const node = nodeMap.get(cleanName);
        // 末端ノードのみ
        if(!node.children) {
          node.data.cluster = cid; 
        }
      }
    });
  });
}

// --- 描画ロジック ---
function drawTree(data) {
  g.selectAll("*").remove();
  nodeMap.clear();

  const root = d3.hierarchy(data);
  rootNode = root;

  const container = document.getElementById("viz");
  const leafCount = root.leaves().length;
  // ノード数が多い場合は高さを確保（スクロール前提のレイアウト計算）
  const h = Math.max(container.clientHeight, leafCount * 18);
  // 右側にラベル分の余白を確保
  const w = container.clientWidth - 150;

  const clusterLayout = d3.cluster().size([h, w]);
  clusterLayout(root);

  root.descendants().forEach(d => {
    // 末端以外のClusterID削除
    if(d.children) delete d.data.cluster; 
    d.y_align = d.y; 
    d.x_final = d.x; 
    if(d.data.name) nodeMap.set(d.data.name, d);
  });

  // 距離モード計算
  root.y_dist = 0;
  root.eachBefore(d => {
    if(d.parent) d.y_dist = d.parent.y_dist + (d.data.length || 0);
  });
  const maxDist = d3.max(root.descendants(), d => d.y_dist);
  const scale = maxDist > 0 ? (w / maxDist) : 0;
  root.descendants().forEach(d => d.y_real = d.y_dist * scale);

  // リンク
  g.selectAll(".link")
  .data(root.links())
  .enter().append("path")
  .attr("class", "link")
  .attr("d", d => stepPath(d.source, d.target, "aligned"));

  // ノード
  const node = g.selectAll(".node")
  .data(root.descendants())
  .enter().append("g")
  .attr("class", "node")
  .attr("id", d => "node-" + cleanId(d.data.name))
  .attr("transform", d => `translate(${d.y_align}, ${d.x_final})`);

  node.append("circle").attr("r", 4.5);
  node.append("text").attr("dy", 3).attr("x", 8).text("");

  // 初期表示更新
  updateView();
        
  // ★描画後に画面にフィットさせる
  setTimeout(fitTree, 100);
}

// --- ★ツリーを画面にフィットさせる関数 ---
function fitTree() {
  const bounds = g.node().getBBox();
  const parent = document.getElementById("viz");
  const fullWidth = parent.clientWidth;
  const fullHeight = parent.clientHeight;
  const width = bounds.width;
  const height = bounds.height;

  if (width === 0 || height === 0) return;

  // 余白（上下左右に少し余裕を持たせる）
  const margin = { top: 20, right: 100, bottom: 20, left: 40 };
        
  const scale = Math.min(
    (fullWidth - margin.left - margin.right) / width,
    (fullHeight - margin.top - margin.bottom) / height
  );

  // 左上を基準に配置計算
  const translateX = margin.left - bounds.x * scale;
  const translateY = margin.top - bounds.y * scale;

  svg.transition()
  .duration(750)
  .call(zoom.transform, d3.zoomIdentity.translate(translateX, translateY).scale(scale));
}

// --- 表示更新 (色とラベル) ---
function updateView() {
  g.selectAll(".node").each(function(d) {
    const group = d3.select(this);
    const circle = group.select("circle");
    const text = group.select("text");
    const isLeaf = !d.children;

    // 1. 色の決定
    let fillColor = "#fff";
    if (d.data.color) {
      fillColor = d.data.color;
    } else if (d.data.cluster) {
      fillColor = colorScale(d.data.cluster);
    }
            
    if (!group.classed("highlighted")) {
      circle.style("fill", fillColor);
    }

    // 2. テキストの決定
    let label = "";
    if (isLeaf) {
      const name = d.data.name || "";
      const cid = d.data.cluster;
      label = cid ? `[${cid}] ${name}` : name;
    }
            
    text.text(label)
    .style("font-weight", d.data.cluster ? "bold" : "normal")
    .style("fill", d.data.cluster ? "#000" : "#333");
  });
}

function updateLayout() {
  const mode = this.value;
  g.selectAll(".node").transition().duration(1000)
  .attr("transform", d => `translate(${mode === "aligned" ? d.y_align : d.y_real}, ${d.x_final})`)
  .on("end", fitTree); // レイアウト変更後にもフィット
        
  g.selectAll(".link").transition().duration(1000)
  .attrTween("d", d => {
    const sY = mode === "aligned" ? [d.source.y_real, d.source.y_align] : [d.source.y_align, d.source.y_real];
    const tY = mode === "aligned" ? [d.target.y_real, d.target.y_align] : [d.target.y_align, d.target.y_real];
    const ipS = d3.interpolateNumber(sY[0], sY[1]);
    const ipT = d3.interpolateNumber(tY[0], tY[1]);
    return t => `M${ipS(t)},${d.source.x_final} V${d.target.x_final} H${ipT(t)}`;
  });
}

function renderTable(data) {
    // 1. tbodyを取得
    const tbody = d3.select("#dataTable tbody");

    // 2. ★ここが重要：既存の行をすべて削除してリセット
    tbody.selectAll("*").remove();

    // 3. データがない場合の表示
    if (!data || data.length === 0) {
        tbody.append("tr").append("td")
            .attr("colspan", 2)
            .style("text-align", "center").style("color", "#999").style("padding", "20px")
            .text("No Data");
        return;
    }

    // 4. 新しいデータで行を作成
    const rows = tbody.selectAll("tr")
        .data(data)
        .enter()
        .append("tr")
        .on("click", function(e, d) {
            // クリック時のハイライト処理
            d3.selectAll("tr").classed("selected", false);
            d3.select(this).classed("selected", true);
            highlightMembers(d.GCL);
        });

    // 5. 列の中身を作成
    rows.append("td").style("font-weight", "bold").text(d => d.cluster_id);
    rows.append("td").html(d => `<div class="gcl-cell" title="${d.GCL}">${d.GCL}</div>`);
}

function highlightMembers(gclStr) {
  d3.selectAll(".node").classed("highlighted", false);
  updateView();

  if(!gclStr) return;
  const ids = gclStr.split("|").map(s => s.trim());
  let target = null;
  ids.forEach(id => {
    if(nodeMap.has(id)) {
      d3.select("#node-" + cleanId(id)).classed("highlighted", true).raise();
      if(!target) target = nodeMap.get(id);
    }
  });
  if(target) {
    const mode = document.querySelector('input[name="layoutMode"]:checked').value;
    const x = (mode === "aligned") ? target.y_align : target.y_real;
            
    // ターゲットを画面の左寄り(1/3)・中央に持ってくる
    const viz = document.getElementById("viz");
    svg.transition().duration(750).call(
      zoom.transform, 
      d3.zoomIdentity.translate(viz.clientWidth/3, viz.clientHeight/2).scale(2).translate(-x, -target.x_final)
    );
  }
}

function stepPath(s, t, mode) {
  const sy = (mode === "aligned") ? s.y_align : s.y_real;
  const ty = (mode === "aligned") ? t.y_align : t.y_real;
  return `M${sy},${s.x_final} V${t.x_final} H${ty}`;
}

function cleanId(str) { return str ? str.replace(/[^a-zA-Z0-9-_]/g, '_') : "unknown"; }