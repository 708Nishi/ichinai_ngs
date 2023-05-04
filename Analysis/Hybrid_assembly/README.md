# hybrid assembly

タグ: 2023年5月4日

# Workflow

## WET

1. 核酸抽出、ライブラリ調整
2. Long read sequence
3. Short read Sequence

## Dry

1. 必要ツール
Fastp: ショートリードの品質確認と品質の悪い塩基の除去、アダプターのトリミング
NanoPlot: ロングリードのQC
NanoFilt: ロングリードのトリミング、フィルタリング
Unicycler: アセンブリツール
Pilon: ポリッシングツール
BWA: インデックス作成, マッピング
SAMtools: samをbamに変換する
Bandage: アセンブルグラフを可視化
BBmap：CG, カバレッジの確認
他: CLC 

2. 環境構築

```bash
#環境
mamba create -n hybrid python=3.8

# install
mamba install -c bioconda -y fastp
pip install NanoPlot
pip install NanoPlot --upgrade
mamba install -c bioconda nanofilt
mamba install -c bioconda unicycler
mamba install -bioconda -y bandage
mamba install -c bioconda -y bbmap
```

- 未検証
- 検証済み：fastp, NanoPlot

1. データ
nanoporeデータは統合しておく。

```bash
cat *.fastq > Nanopore.fastq
```

1. ショートリードの品質確認と前処理

```bash
#fastp
fastp -i [imput_shortread1.fastq] -I [imput_shortread2.fastq] -3 -o Read1_trimmed.fastq -O Read2_trimmed.fastq -h report.html -j report.json -q 30 -n 20 -t 1 -T 1 -w 12
```

1. リード分布を確認する。

```bash
NanoPlot --fastq [Nanopore.fastq] --loglength -t 12 -o raw_long_read_quality_check 
```

1. フィルタリング

```bash
#クオリティスコア 10以下とリード長 1000bp以下を除去。リードの先頭50bpのトリミング。
# .gz だとエラーが起こるので解凍してから実行
NanoFilt [Nanopore.fastq] -q 10 --headcrop 50 -l 1000 > nanofilt/Nanopore_trimmed.fastq
```

1. リード分布を再度確認。

```bash
NanoPlot --fastq Nanopore_trimmed.fastq --loglength -t 12 -o raw_long_read_quality_check
```

1. ハイブリッドアセンブル

```bash
unicycler -1 Read1_trimmed.fastq -2 Read2_trimmed_fastq -l Nanopore_trimmed.fastq -o output/Unicycler -t 12
```

1. アセンブルグラフの可視化

```bash
Bandage 
```

別ウインドウが表ひされ、Unicyclerフォルダ内のassembly.gfaファイルを指定して、Draw graphをクリックする。

1. ポリッシング

```bash
#インデックスを作成
#アセンブル後の配列をリファレンスとして、ショートリードマッピングする。
bwa index ./Unicycler/assembly.fasta
bwa mem -t 12 ./Unicycler/assembly.fasta Read1_trimmed.fastq Read2_trimmed.fastq > Short_aln.sam
```

```bash
#samをbamに変換する
samtools view -@ 20 -bS Short_aln.sam | samtools sort -@ 20 -o Short_sorted.bam
```

```bash
#ポリッシング
pilon --genome Unicycler/assembly.fasta --frags Short_sorted.bam --change --outdir Pilon_dir1
```

Pilon_dir1ディレクトリ内にpilon.fastaがポリッシング後の最終塩基

1. 目視・手作業でエラー部位の確認
CLC genomics 等（本書ではGeneiousで実施）
2. アセンブルした配列のサイズやGC・カバレッジを確認

```bash
bbmap.sh ref=/Pilon_dir/pilon.fasta nodisk covstats=mapping.stats in1=Read1_trimmed.fastq in2=Read2_trimmed.fastq
```
