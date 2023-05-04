## 環境の変更でエラー出現する!

#Outputディレクトリの作成
```
for i in filtered flye_assembly guppy kleborate medaka nano_summary RASTtk; do mkdir -p output/$i; done
```

#guppy
#data：解析対象のfast5fileへのPATH
```
guppy_basecaller --flowcell FLO-MIN106 --kit SQK-RBK004 -x cuda:0 -i data -s output/guppy -r
```

#filtlong
```
for i in $(ls output/guppy/pass/*.fastq | sed -e 's/\.fastq//g' | sed -e 's/output\/guppy\/pass\///g')
do
filtlong --min_length 1000 --keep_percent 90 output/guppy/pass/$i\.fastq | gzip -> output/filtered/$i\.filtered.fastq.gz
done
```

#fastq.gzを統合する、idの重複を修正
```
cat output/filtered/*gz > output/filtered/combined.fastq.gz
seqkit rename output/filtered/combined.fastq.gz > output/filtered/combined.renamed.fastq
```
#flye
```
flye --nano-raw output/filtered/combined.renamed.fastq --out-dir output/flye_assembly --threads 50 --scaffold
```

#medaka
```
#medaka環境を起動
conda activate medaka

#assembly.fastq のミラーイメージをカレントディレクトリに移保存。
cp ./output/flye_assembly/assembly.fasta ./assembly_mirror.fasta

#medaka実行
medaka_consensus -i output/filtered/combined.renamed.fastq -d assembly_mirror.fasta -o output/medaka -t 48 -m r941_min_high_g360

#環境を戻す
conda activate nano_pipe
```

#Kleborate
```
kleborate -a output/medaka/consensus.fasta --all -o output/kleborate/kleborate_result.txt
```




