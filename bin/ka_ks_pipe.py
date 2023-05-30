#!/bin/python
#ka_ks_pipe.py
#can we get everything in a single script? probably its not that complicated if we aren't throwing to slurm
#Alan E. Yocca
#05-03-2023

import sys
import os
import argparse
#import numpy as np
import warnings
import subprocess
from multiprocessing import Process, Queue

parser = argparse.ArgumentParser(prog='PROG')
parser.add_argument('--a', required=False, help='base of individual a')
parser.add_argument('--b', required=False, help='base of individual b')
parser.add_argument('--prot_a', required=False, help='pep fasta file ref')
parser.add_argument('--prot_b', required=False, help='pep fasta file query')
parser.add_argument('--cds_a', required=False, help='cds fasta file ref')
parser.add_argument('--cds_b', required=False, help='cds fasta file query')
parser.add_argument('--trans', required=False, help='tab delimited translation file')
parser.add_argument('--muscle_cmd', required=False, default="muscle3.8.31_i86linux64", help='path to muscle exe. default appends path of ka_ks_pipe.py script')
parser.add_argument('--pal2nal_cmd', required=False, default = "pal2nal_aey.pl", help='path to pal2nal perl script. default appends path of ka_ks_pipe.py script')
parser.add_argument('--codeml_cmd', required=False, default = "codeml", help='path to codeml executable. default appends path of ka_ks_pipe.py script')
parser.add_argument('--ntasks', required=False, default = 1, help='number of threads')
parser.add_argument('--output', required=True, help='output bed file')

args = parser.parse_args()


#We can use a python multiprocessing library to throw it to like 10 processors, should compare arabidopsis sized proteomes in like an hour????

def check_args(a = "", b = "", prot_a = "", prot_b = "", 
				cds_a = "", cds_b = "", trans = "", output = ""):
	
	if a == None or b == None:
		if prot_a == None or prot_b == None or cds_a == None or cds_b == None or trans == None:
			sys.exit("args misspecified. Please list both a and b OR all of prot_a, prot_b, cds_a, cds_b, and trans")
	if prot_a == None or prot_b == None or cds_a == None or cds_b == None or trans == None:
		if a == None or b == None:
			sys.exit("args misspecified. Please list both a and b OR all of prot_a, prot_b, cds_a, cds_b, and trans")
		else:
			prot_a = a + ".pep"
			prot_b = b + ".pep"
			cds_a = a + ".cds"
			cds_b = b + ".cds"
			trans = a + "_" + b + "_trans.txt"
	
	return(prot_a,prot_b,cds_a,cds_b,trans)

def load_orthologs(trans_file = ""):
	ortho_dict = dict()
	with open(trans_file) as fh:
		for line in fh:
			la = line.strip().split("\t")
			if len(la) != 2:
				warnings.warn('Line of translation file does not have 2 columns, be sure to use a tab-delimited translation file')
			ortho_dict[la[0]] = la[1]
			#this will overwrite entries if gene in first column is represented multiple times, something for the user to consider
	
	return ortho_dict

#for a pair of genes, align the proteins, convert to CDS, then calculate ka/ks
#def extract_prot(prot_a = "", prot_b = "", gene_a = "", gene_b = ""):
	#Alan wrote a script to subset fasta... would be slightly faster to split the entire protein / transcript file into separate files, but that creates many files..?? Screw it lets do that I like speed

#so no extract prot, just align prot and split prot / cds

#maybe I don't use this and just load into memory
def split_fasta(fasta = "", split_dir = "", tag = ""):
	#simple split fasta
	#takes all characters up to the first space? screw it write it all out
	#tag for cds or pep
	header = ""
	seq = ""
	with open(fasta) as fh:
		for line in fh:
			if line.startswith(">"):
				if header != "":
					#write out seq, but skips first time opening file
					with open(split_dir + "/" + header + "_" + tag + ".fasta", 'w') as out:
						tmp = out.write(">" + header + "\n")
						tmp = out.write(seq + "\n")
		
		#write out last entry
		with open(split_dir + "/" + header + "_" + tag + ".fasta", 'w') as out:
			tmp = out.write(">" + header + "\n")
			tmp = out.write(seq + "\n")

#four files.. would be nice if we can have separate? eh
def load_fasta(file = ""):
	#some fasta files are messy, take everything up to the first space? nope, up to user
	header = ""
	out_dict = dict()
	with open(file) as fh:
		for line in fh:
			if line.startswith(">"):
				header = line.strip().replace(">","")
				out_dict[header] = ""
			else:
				out_dict[header] = out_dict[header] + line.strip()
	return(out_dict)


#hmmm seemingly too many arguments huh
#def align_pair_codeml(gene_a = "", gene_b = "", prot_a_dict = dict(), prot_b_dict = dict(),
#				trans_a_dict = dict(), trans_b_dict = dict(), muscle_cmd = "",
#				pal2nal_cmd = ""):

