#!/bin/sh

###################################################################
# Bioinformatic data processing for metabarcoding
# for 16S V4 data, with amplicons generated by following Kozich et al. 2013 AEM
# by Alexander Keller (LMU München)
# email: keller@bio.lmu.de
# if you use this script, please kindly cite this article:
# https://doi.org/10.1098/rstb.2021.0171
###################################################################

# Setting paths of required tools
s=/PATH/TO/SeqFilter
  # Seqfilter: https://github.com/BioInf-Wuerzburg/SeqFilter
ps=/PATH/TO/python_scripts
  # USEARCH python scripts: https://drive5.com/python/python_scripts.tar.gz
vsearch=/PATH/TO/vsearch
  # VSEARCH https://github.com/torognes/vsearch

# Define number of threads to be used throughout the script
threads=5

###################################################################
# no edits anymore
# enter raw data directory
cd $1

# skip preprocessing and only do (re-)classification?
classificationOnly=($(grep "classificationOnly" config.txt | cut -f2 -d"="))
if [ $classificationOnly -ne 1 ]
  then

  #extracting files
  find . -name '*.gz' -print0 | xargs -0 -I {} -P $threads gunzip -d {}
  mkdir -p logs

  # do preprocessing for each sample
  for f in *_R1*.fastq; do

    r=$(sed -e "s/_R1/_R2/" <<< "$f")
    s=$(cut -d_ -f1 <<< "$f")
    p=$(cut -d_ -f2 <<< "$f")
  	total=$(grep "^@M0" $f | wc -l) # Miseq Header Start. Consider changing for other platforms


    echo " "
    echo "===================================="
    echo "Processing sample $s"
    echo "(F: $f R: $r)"
    echo "===================================="

    # merging reads
    $vsearch --fastq_mergepairs  $f --reverse $r --fastq_minovlen 20 --fastq_maxdiffs 10 --fastqout $s.merge.fq --fastq_eeout --relabel R1+2-$s- --threads $threads  2> logs/vsearch.m.$s.log
    var="$(grep "Merged" logs/vsearch.m.$s.log)"
    echo "$s : $var" | tee -a logs/_merging.log

    # q filter reads
    $vsearch --fastq_filter $s.merge.fq \
          --fastq_maxee 1 \
          --fastq_minlen 200 \
          --fastq_maxlen 550 \
          --fastq_maxns 0 \
          --fastaout $s.mergefiltered.fa \
          --fasta_width 0 --threads $threads 2> logs/vsearch.mf.$s.log
    var="$(grep "sequences kept" logs/vsearch.mf.$s.log)"
    echo "$s : $var" | tee -a logs/_filter.log

    # if poor quality of reverse reads, swap strategy to q truncation and filtering
    $vsearch --fastq_truncee 1.5 --fastq_filter $f --fastq_minlen 200 --fastaout $s.trunc.fa --relabel R1-$s- --threads $threads 2> logs/vsearch.tf.$s.log
    var="$(grep "sequences kept" logs/vsearch.tf.$s.log)"
    echo "$s : $var" | tee -a logs/_truncfilter.log

  done

  echo " "
  echo "===================================="
  echo "ASV generation and mapping"
  echo "===================================="

  # Concatenate all samples for defining the ASV pool
  cat *mergefiltered.fa > all.merge.fasta
  cat *trunc.fa > all.trunc.fasta
      # if you want to take only the forward reads, swap all.trunc.fasta out to all.merge.fasta
      # only all.merge.fasta will be processed further
      # headers will differ, so that you will see whether it is R1 or R1+2

  # cleanup
  mkdir -p raw
  mkdir -p tmp

  mv *.fastq raw/
  mv *.fq tmp/
  mv *.fa tmp/

  # Dereplication
  $vsearch --derep_fulllength all.merge.fasta \
    --minuniquesize 2 \
    --sizein \
    --sizeout \
    --fasta_width 0 \
    --uc all.merge.derep.uc \
    --output all.merge.derep.fa --threads $threads 2> logs/_derep.log

  # Denoising
  $vsearch --cluster_unoise  all.merge.derep.fa --sizein --sizeout --centroids zotus.merge_chim.fa --threads $threads 2> logs/_unoise.log
  grep "Clusters" logs/_unoise.log
  grep "Singletons" logs/_unoise.log

  # Chimera removal
  $vsearch --sortbysize zotus.merge_chim.fa --output zotus.merge_sorted.fa --threads $threads 2>  logs/_sort.log
  $vsearch --uchime3_denovo zotus.merge_sorted.fa --abskew 16 --nonchimeras zotus.merge.fa --threads $threads 2>  logs/_uchime.log
  grep "Found" logs/_uchime.log

  # create community table
  cat all.merge.fasta |  sed "s/^>R1+2-\([a-zA-Z0-9-]*\)\-\([0-9]*\)/>R1+2-\1_\2;barcodelabel=\1;/g" > all.merge.bc.fasta
  # Different headers for R1 reads only, change to this:
   # cat all.merge.fasta |  sed "s/^>R1-\([a-zA-Z0-9-]*\)\-\([0-9]*\)/>R1-\1_\2;barcodelabel=\1;/g" > all.merge.bc.fasta

  $vsearch --usearch_global all.merge.bc.fasta --db zotus.merge.fa --strand plus --id 0.97 --uc map.merge.uc --threads $threads 2> logs/_mapping.log
  grep "Matching" logs/_mapping.log
  python2.7 $ps/uc2otutab.py map.merge.uc > asv_table.merge.txt

  # copy final files into folder
  mkdir -p ../$1.import
  cp config.txt ../$1.import/asvs.merge.fa
  cp zotus.merge.fa ../$1.import/asvs.merge.fa
  cp asv_table.merge.txt ../$1.import/asv_table.merge.txt

  # we here create a couple of files that ease sample meta data collection and archiving
  # prepare final project information file
  echo "name;id;own;year;marker;description;participants;doi;repository;accession;ignore" > ../$1.import/project.csv
  echo "$1;$1;1;2020;;;;;;;" >> ../$1.import/project.csv

  # prepare final sample information file
  echo "project;name;host;collectionDate;location;country;bioregion;latitude;longitude;tissue;treatment;sampletype;notes" > ../$1.import/samples.csv
  head -n 1 asv_table.merge.txt | sed -e "s/OTUId[[:space:]]//g" | tr "\t" "\n" | sed "s/^/$1;/"  >> ../$1.import/samples.csv

