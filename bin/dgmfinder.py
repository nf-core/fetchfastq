#!/usr/bin/env python

import argparse
import gzip
import bio

def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fastq_id")
    parser.add_argument("--fastq_file")
    parser.add_argument("--annfile")
    parser.add_argument("--kmer_size", type=int)
    args = parser.parse_args()
    return args


def main():
    args = get_args()

    with open(args.annfile) as file:
        fasta_list = file.readlines()
        fasta_list = [line.rstrip() for line in lines]

    with gzip.open(args.fqfile, 'rt') as handle:
        head = [next(handle) for x in range(2)]
        read_len = len(head[1].strip())
        distance = read_len - 10 - (2 * args.kmer_size)

    # configure run
    config = bio.Config(
        dist = distance,                # lookahead distance as a function of read length
        kmer_size=args.kmer_size,       # k-mer size used in the analysis
        min_smp_sz=5,                   # minimum sample size to compute p-value
        max_smp_sz=50,                  # maximum number of sequences sampled per
        lmer_size=7,                    # l-mer size used to compute jaccard similarity between k-mers
        jsthrsh=0.25,                   # jaccard similarity threshold used to collapse the observed sequences
        max_fastq_reads=5000000,        # maximum number of FASTQ reads to process
        annot_fasta=fasta_list          # array containing fasta files to use with blast
    )

    # run analysis
    bio.dgmfinder_single_sample_analysis(
        args.fastq_file,
        config,
        args.fastq_id
    )


main()
