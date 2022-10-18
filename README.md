# 16S metabarcoding pipeline
by Alexander Keller (LMU Munich)

A simple script to process metabarcoding 16S V4 data, with amplicons generated by Kozich et al. 2013 AEM

If you use this script, please kindly cite this article: https://doi.org/10.1098/rstb.2021.0171

# What will the script do?

* Un-gzipping files
* Individual sample preparation
  * Merging forward and reverse reads
  * Quality filtering
  * Backup Option: Forward read only use in case of bad quality reverse reads
* Community level processing
  * Dereplication
  * Denoising
  * ASV generation
  * Chimera (de novo) removal
  * Taxonomic classification
    - allows for multiple reference databases (iterative) with decreasing priority
    - all unclassified reads are hierarchically classified
  * Creation of a community table

# Usage:
1) Put all your raw sequencing files (```.fastq``` or ```.fastq.gz```) into a subfolder of where this script is (do not use full paths).

2) Check paths to binaries in the script file

3)You also need to add a ```config.txt``` file, where information about databases are stored. An example is in the example directory.

Then you are ready to run:
```sh
sh _standardized_processing_16S.sh <FOLDER>
```

Results will be in a new subfolder of your current directory called ```<FOLDER>.import```

In case the analysis needs to be reverted, which will remove files and bring the folder structure back to the original state.

```sh
sh _revert_analysis.sh <FOLDER>
```

# Import into R
I will soon post an R script to load in the data and some processing tools.
