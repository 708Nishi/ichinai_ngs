#!/bin/bash

# 入力データディレクトリ
DATA_DIR="data"
# 出力ディレクトリ
OUTPUT_DIR="output"

# 入力ファイル
ASSEMBLY="$DATA_DIR/assembly.fasta"
READS_1="$DATA_DIR/reads_1.fastq.gz"
READS_2="$DATA_DIR/reads_2.fastq.gz"

# ディレクトリの作成（存在しない場合）
mkdir -p $OUTPUT_DIR

# BWAインデックスの作成
bwa index $ASSEMBLY

# BWAによるショートリードのマッピング
bwa mem $ASSEMBLY $READS_1 $READS_2 > $OUTPUT_DIR/mapped_reads.sam

# SAMtoolsを使用してSAMファイルをBAMファイルに変換
samtools view -S -b $OUTPUT_DIR/mapped_reads.sam > $OUTPUT_DIR/mapped_reads.bam
samtools sort $OUTPUT_DIR/mapped_reads.bam -o $OUTPUT_DIR/sorted_mapped_reads.bam

# インデックスの作成
samtools index $OUTPUT_DIR/sorted_mapped_reads.bam

# Pilonによるポリッシング
java -Xmx16G -jar pilon.jar --genome $ASSEMBLY --frags $OUTPUT_DIR/sorted_mapped_reads.bam --output $OUTPUT_DIR/pilon --changes --vcf --fix all