fi #end classificationOnly


##### Assign taxonomy

  echo " "
  echo "===================================="
  echo "Taxonomic classification"
  echo "===================================="

# Get taxonomy databases from config file
refDBs=($(grep "refdb" config.txt | cut -f2 -d"=" | sed 's/\"//g'))
hieDBs=($(grep "hiedb" config.txt | cut -f2 -d"=" | sed 's/\"//g'))

threshold=97

# create taxonomy file header
echo ",kingdom,phylum,order,family,genus,species" > taxonomy.vsearch
echo ",kingdom,phylum,order,family,genus,species" > taxonomy.blast

# Iterate through databases, first will receive highest assignment priority
# remaining unclassified reads will iterate further

countdb=0
cp  zotus.merge.fa zotus.direct.$countdb.uc.nohit.fasta
prevDB=$countdb
touch taxonomy.vsearch

for db in "${refDBs[@]}"
  do :
    countdb=$((countdb+1))
    echo "\n\n#### Direct VSEARCH Classification level: $countdb";
    $vsearch --usearch_global zotus.direct.$prevDB.uc.nohit.fasta --db $db --id 0.$threshold --uc zotus.direct.$countdb.uc --fastapairs zotus.direct.$countdb.fasta --strand both --threads $threads 2>  logs/_direct.$countdb.log

    grep "^N[[:space:]]" zotus.direct.$countdb.uc | cut -f 9 > zotus.direct.$countdb.uc.nohit
    $s zotus.merge.fa --ids zotus.direct.$countdb.uc.nohit --out zotus.direct.$countdb.uc.nohit.fasta
    cut -f 9,10 zotus.direct.$countdb.uc  | grep -v "*" | sed "s/[A-Za-z0-9]*;tax=//" >> taxonomy.vsearch
    prevDB=$countdb
  done

# unclassified sequences after above iteration will be classified to genus level
echo "\n\n#### Hierarchical VSEARCH classification";

vsearch --sintax zotus.direct.$countdb.uc.nohit.fasta -db $hieDBs -tabbedout zotus.uc.merge.nohit.sintax -strand plus -sintax_cutoff 0.9 -threads $threads 2>  logs/_sintax.log
cut -f1,4 zotus.uc.merge.nohit.sintax | sed -E -e "s/\_[0-9]+//g" -e "s/,s:.*$//"  >> taxonomy.vsearch

# BLAST serves as a backup to check whether global alignments cause errors. Currently not used.
# countdb=0
# cp  zotus.merge.fa zotus.blast.$countdb.uc.nohit.fasta
# prevDB=$countdb
# touch zotus.blast.hits
# touch taxonomy.blast
#
# for db in "${refDBs[@]}"
#   do :
#     countdb=$((countdb+1))
#     echo "\n\n#### Direct BLAST Classification level: $countdb";
#     #makeblastdb -in $db -parse_seqids -blastdb_version 5 -dbtype nucl
#     blastn  -outfmt '6 qseqid sseqid length pident qcovs' -max_target_seqs 1  -query  zotus.blast.$prevDB.uc.nohit.fasta -subject $db -perc_identity $threshold -qcov_hsp_perc 90 -num_threads $threads > zotus.blast.$countdb.out
#     cut -f1 -d"	" zotus.blast.$countdb.out | cut -f1 >> zotus.blast.hits
#   $s zotus.merge.fa --ids-exclude --ids  zotus.blast.hits --out zotus.blast.$countdb.uc.nohit.fasta
#     prevDB=$countdb
#     cut -f 1,2 zotus.blast.$countdb.out >> taxonomy.blast
#
#   done

# final file modifications to load into R
sed -i .bak -e "s/c:.*,o:/o:/g" -e "s/[A-Za-z0-9]*;tax=//" -e "s/	/,/" taxonomy.vsearch
#sed -i .bak -e "s/c:.*,o:/o:/g" -e "s/[A-Za-z0-9]*;tax=//" -e "s/	/,/" taxonomy.blast

# copying files into output directory
cp taxonomy.*  ../$1.import/
sed -i .bak "s/OTUId//" ../$1.import/asv_table.merge.txt