def align_pair_codeml(gene_a, gene_b, prot_a_dict, prot_b_dict, 
						cds_a_dict, cds_b_dict, muscle_cmd, pal2nal_cmd, 
						codeml_cmd, ctl_file, q):
	
	#combine both files into a string, and run muscle 
	prot_string = ">" + gene_a + "\n" + prot_a_dict[gene_a] + "\n" \
					+ ">" + gene_b + "\n" + prot_b_dict[gene_b] + "\n"
	trans_string = ">" + gene_a + "\n" + cds_a_dict[gene_a] + "\n" \
					+ ">" + gene_b + "\n" + cds_b_dict[gene_b] + "\n"

	process = subprocess.Popen([muscle_cmd], stdin=subprocess.PIPE, 
								stdout=subprocess.PIPE, stderr=subprocess.PIPE, 
								text=True)
	#outputs the length of prot string, so store in tmp variable
	tmp = process.stdin.write(prot_string)
	aln, err = process.communicate()
	#need to capture error/output of each gene??? Do I really though?
	#print(process.stdout.read())
	
	#need the standard output, and somehow... pal2nal thats it!
	process = subprocess.Popen([pal2nal_cmd, "-output paml", "-aln", aln, 
								"-cds", trans_string], stdin=subprocess.PIPE, 
								stdout=subprocess.PIPE, stderr=subprocess.PIPE, 
								text=True)
	tran_aln, err = process.communicate()
	
	#write out
	aln_file = gene_a + "_" + gene_b + "_aln.fa"
	with open(aln_file, 'w') as out:
		tmp = out.write(tran_aln)

	#add two lines to ctl file
	outfile = aln_file.replace("aln","codeml")
	
	ctl_string = "seqfile = " + aln_file + "\n"
	ctl_string += "outfile = " + outfile + "\n"
	
	with open(ctl_file) as fh:
		for line in fh:
			ctl_string += line
	
	with open(aln_file + "_codeml.ctl", 'w') as out:
		tmp = out.write(ctl_string)
	
	process = subprocess.Popen([codeml_cmd, aln_file + "_codeml.ctl"],
								stdin=subprocess.PIPE, stdout=subprocess.PIPE, 
								stderr=subprocess.PIPE, text=True)
	out, err = process.communicate()
	
	#parse
	dnds = ""
	dn = ""
	ds = ""
	
	#parse this string
	#t= 2.0023  S=   321.9  N=   917.1  dN/dS=  0.4692  dN = 0.5158  dS = 1.0994
	
	#soooo output is relative to where the ctl file is... soo we need to append the path of the ctl file? eh just screw the whole temp directory thing and throw it all in the cwd
	
	
	with open(outfile) as fh:
		for line in fh:
			if line.startswith("t="):
				la = line.strip().split()
				#lets hope this works
				dnds = la[7]
				dn = la[10]
				ds = la[13]
				
	#remove everything
	#- control file
	#- alignment file
	#codeml output file
	#this might dramatically slow it down... excess i/o??
	#who knows, consider keeping all these files in a tmp directory and cleaning up later
	os.remove(aln_file + "_codeml.ctl")
	os.remove(aln_file)
	os.remove(outfile)
	
	#how to collect these across many processes, these are the numbers I need
	q.put([dnds, dn, ds])

if __name__ == "__main__":
	
	#check args
	prot_a,prot_b,cds_a,cds_b,trans = check_args(a = args.a, b = args.b, 
												 prot_a = args.prot_a, 
												 prot_b = args.prot_b, 
												 cds_a = args.cds_a, 
												 cds_b = args.cds_b, 
												 trans = args.trans, 
												 output = args.output)
	
	#load in all the pep / cds for genome a / b
	prot_a_dict = load_fasta(file = prot_a)
	prot_b_dict = load_fasta(file = prot_b)
	cds_a_dict = load_fasta(file = cds_a)
	cds_b_dict = load_fasta(file = cds_b)
	
	#load translation file
	trans_dict = load_orthologs(trans_file = trans)
	
	file_path = os.path.realpath(__file__)
	file_dir = os.path.dirname(file_path)
	
	if args.muscle_cmd == "muscle3.8.31_i86linux64":
		muscle_cmd = file_dir + "/" + args.muscle_cmd
	if args.pal2nal_cmd == "pal2nal_aey.pl":
		pal2nal_cmd = file_dir + "/" + args.pal2nal_cmd
	if args.codeml_cmd == "codeml":
		codeml_cmd = file_dir + "/" + args.codeml_cmd
	
	#hard code codeml static ctl file
	ctl_file = file_dir + "/codeml.ctl.static" 
	
	#loop lines of the translation file and throw these into different processes
	#limit on the number of processes to launch
	
	dnds = []
	dn = []
	ds = []
	q = Queue()
	processes = []	
	i = 1
	
	ref_list = []
	query_list = []
	for gene_a in trans_dict.keys():
		
		ref_list.append(gene_a)
		query_list.append(trans_dict[gene_a])
		if i % args.ntasks:
			#collect processes and reset queue / procs
			for p in processes:
				lol = q.get()
				dnds.append(lol[0])
				dn.append(lol[1])
				ds.append(lol[2])
			for p in processes:
				p.join()
			
			#reset queue
			q = Queue()
			processes = []
		
		#Ugh... Think these need to be positional??
		p = Process(target=align_pair_codeml, args=(gene_a, 
			trans_dict[gene_a], prot_a_dict, 
			prot_b_dict, cds_a_dict, 
			cds_b_dict, muscle_cmd,
			pal2nal_cmd, codeml_cmd, ctl_file, q))
		
		processes.append(p)
		p.start()
		
		i += 1
	
	#collect stragglers
	for p in processes:
		lol = q.get()
		dnds.append(lol[0])
		dn.append(lol[1])
		ds.append(lol[2])
	
	for p in processes:
		p.join()
	
	with open(args.output, 'w') as out:
		tmp = out.write("Ref\tQuery\tdN\tdS\tdNdS\n")
		for i in range(len(dnds)):
			tmp = out.write(ref_list[i] + "\t" + query_list[i] + "\t" + dn[i] + "\t" +
							ds[i] + "\t" + dnds[i] + "\n")
	










