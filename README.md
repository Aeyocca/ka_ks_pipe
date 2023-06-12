---
output:
  html_document: default
  pdf_document: default
  word_document: default
---
# ka_ks_pipe

Its called ka_ks_pipe, but this is pretty much just a python wrapper to run codeml on a set of genes.

## Download and install

I am sharing some precompiled binaries for codeml and muscle. I believe these should work on most systems. If not please install yourself.

Copy the github repository

`git clone XXX/ka_ks_pipe.git .`

Create conda environment with necessary packages

`conda create -n ka_ks_pipe environment.yaml`

Activate environment

`conda activate ka_ks_pipe`

Run the test data

`cd ka_ks_pipe/example`

`python ../bin/ka_ks_pipe --a tmp_a --b tmp_b --output tmp_a.tmp_b.ka_ks.txt`

This example should complete within 15 minutes on a single thread

To run with your own data, be sure the following files exist

`${genome_a}.cds 
${genome_a}.pep 
${genome_b}.cds 
${genome_b}.pep 
${genome_a}.${genome_b}.trans.txt`








