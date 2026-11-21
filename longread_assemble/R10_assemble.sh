#!/bin/bash
#
# R10.4.1 (FLO-MIN114 / SQK-RBK114-24) ロングリード単独アセンブリ・パイプライン
#
# 処理の流れ（株ごと）:
#   1. Guppy     : fast5 のベースコール
#   2. NanoPlot  : リードの QC
#   3. seqkit    : pass リードの統合と ID の重複修正
#   4. Filtlong  : 統合後のリード全体に対するフィルタリング
#   5. Flye      : アセンブリ（--nano-hq）
#   6. Medaka    : ポリッシング
#   7. Kleborate : 型別・病原因子・薬剤耐性遺伝子の検出
#
# 入力: rawdata2/<株名>/ 以下の fast5 ファイル
# 出力: output/<株名>/ 以下。ログは output/<株名>/log/ に保存する。
#
# 使い方:
#   MEDAKA_MODEL=<モデル名> bash R10_assemble.sh
#
# 【要確認】MEDAKA_MODEL
#   Medaka のモデルは、Guppy がベースコールに使った設定（hac / sup、Guppy のバージョン）
#   と対応するものを指定する必要がある。R10.4.1 用のモデルは
#   r1041_e82_400bps_hac_... / r1041_e82_400bps_sup_... のような名前だが、正確な名前は
#   `medaka tools list_models` の出力と Guppy の設定ファイル名を照合して決めること。
#   旧スクリプトで指定していた r10_min_high_g340 は R10.3 用であり、本データには対応しない。
#
# 【要確認】バーコード
#   SQK-RBK114-24 はバーコード付きキットである。rawdata2/<株名>/ が株ごとに
#   すでに振り分け済みのデータであることを前提としている。多重化されたままの場合は、
#   Guppy に --barcode_kits SQK-RBK114-24 を付けてバーコードごとに振り分ける必要がある。

set -euo pipefail

# ==== 設定 ===================================================================
samples=("Kp03" "Kp16" "Kp32" "Kp40" "Kp53" "Kp58")

RAW_DIR="rawdata2"
OUT_ROOT="output"

FLOWCELL="FLO-MIN114"
KIT="SQK-RBK114-24"
GPU_DEVICE="cuda:0"

THREADS="${THREADS:-48}"

# Filtlong の条件（統合後のリード全体に適用する）
MIN_LENGTH=1000
KEEP_PERCENT=90

# Medaka のモデル【要確認】未指定の場合は実行前に停止する
: "${MEDAKA_MODEL:?MEDAKA_MODEL が未指定です。冒頭のコメントを参照し、ベースコール設定に対応するモデル名を指定してください（例: MEDAKA_MODEL=<モデル名> bash R10_assemble.sh）}"
# =============================================================================

log() { echo "[$(date '+%F %T')] $*"; }

# 必要なコマンドが揃っているかを最初に確認する
for cmd in guppy_basecaller NanoPlot seqkit filtlong flye medaka_consensus kleborate; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "エラー: $cmd が見つかりません。conda 環境を確認してください。" >&2
    exit 1
  fi
done

for sample in "${samples[@]}"; do
  out="$OUT_ROOT/$sample"
  logdir="$out/log"

  if [ ! -d "$RAW_DIR/$sample" ]; then
    echo "エラー: 入力ディレクトリ $RAW_DIR/$sample がありません。" >&2
    exit 1
  fi

  for d in guppy nano_summary filtered flye_assembly medaka kleborate log; do
    mkdir -p "$out/$d"
  done

  log "[$sample] 開始"

  # 1. Guppy -----------------------------------------------------------------
  log "[$sample] Guppy によるベースコール"
  guppy_basecaller --flowcell "$FLOWCELL" --kit "$KIT" -x "$GPU_DEVICE" \
    -i "$RAW_DIR/$sample" -s "$out/guppy" -r \
    > "$logdir/guppy.log" 2>&1

  # 2. NanoPlot ---------------------------------------------------------------
  log "[$sample] NanoPlot による QC"
  NanoPlot --summary "$out/guppy/sequencing_summary.txt" --loglength \
    -t "$THREADS" -o "$out/nano_summary" \
    > "$logdir/nanoplot.log" 2>&1

  # 3. pass リードの統合と ID の重複修正 ---------------------------------------
  # Guppy のバージョンにより .fastq と .fastq.gz のどちらも出力され得るため、両方を対象にする
  log "[$sample] pass リードの統合"
  shopt -s nullglob
  pass_reads=("$out"/guppy/pass/*.fastq "$out"/guppy/pass/*.fastq.gz)
  shopt -u nullglob
  if [ "${#pass_reads[@]}" -eq 0 ]; then
    echo "エラー: $out/guppy/pass に fastq がありません。" >&2
    exit 1
  fi
  seqkit seq -j "$THREADS" "${pass_reads[@]}" -o "$out/filtered/combined.fastq.gz"
  seqkit rename -j "$THREADS" "$out/filtered/combined.fastq.gz" \
    -o "$out/filtered/combined.renamed.fastq.gz"

  # 4. Filtlong ---------------------------------------------------------------
  # 旧版では小分けのファイルごとに --keep_percent を適用していたが、
  # 「全リードの上位 90% を残す」という意図に合わせ、統合後のリード全体に適用する
  log "[$sample] Filtlong によるフィルタリング"
  filtlong --min_length "$MIN_LENGTH" --keep_percent "$KEEP_PERCENT" \
    "$out/filtered/combined.renamed.fastq.gz" 2> "$logdir/filtlong.log" \
    | gzip > "$out/filtered/filtered.fastq.gz"

  # 5. Flye -------------------------------------------------------------------
  # R10.4.1 を Guppy 5 以降の hac / sup でベースコールしたリードには --nano-hq を用いる
  log "[$sample] Flye によるアセンブリ"
  flye --nano-hq "$out/filtered/filtered.fastq.gz" --out-dir "$out/flye_assembly" \
    --threads "$THREADS" --scaffold \
    > "$logdir/flye.log" 2>&1

  # 6. Medaka -----------------------------------------------------------------
  # Medaka は入力 fasta の隣にインデックス（.fai / .mmi）を作るため、
  # 株ごとのディレクトリ内にコピーしてから実行し、株間で混ざらないようにする
  log "[$sample] Medaka によるポリッシング（モデル: $MEDAKA_MODEL）"
  medaka_input="$out/medaka_input"
  rm -rf "$medaka_input" "$out/medaka"
  mkdir -p "$medaka_input"
  cp "$out/flye_assembly/assembly.fasta" "$medaka_input/assembly.fasta"
  medaka_consensus -i "$out/filtered/filtered.fastq.gz" -d "$medaka_input/assembly.fasta" \
    -o "$out/medaka" -t "$THREADS" -m "$MEDAKA_MODEL" \
    > "$logdir/medaka.log" 2>&1

  # 7. Kleborate --------------------------------------------------------------
  # 【要確認】以下は Kleborate v2 系の書式。v3 系では `kleborate -a <fasta> -o <dir> -p kpsc` となる
  log "[$sample] Kleborate による型別"
  kleborate -a "$out/medaka/consensus.fasta" --all \
    -o "$out/kleborate/kleborate_result.txt" \
    > "$logdir/kleborate.log" 2>&1

  log "[$sample] 完了"
done

log "全株の処理が完了しました"
