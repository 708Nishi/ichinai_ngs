#!/bin/bash

#sample はrawdata2ディレクトリ内にFast5形式で保存されている。

# 処理するディレクトリ名を指定
samples=("Kp03" "Kp16" "Kp32" "Kp40" "Kp53" "Kp58")

for sample in "${samples[@]}"; do
  # Outputディレクトリの確認と作成
  for i in filtered flye_assembly guppy kleborate medaka nano_summary RASTtk; do
    mkdir -p output/$sample/$i
  done

  # guppy
  guppy_basecaller --flowcell FLO-MIN114 --kit SQK-RBK114-24 -x cuda:0 -i rawdata2/$sample -s output/$sample/guppy -r

  # filtlong
  for i in $(ls output/$sample/guppy/pass/*.fastq | sed -e 's/\.fastq//g' | sed -e "s|output/$sample/guppy/pass/||g")
  do
      filtlong --min_length 1000 --keep_percent 90 output/$sample/guppy/pass/$i.fastq | gzip > output/$sample/filtered/$i.filtered.fastq.gz
  done

  # fastq.gzファイルを統合し、idの重複を修正
  cat output/$sample/filtered/*gz > output/$sample/filtered/combined.fastq.gz
  seqkit rename -o output/$sample/filtered/combined.renamed.fastq.gz output/$sample/filtered/combined.fastq.gz

  # flye
  flye --nano-raw output/$sample/filtered/combined.renamed.fastq.gz --out-dir output/$sample/flye_assembly --threads 50 --scaffold

  # assembly.fastaのミラーイメージをカレントディレクトリに保存。
  cp ./output/$sample/flye_assembly/assembly.fasta ./assembly_mirror.fasta

  # medaka実行
  medaka_consensus -i output/$sample/filtered/combined.renamed.fastq.gz -d assembly_mirror.fasta -o output/$sample/medaka -t 48 -m r10_min_high_g340

  # file 移動・名前変更
  mv assembly_mirror.fasta* output/$sample/


done

